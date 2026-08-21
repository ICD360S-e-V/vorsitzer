/// Die drei Vorlagen, mit denen aus dem Ärzte-Tab ein Termin angefragt wird —
/// samt der Fachtabelle, die aus „Termin" den Anlass macht, den die jeweilige
/// Praxis auch versteht.
///
/// WARUM DREI UND NICHT EINE
/// Bis hierher gab es genau zwei Textbausteine: „Klinik" und „alles andere".
/// Ein Gastroenterologe bekam damit dieselbe Bitte um eine
/// „Vorsorgeuntersuchung" wie ein Zahnarzt — und eine Anmeldung, die einen
/// Anlass nicht einordnen kann, ruft zurück oder legt weg. Die drei Vorlagen
/// trennen die drei Fälle, die eine Anmeldung wirklich unterschiedlich
/// behandelt:
///
///  * [TerminanfrageVorlage.erstvorstellung] — der Mensch war dort noch nie.
///    Die Praxis muss entscheiden, ob sie überhaupt aufnimmt.
///  * [TerminanfrageVorlage.kontrolle] — bekannter Patient, planbarer Termin
///    (Vorsorge, Verlaufskontrolle, Nachsorge). Darf in vier Wochen sein.
///  * [TerminanfrageVorlage.akut] — Beschwerden jetzt. Die Bitte lautet auf
///    einen kurzfristigen Termin.
///
/// ⚠️ KEINE BEHAUPTUNG OHNE DECKUNG. Die alte Fassung schrieb in jeden
/// Klinikbrief „Eine Überweisung des behandelnden Arztes liegt vor / wird
/// nachgereicht." — ohne dass irgendjemand das geprüft hätte. Wer so etwas an
/// eine Ambulanz faxt und dann ohne Überweisung dasteht, hat den Termin
/// umsonst. Deshalb ist [ArztFach.ueberweisungUeblich] nur die Voreinstellung
/// des Kästchens; der Satz erscheint ausschließlich, wenn er bestätigt wurde.
///
/// ⚠️ Und keine Überweisungspflicht erfinden: § 76 Abs. 1 SGB V lässt die
/// freie Arztwahl unter den Vertragsärzten. Verlangt wird eine Überweisung nur
/// für wenige Fächer (u. a. Labor, Radiologie, Pathologie) — überall sonst ist
/// sie üblich, nicht vorgeschrieben. Das Feld heißt deshalb
/// `ueberweisungUeblich` und nicht `ueberweisungNoetig`.
library;

/// Das Zeitfenster des Vereins — eine Quelle, nicht in jedem Brief neu
/// getippt.
///
/// 🔴 ES IST DAS FENSTER DES VEREINS, NICHT DAS DES PATIENTEN.
/// In diesen Stunden ist der ehrenamtliche Verein besetzt, und nur in diesen
/// Stunden kann jemand **mitkommen** — zum Übersetzen und als Begleitung.
/// Deshalb steht es an zwei Stellen im Brief, und zwar mit zwei verschiedenen
/// Aussagen: als Rückrufzeit hinter der Telefonnummer, und als Bitte um die
/// Terminlage. Ein Termin um 9 Uhr ist für einen Menschen, der kein Deutsch
/// spricht, ein Termin ohne Übersetzung.
///
/// ⚠️ „montags bis freitags", nicht „werktags": werktags schließt den Samstag
/// ein, und samstags ist hier niemand. Eine Praxis, die sich auf ein Fenster
/// verlässt, das nicht stimmt, ruft genau einmal an.
const String kVereinErreichbarkeit = 'montags bis freitags von 14 bis 17 Uhr';

/// In wessen Namen der Text steht.
///
/// 🔴 DER GRUND, WARUM ES ZWEI GIBT — und warum eine Fassung für beide Wege
/// falsch wäre:
///
///  * Das **Fax** ist ein Brief DES MITGLIEDS. Im PDF steht oben sein
///    Absenderblock mit seiner Anschrift, unten seine Grußformel und sein
///    Name. „Ich bitte um einen Termin" ist dort richtig.
///  * Die **E-Mail** geht aus dem Vereinspostfach hinaus, und darunter hängt
///    die Signatur eines Vorstandsmitglieds — mit dessen Namen. Steht im Text
///    darüber „Mit freundlichen Grüßen / Olena Shevchenko" und darunter
///    „Ionut-Claudiu Duinea, Vorstand", dann unterschreiben **zwei
///    verschiedene Menschen dieselbe Mail**. Das sieht nicht nach Sorgfalt
///    aus, sondern nach einem Serienbrief, bei dem jemand vergessen hat,
///    einen Platzhalter zu ersetzen.
///
/// In der Wir-Fassung trägt die Signatur den Abschluss, das Mitglied wird im
/// Angabenblock genannt — dort, wo die Anmeldung es ohnehin sucht — und der
/// Text sagt ausdrücklich, für wen geschrieben wird.
enum TerminanfrageStimme {
  /// Das Mitglied schreibt selbst — für das Fax-PDF.
  ich,

  /// Der Verein schreibt für das Mitglied — für die E-Mail.
  wir,
}

/// Welche der drei Vorlagen gewählt ist.
enum TerminanfrageVorlage {
  /// Erster Termin in dieser Praxis — die Aufnahme selbst ist die Frage.
  erstvorstellung,

  /// Planbarer Termin bei bekanntem Patienten: Vorsorge, Verlaufskontrolle,
  /// Nachsorge. Was davon, entscheidet die Fachrichtung.
  kontrolle,

  /// Akute Beschwerden, Bitte um einen kurzfristigen Termin.
  akut,
}

extension TerminanfrageVorlageX on TerminanfrageVorlage {
  /// Schlüssel für Datenbank und Protokoll — stabil, nicht die Beschriftung.
  String get schluessel => switch (this) {
        TerminanfrageVorlage.erstvorstellung => 'erstvorstellung',
        TerminanfrageVorlage.kontrolle => 'kontrolle',
        TerminanfrageVorlage.akut => 'akut',
      };

  /// Was im Auswahlband steht.
  String get titel => switch (this) {
        TerminanfrageVorlage.erstvorstellung => 'Erstvorstellung',
        TerminanfrageVorlage.kontrolle => 'Kontrolle / Vorsorge',
        TerminanfrageVorlage.akut => 'Akuttermin',
      };

  /// Eine Zeile darunter, damit die Wahl ohne Raten getroffen werden kann.
  String get erklaerung => switch (this) {
        TerminanfrageVorlage.erstvorstellung =>
          'Erster Termin in dieser Praxis',
        TerminanfrageVorlage.kontrolle =>
          'Bekannter Patient, planbarer Termin',
        TerminanfrageVorlage.akut => 'Beschwerden jetzt, kurzfristiger Termin',
      };

  static TerminanfrageVorlage vonSchluessel(String s) => switch (s) {
        'erstvorstellung' => TerminanfrageVorlage.erstvorstellung,
        'akut' => TerminanfrageVorlage.akut,
        _ => TerminanfrageVorlage.kontrolle,
      };
}

/// Ob ein Anlass eine Beschwerde ist oder ein Anliegen.
///
/// Der Unterschied ist nicht kosmetisch, er ist grammatisch: „Es bestehen
/// Zahnschmerzen" ist richtig, „Es besteht eine professionelle Zahnreinigung"
/// ist Unsinn. Aus [beschwerde] wird ein „Es bestehen …"-Satz, aus [anliegen]
/// ein „Anlass ist …"-Satz.
enum AnlassArt { beschwerde, anliegen }

/// Ein auswählbarer Grund für den Termin.
///
/// ⚠️ [phrase] ist eine Nominalphrase ohne Punkt und ohne Satzanfang — sie
/// wird mit anderen in einen Satz eingereiht. Wer hier einen ganzen Satz
/// hinterlegt, bekommt „Es bestehen Es tut der Zahn weh."
class TerminAnlass {
  /// Was auf dem Knopf steht.
  final String kurz;

  /// Wie es im Brief eingereiht wird.
  final String phrase;

  final AnlassArt art;

  const TerminAnlass(this.kurz, this.phrase, [this.art = AnlassArt.beschwerde]);

  /// Kurzform, wenn Knopf und Briefwort dasselbe sind.
  const TerminAnlass.gleich(this.kurz, [this.art = AnlassArt.beschwerde])
      : phrase = kurz;
}

/// Was eine Fachrichtung aus den drei Vorlagen macht.
class ArztFach {
  /// Wie das Fach im Brief heißt („gastroenterologisch", „HNO-ärztlich").
  final String bezeichnung;

  /// Anlass der Erstvorstellung, als Fortsetzung von „bitte ich um einen
  /// Termin …".
  final String erstAnlass;

  /// Anlass des planbaren Termins.
  final String kontrolleAnlass;

  /// Ein Satz mehr zum planbaren Termin, wenn es dafür eine benannte Leistung
  /// gibt (Check-up, Hautkrebs-Screening, Koloskopie …). Leer = kein Zusatz.
  final String kontrolleZusatz;

  /// Anlass des Akuttermins.
  final String akutAnlass;

  /// Ob in diesem Fach üblicherweise mit Überweisung vorgestellt wird.
  /// ⚠️ Nur Voreinstellung des Kästchens — siehe Kopf dieser Datei.
  final bool ueberweisungUeblich;

  /// Wie das mitgebrachte Papier in diesem Fach heißt.
  ///
  /// ⚠️ Beim Sanitätshaus ist es KEINE Überweisung, sondern eine ärztliche
  /// Verordnung (Rezept) nach § 33 SGB V — ohne sie zahlt die Kasse nichts,
  /// und wer „Überweisung" schreibt, sagt dem Sanitätshaus das eine Wort
  /// nicht, auf das es wartet.
  final String belegName;

  /// Ein Satz, der nur zusammen mit dem Beleg erscheint — dort, wo an dem
  /// Papier eine Frist hängt.
  ///
  /// ⚠️ Beim Sanitätshaus ist das der eigentliche Grund zur Eile: eine
  /// Hilfsmittelverordnung (Muster 16) gilt **28 Kalendertage** ab
  /// Ausstellung, nach einer Krankenhausentlassung nur **sieben**. Wer den
  /// Termin in fünf Wochen bekommt, braucht ein neues Rezept — also einen
  /// neuen Arzttermin für dasselbe Hilfsmittel. Der Satz erscheint nur, wenn
  /// das Rezept auch angekreuzt ist; ohne Rezept wäre er eine Frist ohne
  /// Anlass.
  final String belegZusatz;

  /// Wie der Empfänger im Fließtext benannt wird — MIT Präposition, weil die
  /// nicht überall dieselbe ist: „in Ihrer Praxis", aber „bei Ihrem
  /// Sanitätshaus".
  ///
  /// ⚠️ Nicht kosmetisch. „Besteht in Ihrer Praxis bereits eine
  /// Patientenakte" an ein Sanitätshaus zeigt sofort, dass da ein Formular
  /// gelaufen ist und kein Mensch geschrieben hat — und wer das merkt, liest
  /// den Rest anders.
  final String stelleDativ;

  /// Die auswählbaren Gründe. Mindestens fünf je Fach, damit der häufige Fall
  /// wirklich dabei ist und niemand tippen muss; das Freitextfeld bleibt
  /// trotzdem, weil keine Liste alles trifft.
  final List<TerminAnlass> anlaesse;

  const ArztFach({
    required this.bezeichnung,
    required this.erstAnlass,
    required this.kontrolleAnlass,
    this.kontrolleZusatz = '',
    required this.akutAnlass,
    this.ueberweisungUeblich = true,
    this.belegName = 'Überweisung',
    this.belegZusatz = '',
    this.stelleDativ = 'in Ihrer Praxis',
    this.anlaesse = const [],
  });
}

/// Fachtabelle für alle 21 Ärzte-Tabs, die einen Anfrage-Knopf haben.
///
/// ⚠️ Die Schlüssel sind dieselben `arzt_type`-Werte, mit denen auch
/// `saveArztTermin` und die Tabellen arbeiten. Ein Tippfehler fällt nicht
/// auf — er landet still bei [_fachSonstige]. `test/terminanfrage_test.dart`
/// hält die Liste deshalb gegen die Tab-Liste des Bildschirms.
///
/// HERKUNFT DER ANLÄSSE
/// Keine Erfindung am Schreibtisch: Grundlage sind die veröffentlichten
/// Beratungsanlässe und Leitsymptome der jeweiligen Fächer — für die
/// Hausarztpraxis die Verteilung Bewegungsapparat 30,6 % / Abdomen 14,3 % /
/// Atemwege 13,3 % / grippale Infekte 12,6 % / psychisch 7,4 % und die
/// chronischen Diagnosen Schilddrüse, Hypertonie, Diabetes (DEGAM-Kongress
/// 2018, Primärdatenanalyse); für Reflux die Angabe, dass 20–40 % der
/// westlichen Bevölkerung wöchentlich Sodbrennen und saures Aufstoßen haben;
/// für Neurologie Kopfschmerz, motorische Defizite, Schwindel, Anfälle;
/// Schwindel mit 20–30 % Lebenszeitprävalenz zugleich als HNO-Leitsymptom;
/// Juckreiz als fachübergreifendes Leitsymptom der Dermatosen.
const Map<String, ArztFach> kArztFaecher = {
  // ── Grundversorgung ────────────────────────────────────────────────
  'gesundheit_hausarzt': ArztFach(
    bezeichnung: 'hausärztlich',
    erstAnlass: 'zur hausärztlichen Erstvorstellung und Aufnahme in Ihre Praxis',
    kontrolleAnlass: 'zur Gesundheitsuntersuchung (Check-up)',
    kontrolleZusatz:
        'Es geht um die Gesundheitsuntersuchung nach § 25 Abs. 1 SGB V.',
    akutAnlass: 'wegen akuter Beschwerden',
    // Der Hausarzt ist die Stelle, die überweist — nicht die, zu der man
    // überwiesen wird.
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass('Erkältung / Husten / Fieber',
          'Husten, Fieber und Erkältungsbeschwerden'),
      TerminAnlass.gleich('Rücken- oder Gelenkschmerzen'),
      TerminAnlass('Bluthochdruck', 'ein zu hoher Blutdruck'),
      TerminAnlass('Bauch- / Magen-Darm-Beschwerden',
          'Bauchschmerzen und Magen-Darm-Beschwerden'),
      TerminAnlass('Müdigkeit / Erschöpfung',
          'anhaltende Müdigkeit und Erschöpfung'),
      TerminAnlass('Blutbild / Laborkontrolle', 'eine Laborkontrolle',
          AnlassArt.anliegen),
      TerminAnlass('Folgerezept / Dauermedikation',
          'ein Folgerezept für die Dauermedikation', AnlassArt.anliegen),
      TerminAnlass('Überweisung zum Facharzt',
          'eine Überweisung zum Facharzt', AnlassArt.anliegen),
      TerminAnlass('Impfung', 'eine Impfung', AnlassArt.anliegen),
      TerminAnlass('Krankschreibung (AU)',
          'eine Arbeitsunfähigkeitsbescheinigung', AnlassArt.anliegen),
    ],
  ),

  // ── Fachärzte mit direktem Zugang ──────────────────────────────────
  'gesundheit_augenarzt': ArztFach(
    bezeichnung: 'augenärztlich',
    erstAnlass: 'zur augenärztlichen Erstvorstellung',
    kontrolleAnlass: 'zur augenärztlichen Kontrolluntersuchung',
    kontrolleZusatz:
        'Gewünscht sind Sehschärfe, Augeninnendruck und Beurteilung des '
        'Augenhintergrundes.',
    akutAnlass: 'wegen einer akuten Sehverschlechterung',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass.gleich('Sehverschlechterung'),
      TerminAnlass.gleich('Augenschmerzen'),
      TerminAnlass('Trockene / brennende Augen', 'trockene, brennende Augen'),
      TerminAnlass('Rotes, gereiztes Auge', 'ein rotes, gereiztes Auge'),
      TerminAnlass.gleich('Doppelbilder'),
      // ⚠️ Lichtblitze und „Rußregen" sind die Warnzeichen einer
      // Netzhautablösung — das ist ein Fall für heute, nicht für „in vier
      // Wochen". Der Text sagt das mit, damit die Anmeldung es einordnet.
      TerminAnlass('Lichtblitze / „Rußregen"',
          'Lichtblitze und Rußregen — mit Verdacht auf eine Netzhautablösung'),
      TerminAnlass('Brille / Kontaktlinsen',
          'eine Bestimmung für Brille oder Kontaktlinsen', AnlassArt.anliegen),
      TerminAnlass('Augeninnendruck (Glaukom)',
          'eine Kontrolle des Augeninnendrucks', AnlassArt.anliegen),
      TerminAnlass('Netzhautkontrolle bei Diabetes',
          'die Netzhautkontrolle bei Diabetes', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_zahnarzt': ArztFach(
    bezeichnung: 'zahnärztlich',
    erstAnlass: 'zur zahnärztlichen Erstvorstellung',
    kontrolleAnlass: 'zur zahnärztlichen Kontrolluntersuchung',
    kontrolleZusatz:
        'Die Untersuchung soll zugleich im Bonusheft nach § 55 Abs. 1 SGB V '
        'eingetragen werden.',
    akutAnlass: 'wegen akuter Zahnschmerzen',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass.gleich('Zahnschmerzen'),
      TerminAnlass('Zahnfleischbluten', 'Zahnfleischbluten und -entzündung'),
      TerminAnlass('Kälteempfindliche Zähne', 'kälteempfindliche Zähne'),
      TerminAnlass('Abgebrochener Zahn / Füllung',
          'ein abgebrochener Zahn bzw. eine verlorene Füllung'),
      TerminAnlass('Probleme mit dem Zahnersatz',
          'Beschwerden mit dem Zahnersatz'),
      TerminAnlass('Kontrolle + Bonusheft',
          'die Kontrolluntersuchung mit Eintrag ins Bonusheft',
          AnlassArt.anliegen),
      TerminAnlass('Professionelle Zahnreinigung',
          'eine professionelle Zahnreinigung', AnlassArt.anliegen),
      TerminAnlass('Heil- und Kostenplan',
          'ein Heil- und Kostenplan', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_gynaekologie': ArztFach(
    bezeichnung: 'gynäkologisch',
    erstAnlass: 'zur gynäkologischen Erstvorstellung',
    kontrolleAnlass: 'zur gynäkologischen Krebsfrüherkennungsuntersuchung',
    kontrolleZusatz:
        'Es geht um die Früherkennungsuntersuchung nach § 25 Abs. 2 SGB V.',
    akutAnlass: 'wegen akuter gynäkologischer Beschwerden',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass.gleich('Unterleibsschmerzen'),
      TerminAnlass('Zyklusstörungen', 'Zyklusstörungen und unregelmäßige '
          'Blutungen'),
      TerminAnlass('Ausfluss / Brennen', 'Ausfluss und Brennen'),
      TerminAnlass('Knoten in der Brust', 'ein tastbarer Knoten in der Brust'),
      TerminAnlass.gleich('Wechseljahresbeschwerden'),
      TerminAnlass.gleich('Inkontinenz'),
      // ⚠️ Verhütung steht ganz oben, weil sie der häufigste Anlass
      // überhaupt ist: rund vier von zehn Terminen in der gynäkologischen
      // Praxis drehen sich darum. Eine Liste, die den häufigsten Fall an
      // achter Stelle führt, zwingt zum Suchen.
      TerminAnlass('Verhütungsberatung',
          'eine Beratung zur Verhütung', AnlassArt.anliegen),
      TerminAnlass('Krebsfrüherkennung',
          'die Krebsfrüherkennungsuntersuchung', AnlassArt.anliegen),
      TerminAnlass('Schwangerschaft / Mutterpass',
          'die Betreuung in der Schwangerschaft', AnlassArt.anliegen),
    ],
  ),

  // ── Fachärzte, bei denen die Überweisung üblich ist ────────────────
  'gesundheit_lungenarzt': ArztFach(
    bezeichnung: 'pneumologisch',
    erstAnlass: 'zur pneumologischen Erstvorstellung',
    kontrolleAnlass: 'zur pneumologischen Verlaufskontrolle',
    kontrolleZusatz: 'Gewünscht ist unter anderem eine Lungenfunktionsprüfung.',
    akutAnlass: 'wegen akuter Atembeschwerden',
    anlaesse: [
      TerminAnlass('Atemnot / Luftnot', 'Atemnot, auch bei geringer Belastung'),
      TerminAnlass('Anhaltender Husten', 'ein seit Längerem bestehender Husten'),
      TerminAnlass('Pfeifende Atmung / Asthma',
          'pfeifende Atmung mit Verdacht auf Asthma'),
      TerminAnlass('Wiederkehrende Bronchitis',
          'wiederkehrende Bronchitis mit Auswurf'),
      TerminAnlass('Verdacht auf COPD', 'ein Verdacht auf COPD'),
      TerminAnlass('Schlafapnoe / Schnarchen',
          'Schnarchen mit Atemaussetzern im Schlaf'),
      TerminAnlass('Lungenfunktionstest',
          'eine Lungenfunktionsprüfung', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_hno': ArztFach(
    bezeichnung: 'HNO-ärztlich',
    erstAnlass: 'zur HNO-ärztlichen Erstvorstellung',
    kontrolleAnlass: 'zur HNO-ärztlichen Kontrolluntersuchung',
    kontrolleZusatz: 'Gewünscht ist unter anderem eine Hörprüfung.',
    akutAnlass: 'wegen akuter Beschwerden im HNO-Bereich',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass.gleich('Ohrenschmerzen'),
      // ⚠️ Ein Hörsturz gehört in Tage, nicht in Wochen — steht deshalb im
      // Satz mit drin und nicht nur auf dem Knopf.
      TerminAnlass('Hörverlust / Hörsturz',
          'ein plötzlicher Hörverlust mit Verdacht auf einen Hörsturz'),
      TerminAnlass('Ohrgeräusche (Tinnitus)', 'Ohrgeräusche (Tinnitus)'),
      TerminAnlass.gleich('Schwindel'),
      TerminAnlass('Nasennebenhöhlen / Schnupfen',
          'anhaltender Schnupfen mit Verdacht auf eine '
          'Nasennebenhöhlenentzündung'),
      TerminAnlass('Halsschmerzen / Schluckbeschwerden',
          'Halsschmerzen und Schluckbeschwerden'),
      TerminAnlass('Heiserkeit', 'eine anhaltende Heiserkeit'),
      TerminAnlass('Behinderte Nasenatmung', 'eine behinderte Nasenatmung'),
      TerminAnlass('Allergietest', 'ein Allergietest', AnlassArt.anliegen),
      TerminAnlass('Hörgeräteversorgung',
          'eine Hörgeräteversorgung', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_psychiater': ArztFach(
    bezeichnung: 'psychiatrisch',
    erstAnlass: 'zu einem Erstgespräch',
    kontrolleAnlass: 'zu einem Kontrolltermin',
    akutAnlass: 'wegen einer akuten Verschlechterung des Befindens',
    ueberweisungUeblich: false,
    // ⚠️ Hier ist die Auswahl besonders zurückhaltend zu benutzen: für einen
    // Termin muss niemand seine Diagnose auf ein Fax schreiben. Der Dialog
    // weist bei diesem Fach eigens darauf hin; die Liste ist da, weil manche
    // Praxen ohne Angabe gar nicht erst zurückrufen.
    anlaesse: [
      TerminAnlass('Niedergeschlagenheit',
          'anhaltende Niedergeschlagenheit und Antriebslosigkeit'),
      TerminAnlass('Angst / Panik', 'Angst- und Panikzustände'),
      TerminAnlass.gleich('Schlafstörungen'),
      TerminAnlass('Anhaltende Anspannung',
          'anhaltende Anspannung und Stressbelastung'),
      TerminAnlass('Konzentrationsprobleme',
          'Konzentrations- und Gedächtnisprobleme'),
      TerminAnlass('Belastung nach schwerem Erlebnis',
          'eine anhaltende Belastung nach einem schweren Erlebnis'),
      TerminAnlass('Suchtproblematik', 'eine Suchtproblematik'),
      TerminAnlass('Medikamenteneinstellung',
          'die Einstellung und Kontrolle der Medikation', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_kardiologe': ArztFach(
    bezeichnung: 'kardiologisch',
    erstAnlass: 'zur kardiologischen Erstvorstellung',
    kontrolleAnlass: 'zur kardiologischen Verlaufskontrolle',
    kontrolleZusatz: 'Gewünscht sind unter anderem EKG und Echokardiographie.',
    akutAnlass: 'wegen akuter Herzbeschwerden',
    anlaesse: [
      // ⚠️ Ausstrahlender Brustschmerz ist das Leitsymptom der koronaren
      // Durchblutungsstörung. Steht er im Text, weiß die Anmeldung, dass das
      // kein Vier-Wochen-Termin ist.
      TerminAnlass('Brustschmerz / Engegefühl',
          'Schmerzen und ein Engegefühl im Brustkorb, teils ausstrahlend'),
      TerminAnlass('Atemnot bei Belastung', 'Atemnot bei Belastung'),
      TerminAnlass('Herzstolpern / Herzrasen', 'Herzstolpern und Herzrasen'),
      TerminAnlass('Bluthochdruck', 'ein zu hoher Blutdruck'),
      TerminAnlass('Wasser in den Beinen',
          'Wassereinlagerungen in den Beinen'),
      TerminAnlass('Schwindel / Ohnmacht', 'Schwindel bis hin zur Ohnmacht'),
      TerminAnlass('Kontrolle nach Infarkt / Stent',
          'die Verlaufskontrolle nach Herzinfarkt bzw. Stent',
          AnlassArt.anliegen),
    ],
  ),
  'gesundheit_neurologe': ArztFach(
    bezeichnung: 'neurologisch',
    erstAnlass: 'zur neurologischen Erstvorstellung',
    kontrolleAnlass: 'zur neurologischen Verlaufskontrolle',
    akutAnlass: 'wegen akuter neurologischer Beschwerden',
    anlaesse: [
      TerminAnlass('Kopfschmerzen / Migräne', 'Kopfschmerzen bzw. Migräne'),
      TerminAnlass.gleich('Schwindel'),
      TerminAnlass('Taubheitsgefühl / Kribbeln',
          'Taubheitsgefühl und Kribbeln in Armen oder Beinen'),
      TerminAnlass('Kraftverlust / Lähmung',
          'Kraftverlust bzw. Lähmungserscheinungen'),
      TerminAnlass('Krampfanfall', 'ein Krampfanfall'),
      TerminAnlass('Gedächtnisstörungen',
          'Gedächtnis- und Konzentrationsstörungen'),
      TerminAnlass('Zittern (Tremor)', 'ein Zittern der Hände'),
    ],
  ),
  'gesundheit_orthopaede': ArztFach(
    bezeichnung: 'orthopädisch',
    erstAnlass: 'zur orthopädischen Erstvorstellung',
    kontrolleAnlass: 'zur orthopädischen Verlaufskontrolle',
    akutAnlass: 'wegen akuter Schmerzen im Bewegungsapparat',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass.gleich('Rückenschmerzen'),
      TerminAnlass('Nacken- / Schulterschmerzen',
          'Nacken- und Schulterschmerzen'),
      TerminAnlass.gleich('Knieschmerzen'),
      TerminAnlass.gleich('Hüftschmerzen'),
      TerminAnlass('Geschwollenes Gelenk', 'ein geschwollenes Gelenk'),
      TerminAnlass('Arthrose / Verschleiß',
          'Beschwerden durch Gelenkverschleiß (Arthrose)'),
      TerminAnlass('Schmerzen nach Sturz / Unfall',
          'Schmerzen nach einem Sturz bzw. Unfall'),
      TerminAnlass('Verordnung Physiotherapie',
          'eine Verordnung für Physiotherapie', AnlassArt.anliegen),
      TerminAnlass('Kontrolle nach Operation',
          'die Kontrolle nach einer Operation', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_hautarzt': ArztFach(
    bezeichnung: 'dermatologisch',
    erstAnlass: 'zur dermatologischen Erstvorstellung',
    kontrolleAnlass: 'zum Hautkrebs-Screening',
    kontrolleZusatz:
        'Es geht um die Früherkennungsuntersuchung auf Hautkrebs nach '
        '§ 25 Abs. 2 SGB V.',
    akutAnlass: 'wegen einer akuten Hautveränderung',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass('Juckreiz', 'anhaltender Juckreiz'),
      TerminAnlass('Hautausschlag', 'ein Hautausschlag'),
      TerminAnlass('Auffälliges Muttermal',
          'ein auffälliges, verändertes Muttermal'),
      TerminAnlass('Ekzem / Neurodermitis', 'ein Ekzem bzw. Neurodermitis'),
      TerminAnlass('Schuppenflechte', 'eine Schuppenflechte (Psoriasis)'),
      TerminAnlass.gleich('Akne'),
      TerminAnlass('Haarausfall', 'ein zunehmender Haarausfall'),
      TerminAnlass('Nagelveränderung / Nagelpilz',
          'eine Nagelveränderung mit Verdacht auf Nagelpilz'),
      TerminAnlass('Hautkrebs-Screening',
          'das Hautkrebs-Screening', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_urologie': ArztFach(
    bezeichnung: 'urologisch',
    erstAnlass: 'zur urologischen Erstvorstellung',
    kontrolleAnlass: 'zur urologischen Krebsfrüherkennungsuntersuchung',
    kontrolleZusatz:
        'Es geht um die Früherkennungsuntersuchung nach § 25 Abs. 2 SGB V.',
    akutAnlass: 'wegen akuter urologischer Beschwerden',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass('Brennen beim Wasserlassen', 'Brennen beim Wasserlassen'),
      TerminAnlass('Häufiger Harndrang',
          'häufiger Harndrang, auch nachts'),
      TerminAnlass('Blut im Urin', 'Blut im Urin'),
      TerminAnlass('Prostatabeschwerden', 'Prostatabeschwerden'),
      TerminAnlass('Nierenschmerzen / Steine',
          'Nierenschmerzen mit Verdacht auf Steine'),
      TerminAnlass.gleich('Erektionsstörungen'),
      TerminAnlass('Inkontinenz', 'eine nachlassende Kontinenz'),
      TerminAnlass('Krebsfrüherkennung',
          'die Krebsfrüherkennungsuntersuchung', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_onkologie': ArztFach(
    bezeichnung: 'onkologisch',
    erstAnlass: 'zur onkologischen Erstvorstellung',
    kontrolleAnlass: 'zum Nachsorgetermin',
    kontrolleZusatz: 'Der Termin dient der Tumornachsorge.',
    akutAnlass: 'wegen einer akuten Verschlechterung',
    anlaesse: [
      TerminAnlass('Nachsorge laut Plan',
          'der nach dem Nachsorgeplan fällige Termin', AnlassArt.anliegen),
      TerminAnlass('Kontrolle der Blutwerte',
          'eine Kontrolle der Blutwerte', AnlassArt.anliegen),
      TerminAnlass('Befundbesprechung',
          'die Besprechung eines Befundes', AnlassArt.anliegen),
      TerminAnlass('Fortsetzung der Therapie',
          'die Fortsetzung der Therapie', AnlassArt.anliegen),
      TerminAnlass('Nebenwirkungen der Behandlung',
          'Nebenwirkungen der laufenden Behandlung'),
      TerminAnlass('Zweitmeinung', 'eine Zweitmeinung', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_endokrinologie': ArztFach(
    bezeichnung: 'endokrinologisch',
    erstAnlass: 'zur endokrinologischen Erstvorstellung',
    kontrolleAnlass: 'zur endokrinologischen Verlaufskontrolle',
    kontrolleZusatz:
        'Gewünscht ist eine Kontrolle der Schilddrüsen- und Hormonwerte.',
    akutAnlass: 'wegen akuter Beschwerden',
    anlaesse: [
      TerminAnlass('Schilddrüsenwerte',
          'auffällige Schilddrüsenwerte mit Verdacht auf eine Über- oder '
          'Unterfunktion'),
      TerminAnlass('Knoten in der Schilddrüse',
          'ein Knoten in der Schilddrüse'),
      TerminAnlass('Druckgefühl im Hals',
          'ein Druckgefühl im Hals mit Schluckbeschwerden und Heiserkeit'),
      TerminAnlass('Gewichtszunahme / -abnahme',
          'eine ungewollte Gewichtszunahme bzw. -abnahme'),
      TerminAnlass('Erschöpfung / Kälteempfindlichkeit',
          'Erschöpfung und Kälteempfindlichkeit'),
      TerminAnlass('Hormon- / Zyklusstörung',
          'eine Hormon- bzw. Zyklusstörung'),
      TerminAnlass('Osteoporose-Abklärung',
          'eine Abklärung auf Osteoporose', AnlassArt.anliegen),
      TerminAnlass('Kontrolle der Hormonmedikation',
          'die Kontrolle der Hormonmedikation', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_diabetologie': ArztFach(
    bezeichnung: 'diabetologisch',
    erstAnlass: 'zur diabetologischen Erstvorstellung',
    kontrolleAnlass: 'zum diabetologischen Quartalstermin',
    kontrolleZusatz:
        'Der Termin gehört zur strukturierten Behandlung im DMP Diabetes '
        'mellitus.',
    akutAnlass: 'wegen entgleister Blutzuckerwerte',
    anlaesse: [
      TerminAnlass('Erhöhte Blutzuckerwerte', 'erhöhte Blutzuckerwerte'),
      TerminAnlass('Unterzuckerungen', 'wiederholte Unterzuckerungen'),
      TerminAnlass('Diabetischer Fuß', 'eine Wunde am Fuß bei Diabetes'),
      TerminAnlass('Quartalskontrolle (DMP)',
          'die Quartalskontrolle im DMP', AnlassArt.anliegen),
      TerminAnlass('HbA1c-Kontrolle',
          'eine HbA1c-Kontrolle', AnlassArt.anliegen),
      TerminAnlass('Jährliche Fußuntersuchung',
          'die jährliche Fußuntersuchung', AnlassArt.anliegen),
      TerminAnlass('Einstellung der Insulintherapie',
          'die Einstellung der Insulintherapie', AnlassArt.anliegen),
      TerminAnlass('Diabetes-Schulung',
          'die Teilnahme an einer Schulung', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_gastroenterologie': ArztFach(
    bezeichnung: 'gastroenterologisch',
    erstAnlass: 'zur gastroenterologischen Erstvorstellung',
    kontrolleAnlass: 'zur gastroenterologischen Kontrolluntersuchung',
    kontrolleZusatz:
        'Sollte dafür eine Endoskopie (Magen- oder Darmspiegelung) '
        'vorgesehen sein, bitte ich um die Vorbereitungsunterlagen mit der '
        'Terminbestätigung.',
    akutAnlass: 'wegen akuter Magen-Darm-Beschwerden',
    anlaesse: [
      TerminAnlass('Sodbrennen / saures Aufstoßen',
          'Sodbrennen mit saurem Aufstoßen und Brennen hinter dem Brustbein'),
      TerminAnlass('Magenschmerzen / Gastritis',
          'Magenschmerzen mit Verdacht auf eine Gastritis'),
      TerminAnlass('Übelkeit / Erbrechen', 'Übelkeit und Erbrechen'),
      TerminAnlass('Blähungen / Völlegefühl', 'Blähungen und Völlegefühl'),
      TerminAnlass('Durchfall / Verstopfung',
          'anhaltender Durchfall bzw. Verstopfung'),
      TerminAnlass('Blut im Stuhl', 'Blut im Stuhl'),
      TerminAnlass('Schluckbeschwerden', 'Schluckbeschwerden'),
      TerminAnlass('Gewichtsverlust', 'ein unerklärlicher Gewichtsverlust'),
      TerminAnlass('Vorsorge-Darmspiegelung',
          'die Vorsorge-Darmspiegelung', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_rheumatologie': ArztFach(
    bezeichnung: 'rheumatologisch',
    erstAnlass: 'zur rheumatologischen Erstvorstellung',
    kontrolleAnlass: 'zur rheumatologischen Verlaufskontrolle',
    kontrolleZusatz:
        'Falls vor dem Termin Laborwerte benötigt werden, bitte ich um einen '
        'entsprechenden Hinweis.',
    akutAnlass: 'wegen eines akuten Schubes',
    anlaesse: [
      // ⚠️ Die beiden ersten Phrasen tragen die Überweisungskriterien mit, mit
      // denen der Rheumatologe arbeitet: eine länger als zwei Wochen
      // bestehende Schwellung von zwei oder mehr Gelenken gehört abgeklärt,
      // und die Morgensteifigkeit zählt ab 30 Minuten (sie tritt bei 80–90 %
      // der Betroffenen auf und ist fast immer ein Entzündungszeichen).
      // „Gelenkschmerzen" allein sagt einer Anmeldung nichts — die Zahlen
      // schon, und sie entscheiden über die Dringlichkeit.
      TerminAnlass('Gelenkschmerzen / Schwellung',
          'geschwollene Gelenke, seit mehr als zwei Wochen und an mehr als '
          'einem Gelenk'),
      TerminAnlass('Morgensteifigkeit',
          'eine Morgensteifigkeit von mehr als 30 Minuten'),
      TerminAnlass('Verdacht auf entzündliches Rheuma',
          'ein Verdacht auf eine entzündlich-rheumatische Erkrankung'),
      TerminAnlass('Akuter Schub', 'ein akuter Schub'),
      TerminAnlass('Muskelschmerzen', 'anhaltende Muskelschmerzen'),
      TerminAnlass('Auffällige Entzündungswerte',
          'auffällige Entzündungswerte im Labor'),
      TerminAnlass('Kontrolle der Basistherapie',
          'die Kontrolle der Basistherapie', AnlassArt.anliegen),
    ],
  ),
  'gesundheit_wundzentrum': ArztFach(
    bezeichnung: 'wundmedizinisch',
    erstAnlass: 'zur Erstvorstellung in Ihrer Wundsprechstunde',
    kontrolleAnlass: 'zur Wundkontrolle',
    akutAnlass: 'wegen einer Verschlechterung der Wundsituation',
    anlaesse: [
      // ⚠️ „chronisch" ist definiert: keine Heilungstendenz nach vier bis
      // zwölf Wochen. Steht die Dauer im Text, muss die Wundsprechstunde
      // nicht erst nachfragen, ob es überhaupt ihr Fall ist.
      TerminAnlass('Wunde heilt nicht ab',
          'eine Wunde, die seit mehr als vier Wochen keine Heilungstendenz '
          'zeigt'),
      TerminAnlass('Offenes Bein (Ulcus cruris)',
          'ein offenes Bein (Ulcus cruris)'),
      TerminAnlass('Wunde nässt / riecht', 'eine nässende, riechende Wunde'),
      TerminAnlass('Rötung / Schwellung',
          'Rötung und Schwellung im Wundbereich'),
      TerminAnlass('Schmerzen an der Wunde', 'Schmerzen im Wundbereich'),
      TerminAnlass('Diabetisches Fußsyndrom',
          'ein diabetisches Fußsyndrom'),
      TerminAnlass('Druckgeschwür (Dekubitus)', 'ein Druckgeschwür'),
      TerminAnlass('Wechsel des Verbandmaterials',
          'die Umstellung des Verbandmaterials', AnlassArt.anliegen),
    ],
  ),

  // ── Einrichtungen, keine Praxen ────────────────────────────────────
  'gesundheit_krankenhaus': ArztFach(
    bezeichnung: 'fachärztlich',
    erstAnlass: 'zur ambulanten Erstvorstellung in Ihrem Haus',
    kontrolleAnlass: 'zu einem Kontrolltermin in Ihrer Ambulanz',
    kontrolleZusatz: 'Der Termin dient der Nachkontrolle.',
    akutAnlass: 'wegen akuter Beschwerden',
    stelleDativ: 'in Ihrem Haus',
    anlaesse: [
      TerminAnlass('Ambulante Erstvorstellung',
          'eine ambulante Erstvorstellung', AnlassArt.anliegen),
      TerminAnlass('Vorbereitung eines Eingriffs',
          'die Vorbereitung eines geplanten Eingriffs', AnlassArt.anliegen),
      TerminAnlass('Nachkontrolle nach OP',
          'die Nachkontrolle nach einer Operation', AnlassArt.anliegen),
      TerminAnlass('Spezialsprechstunde',
          'einen Termin in Ihrer Spezialsprechstunde', AnlassArt.anliegen),
      TerminAnlass('Befundbesprechung',
          'die Besprechung eines Befundes', AnlassArt.anliegen),
      TerminAnlass('Zweitmeinung', 'eine Zweitmeinung', AnlassArt.anliegen),
    ],
  ),

  // ⚠️ Der Medizinische Dienst behandelt nicht und vergibt keine
  // Sprechstundentermine — er begutachtet im Auftrag der Kasse, und den
  // Termin setzt er selbst an. Eine „Terminanfrage" im Wortsinn gibt es hier
  // nicht; die drei Vorlagen sind Anfragen ZUM Begutachtungstermin, und der
  // Ton bleibt anfragend, damit niemand dem MD einen Termin diktiert.
  'gesundheit_md': ArztFach(
    bezeichnung: 'begutachtend',
    erstAnlass: 'um Mitteilung eines Termins zur Begutachtung',
    kontrolleAnlass: 'um eine Auskunft zum Stand des Begutachtungsverfahrens',
    akutAnlass: 'um eine kurzfristige Begutachtung',
    ueberweisungUeblich: false,
    anlaesse: [
      TerminAnlass('Pflegegrad — Erstbegutachtung',
          'die Erstbegutachtung zum Pflegegrad', AnlassArt.anliegen),
      TerminAnlass('Höherstufung Pflegegrad',
          'die Begutachtung zur Höherstufung des Pflegegrades',
          AnlassArt.anliegen),
      // 🔴 HIER STAND EIN FEHLER, UND ZWAR EINER MIT FRIST.
      // „Widerspruch gegen das Gutachten" an den MD zu richten, geht ins
      // Leere: Widersprochen wird dem BESCHEID, und der kommt von der
      // Pflegekasse — dort ist auch der Widerspruch einzulegen, innerhalb
      // eines Monats nach Zugang. Der MD begutachtet nur im Auftrag der Kasse
      // und entscheidet nichts. Ein Widerspruch an die falsche Stelle ist
      // nicht bloß wirkungslos, er verbrennt die Monatsfrist.
      //
      // Was man beim MD-Verfahren wirklich anfragt, ist das Gutachten selbst:
      // es wird auf Wunsch übersandt, und ohne es lässt sich ein Widerspruch
      // gar nicht begründen. Deshalb steht hier das — und der Dialog weist
      // beim MD zusätzlich darauf hin, wohin der Widerspruch gehört.
      TerminAnlass('Gutachten anfordern',
          'die Übersendung des Pflegegutachtens', AnlassArt.anliegen),
      TerminAnlass('Begutachtung Hilfsmittel',
          'die Begutachtung eines Hilfsmittels', AnlassArt.anliegen),
      TerminAnlass('Begutachtung Arbeitsunfähigkeit',
          'die Begutachtung der Arbeitsunfähigkeit', AnlassArt.anliegen),
      TerminAnlass('Sachstand des Verfahrens',
          'eine Auskunft zum Sachstand', AnlassArt.anliegen),
    ],
  ),

  // ⚠️ Das Sanitätshaus ist keine Praxis: es versorgt mit Hilfsmitteln auf
  // ärztliche Verordnung (§ 33 SGB V). Deshalb heißt das Papier hier Rezept
  // und nicht Überweisung, und die Anlässe sind Versorgung, Anpassung und
  // Reparatur — nicht Untersuchung.
  //
  // ⚠️ Dieser Tab hängt technisch NICHT an `selected_arzt`: seine Termine
  // gehören einem `vorfall_id` und liegen in `sanitaetshausAction`, nicht in
  // `saveArztTermin`. Und es gibt dort bislang nur `stammdaten.telefon` und
  // `stammdaten.email`, KEIN Faxfeld — solange das so ist, kann von hier aus
  // nur der Mailweg angeboten werden. Siehe Anmerkung im Versanddialog.
  'gesundheit_sanitaetshaus': ArztFach(
    bezeichnung: 'Hilfsmittelversorgung',
    erstAnlass: 'zur Beratung und zum Anmessen',
    kontrolleAnlass: 'zu einem Versorgungstermin',
    akutAnlass: 'wegen eines defekten Hilfsmittels',
    ueberweisungUeblich: false,
    belegName: 'ärztliche Verordnung (Rezept)',
    stelleDativ: 'bei Ihrem Sanitätshaus',
    belegZusatz: 'Die Verordnung ist 28 Kalendertage ab Ausstellung gültig '
        '(nach einer Krankenhausentlassung sieben Tage); ich bitte daher um '
        'einen Termin innerhalb dieser Frist.',
    anlaesse: [
      TerminAnlass('Rezept einlösen',
          'die Einlösung einer Hilfsmittelverordnung', AnlassArt.anliegen),
      TerminAnlass('Anmessen / Maßanfertigung',
          'das Anmessen einer Maßanfertigung', AnlassArt.anliegen),
      TerminAnlass('Anpassung / Nachpassung',
          'eine Anpassung des vorhandenen Hilfsmittels', AnlassArt.anliegen),
      TerminAnlass('Reparatur', 'die Reparatur eines Hilfsmittels',
          AnlassArt.anliegen),
      TerminAnlass('Wartung / Sicherheitskontrolle',
          'die Wartung des Hilfsmittels', AnlassArt.anliegen),
      TerminAnlass('Einweisung in die Nutzung',
          'eine Einweisung in die Nutzung', AnlassArt.anliegen),
      TerminAnlass('Hilfsmittel drückt / passt nicht',
          'ein Hilfsmittel, das drückt und nicht richtig sitzt'),
      TerminAnlass('Verbrauchsmaterial',
          'die Nachlieferung von Verbrauchsmaterial', AnlassArt.anliegen),
      TerminAnlass('Kostenvoranschlag für die Kasse',
          'ein Kostenvoranschlag für die Krankenkasse', AnlassArt.anliegen),
      TerminAnlass('Hausbesuch erforderlich',
          'ein Hausbesuch, wie auf der Verordnung vermerkt',
          AnlassArt.anliegen),
    ],
  ),

  'gesundheit_sonstige': _fachSonstige,
};

/// ⚠️ NICHT in der Tabelle, und das ist Absicht: **Rettungsdienst**.
///
/// Der Rettungsdienst wird über 112 disponiert, wenn es passiert — er vergibt
/// keine Termine, und der Tab hat folgerichtig weder eine Terminliste noch
/// einen Anfrage-Knopf (geprüft: 0 Treffer für „Termin" in
/// `lib/widgets/rettungsdienst.dart`). Eine „Terminanfrage an den
/// Rettungsdienst" wäre keine Lücke, die man schließt, sondern eine Funktion,
/// die im Ernstfall Zeit kostet.
const String rettungsdienstOhneAnfrage = 'gesundheit_rettungsdienst';

/// Auffangfach. ⚠️ Bewusst ohne Fachwort im Text: „fachärztlich" passt
/// überall und behauptet nichts, was der Empfänger nicht ist.
const ArztFach _fachSonstige = ArztFach(
  bezeichnung: 'fachärztlich',
  erstAnlass: 'zur Erstvorstellung in Ihrer Praxis',
  kontrolleAnlass: 'zu einem Kontrolltermin',
  akutAnlass: 'wegen akuter Beschwerden',
  ueberweisungUeblich: false,
  anlaesse: [
    TerminAnlass('Erstvorstellung', 'eine Erstvorstellung', AnlassArt.anliegen),
    TerminAnlass('Kontrolluntersuchung',
        'eine Kontrolluntersuchung', AnlassArt.anliegen),
    TerminAnlass('Befundbesprechung',
        'die Besprechung eines Befundes', AnlassArt.anliegen),
    TerminAnlass('Akute Beschwerden', 'akute Beschwerden'),
    TerminAnlass('Folgerezept', 'ein Folgerezept', AnlassArt.anliegen),
    TerminAnlass('Überweisung einlösen',
        'die Einlösung einer Überweisung', AnlassArt.anliegen),
  ],
);

/// Das Fach zu einem `arzt_type` — nie `null`, damit ein unbekannter Tab
/// einen brauchbaren Brief erzeugt statt eine Lücke.
ArztFach arztFachFuer(String arztTyp) => kArztFaecher[arztTyp] ?? _fachSonstige;

/// Was die Terminliste über die Vorgeschichte bei DIESER Praxis hergibt:
/// Anzahl stattgefundener Termine und das Datum des jüngsten, `dd.MM.yyyy`.
///
/// 🔴 Gezählt wird NUR, was auch ein Termin war. Zeilen mit `typ` = `anfrage`
/// sind Anfragen — oft unbeantwortete —, und aus einer unbeantworteten
/// Anfrage „der Patient war schon einmal hier" zu machen, ist die Umkehrung
/// der Wahrheit. Ebenso fliegen Termine in der Zukunft raus: ein vereinbarter
/// Termin nächste Woche belegt keine Vorgeschichte.
///
/// [termine] sind die Zeilen aus `_arztTermine[type]`, so wie sie vom Server
/// kommen: `datum` als `yyyy-MM-dd`, `typ` als `normal` | `notfall` |
/// `anfrage`.
(int, String) terminanfrageHistorie(
  List<Map<String, dynamic>> termine, {
  DateTime? heute,
}) {
  final jetzt = heute ?? DateTime.now();
  DateTime? juengster;
  var anzahl = 0;

  for (final t in termine) {
    if ((t['typ']?.toString() ?? '') == 'anfrage') continue;
    final d = DateTime.tryParse(t['datum']?.toString() ?? '');
    if (d == null || d.isAfter(jetzt)) continue;
    anzahl++;
    if (juengster == null || d.isAfter(juengster)) juengster = d;
  }

  final wann = juengster == null
      ? ''
      : '${juengster.day.toString().padLeft(2, '0')}.'
          '${juengster.month.toString().padLeft(2, '0')}.'
          '${juengster.year}';
  return (anzahl, wann);
}

/// Welche Vorlage vorausgewählt wird, wenn der Dialog aufgeht.
///
/// Grundlage sind die bei DIESER Praxis erfassten Termine: keiner erfasst →
/// [TerminanfrageVorlage.erstvorstellung], sonst
/// [TerminanfrageVorlage.kontrolle]. [TerminanfrageVorlage.akut] wird nie
/// vorausgewählt — ob es eilt, weiß nur der Mensch.
///
/// ⚠️ Eine Voreinstellung, keine Feststellung. Der Knopf bleibt umstellbar,
/// und der Brief behauptet nie „Patient war noch nie hier" — siehe
/// [_herkunftsAbsatz].
TerminanfrageVorlage vorgewaehlteVorlage(int erfassteTermine) =>
    erfassteTermine > 0
        ? TerminanfrageVorlage.kontrolle
        : TerminanfrageVorlage.erstvorstellung;

/// Warum diese Vorlage vorgewählt ist — als Satz für den Dialog, damit die
/// Voreinstellung nicht wie eine Behauptung des Programms aussieht.
String vorauswahlBegruendung(int erfassteTermine, String letzterTermin) {
  if (erfassteTermine == 0) {
    return 'Kein Termin bei dieser Praxis erfasst — Erstvorstellung vorgewählt. '
        'Ob dort bereits eine Akte besteht, wissen wir nicht; die Anfrage '
        'sagt das auch so.';
  }
  final wann = letzterTermin.isEmpty ? '' : ', zuletzt am $letzterTermin';
  return '$erfassteTermine Termin${erfassteTermine == 1 ? '' : 'e'} '
      'bei dieser Praxis erfasst$wann — Kontrolltermin vorgewählt.';
}

/// Alles, was in den Brief kommt. Wird im Dialog aus User, `selected_arzt`,
/// Krankenkasse und Vereinsdaten zusammengesetzt.
class TerminanfrageDaten {
  final String arztTyp;

  // ── Patient ──
  final String vorname;
  final String nachname;
  final String geburtsdatum; // dd.MM.yyyy, wie es im Brief steht
  final String strasse;
  final String plz;
  final String ort;
  final String krankenkasse;
  final String versichertennummer;

  // ── Praxis ──
  final String praxisName;
  final String arztName;
  final String praxisStrasse;
  final String praxisPlzOrt;

  /// Die beiden Kanäle der Praxis. Sie stehen NICHT im Brief — sie
  /// entscheiden, welcher Versandknopf überhaupt angeht.
  final String praxisEmail;
  final String praxisFax;

  /// Nur für die Nebenabfragen des Dialogs (Krankenkasse). Im Brief taucht
  /// sie nie auf.
  final int userId;

  // ── Anliegen ──
  /// Die angekreuzten Gründe, als [TerminAnlass.kurz]. Aufgelöst wird gegen
  /// das Fach — ein Grund, der dort nicht (mehr) steht, wird still übergangen
  /// statt roh in den Brief geschrieben.
  final List<String> anlaesse;

  /// Freitext zusätzlich zur Auswahl. Keine Liste trifft alles.
  final String anliegen;

  /// Nur wenn bestätigt — siehe ⚠️ im Kopf dieser Datei.
  final bool ueberweisungLiegtVor;

  /// Ob jemand vom Verein mitkommt (Übersetzung, Begleitung). Steuert die
  /// Bitte um die Terminlage — siehe [kVereinErreichbarkeit].
  final bool begleitung;

  /// Abweichende Wunschzeit, falls die Regel einmal nicht passt. Leer =
  /// das Vereinsfenster gilt.
  final String wunschzeitAbweichend;

  /// Wie viele stattgefundene Termine bei dieser Praxis erfasst sind, und
  /// wann der letzte war. Kommt aus [terminanfrageHistorie].
  final int erfassteTermine;
  final String letzterTermin;

  // ── Rückweg ──
  final String rueckantwortEmail;
  final String rueckantwortFax;
  final String rueckantwortTelefon;
  final String vereinsname;
  final String erreichbarkeit;

  const TerminanfrageDaten({
    required this.arztTyp,
    required this.vorname,
    required this.nachname,
    this.geburtsdatum = '',
    this.strasse = '',
    this.plz = '',
    this.ort = '',
    this.krankenkasse = '',
    this.versichertennummer = '',
    this.praxisName = '',
    this.arztName = '',
    this.praxisStrasse = '',
    this.praxisPlzOrt = '',
    this.praxisEmail = '',
    this.praxisFax = '',
    this.userId = 0,
    this.anlaesse = const [],
    this.anliegen = '',
    this.ueberweisungLiegtVor = false,
    this.begleitung = true,
    this.wunschzeitAbweichend = '',
    this.erfassteTermine = 0,
    this.letzterTermin = '',
    this.rueckantwortEmail = '',
    this.rueckantwortFax = '',
    this.rueckantwortTelefon = '',
    this.vereinsname = '',
    this.erreichbarkeit = kVereinErreichbarkeit,
  });

  String get vollerName => '$vorname $nachname'.trim();
}

/// Betreff und Brieftext einer Anfrage — dieselbe Quelle für E-Mail und Fax.
class TerminanfrageText {
  final String betreff;

  /// Der Fließtext ohne Anrede und ohne Grußformel: die baut der jeweilige
  /// Ausgang selbst, weil das PDF sie anders setzt als eine E-Mail.
  final List<String> absaetze;

  /// Die Angaben, die als Block stehen (Name, Geburtsdatum, Kasse …) — im
  /// PDF eine Tabelle, in der E-Mail Zeilen.
  final List<(String, String)> angaben;

  const TerminanfrageText({
    required this.betreff,
    required this.absaetze,
    required this.angaben,
  });

  /// Fertige E-Mail: Anrede, Text, Angaben, Grußformel.
  ///
  /// ⚠️ Ohne Signatur — die hängt `api/mail/send.php` an und holt sie aus
  /// `users` + `vereineinstellungen`. Wer sie hier noch einmal schreibt,
  /// erzeugt sie doppelt und lässt beide auseinanderlaufen.
  String alsMailText(
    TerminanfrageDaten d, {
    TerminanfrageStimme stimme = TerminanfrageStimme.ich,
  }) {
    final b = StringBuffer()
      ..writeln('Sehr geehrte Damen und Herren,')
      ..writeln();
    for (final a in absaetze) {
      b..writeln(a)..writeln();
    }
    b.writeln('Angaben zur Patientin / zum Patienten:');
    for (final (label, wert) in angaben) {
      b.writeln('$label: $wert');
    }
    // 🔴 In der Wir-Fassung KEINE Grußformel und KEIN Name: den Abschluss
    // trägt die Mailsignatur, und die nennt den Menschen, der die Mail
    // wirklich abgeschickt hat. Stünde hier zusätzlich der Name des
    // Mitglieds, unterschrieben zwei verschiedene Leute dieselbe Mail.
    if (stimme == TerminanfrageStimme.ich) {
      b
        ..writeln()
        ..writeln('Mit freundlichen Grüßen')
        ..writeln(d.vollerName);
    }
    return b.toString();
  }
}

/// Baut Betreff und Text aus Vorlage + Fach + Daten.
TerminanfrageText terminanfrageText(
  TerminanfrageVorlage vorlage,
  TerminanfrageDaten d, {
  TerminanfrageStimme stimme = TerminanfrageStimme.ich,
}) {
  final fach = arztFachFuer(d.arztTyp);
  final istMd = d.arztTyp == 'gesundheit_md';
  final wir = stimme == TerminanfrageStimme.wir;

  final (anlass, zusatz) = switch (vorlage) {
    TerminanfrageVorlage.erstvorstellung => (fach.erstAnlass, ''),
    TerminanfrageVorlage.kontrolle => (fach.kontrolleAnlass, fach.kontrolleZusatz),
    TerminanfrageVorlage.akut => (fach.akutAnlass, ''),
  };

  // ⚠️ Der MD bekommt kein „bitte ich um einen Termin": seine Vorlagen sind
  // schon als Bitte formuliert („um Mitteilung eines Termins …"). Sonst
  // stünde dort „bitte ich um einen Termin um Mitteilung eines Termins".
  // In der Wir-Fassung MUSS das Mitglied hier genannt werden: sonst stünde am
  // Anfang „wir bitten um einen Termin" und die Praxis wüsste bis zum
  // Angabenblock nicht, für wen.
  final fuerWen = wir ? ' für unser Mitglied ${d.vollerName}' : '';
  final bitte = wir ? 'bitten wir$fuerWen' : 'bitte ich';
  final einleitung = istMd
      ? 'hiermit $bitte $anlass.'
      : vorlage == TerminanfrageVorlage.akut
          ? 'hiermit $bitte um einen kurzfristigen Termin $anlass.'
          : 'hiermit $bitte um einen Termin $anlass.';

  final absaetze = <String>[einleitung];
  if (zusatz.isNotEmpty) absaetze.add(zusatz);

  // Steht direkt hinter dem Anlass, nicht am Ende: die Anmeldung entscheidet
  // als Erstes, ob sie eine Akte anlegt oder eine sucht.
  final herkunft = _herkunftsAbsatz(vorlage, d, istMd, wir);
  if (herkunft.isNotEmpty) absaetze.add(herkunft);

  absaetze.addAll(_anlassSaetze(fach, d.anlaesse));
  if (d.anliegen.trim().isNotEmpty) absaetze.add(d.anliegen.trim());

  if (d.ueberweisungLiegtVor) {
    absaetze.add(
      'Eine ${fach.belegName} liegt vor und wird zum Termin mitgebracht.'
      '${fach.belegZusatz.isEmpty ? '' : ' ${fach.belegZusatz}'}',
    );
  }

  final zeit = _terminlageAbsatz(d, wir);
  if (zeit.isNotEmpty) absaetze.add(zeit);

  // Der Schlusssatz nennt den Rückweg — sonst antwortet die Praxis dorthin,
  // wo niemand nachsieht. Beim Fax ist die Faxnummer der Rückweg, bei der
  // E-Mail die Adresse; genannt wird, was gesetzt ist.
  //
  // ⚠️ Beim Telefon steht das Zeitfenster DIREKT dahinter, nicht in einem
  // Nebensatz weiter unten: eine Anmeldung liest die Rückrufnummer und wählt.
  // Schriftliche Wege brauchen es nicht — ein Fax wartet, ein Anruf nicht.
  final zeitfenster =
      d.erreichbarkeit.trim().isEmpty ? '' : ' (${d.erreichbarkeit.trim()})';
  final rueckwege = <String>[
    if (d.rueckantwortEmail.isNotEmpty) 'per E-Mail an ${d.rueckantwortEmail}',
    if (d.rueckantwortFax.isNotEmpty) 'per Fax an ${d.rueckantwortFax}',
    if (d.rueckantwortTelefon.isNotEmpty)
      'telefonisch unter ${d.rueckantwortTelefon}$zeitfenster',
  ];
  final unsMir = wir ? 'uns' : 'mir';
  absaetze.add(rueckwege.isEmpty
      ? 'Bitte teilen Sie $unsMir mögliche Termine mit.'
      : 'Bitte teilen Sie $unsMir mögliche Termine '
          '${_aufzaehlung(rueckwege)} mit.');

  // ⚠️ Der Verein wird genannt, aber es wird KEINE Vollmacht behauptet. Eine
  // Terminorganisation braucht keine; eine Auskunft über den Gesundheits-
  // zustand schon, und die wird hier auch nicht erbeten.
  //
  // „ehrenamtlich" steht nicht als Höflichkeit dabei, sondern weil es das
  // schmale Zeitfenster erklärt. Ohne den Grund liest sich „nur nachmittags"
  // wie Unlust; mit ihm ist es eine Auskunft.
  final wann = d.erreichbarkeit.trim().isEmpty
      ? ''
      : 'Der Verein arbeitet ehrenamtlich und ist ${d.erreichbarkeit.trim()} '
          'besetzt.';
  if (wir) {
    // ⚠️ Kein „die Terminorganisation übernimmt der Verein" mehr: in dieser
    // Fassung SCHREIBT der Verein, das steht schon im ersten Satz und in der
    // Signatur. Was bleibt, ist die Auskunft, die der Praxis wirklich hilft.
    if (wann.isNotEmpty) absaetze.add(wann);
  } else if (d.vereinsname.isNotEmpty &&
      (d.rueckantwortEmail.isNotEmpty || d.rueckantwortFax.isNotEmpty)) {
    absaetze.add(
      'Die Terminorganisation übernimmt für mich ${d.vereinsname}; '
      'die genannten Kontaktdaten sind die des Vereins.'
      '${wann.isEmpty ? '' : ' $wann'}',
    );
  }

  // 🔴 KEINE Telefonnummer des Mitglieds.
  //
  // Wir vereinbaren den Termin — deshalb steht im Text unsere Nummer samt
  // Zeitfenster. Stünde daneben die private Nummer des Mitglieds, riefe die
  // Anmeldung genau dort an: bei einem Menschen, der oft kein Deutsch spricht
  // und für den wir gerade deswegen anfragen. Das Gespräch scheitert, der
  // Platz ist weg, und niemand erfährt davon.
  //
  // Dazu kommt: die Nummer ist für die Terminvergabe schlicht nicht nötig.
  // Was die Anmeldung braucht, ist die Akte zu finden — Name, Geburtsdatum,
  // Anschrift, Kasse, Versichertennummer. Eine private Rufnummer an einen
  // Dritten zu geben, der sie nicht braucht, ist genau das, was Art. 5 Abs. 1
  // lit. c DSGVO Datenminimierung nennt.
  final angaben = <(String, String)>[
    ('Name', d.vollerName),
    if (d.geburtsdatum.isNotEmpty) ('Geburtsdatum', d.geburtsdatum),
    if (d.strasse.isNotEmpty) ('Anschrift', d.strasse),
    if ('${d.plz} ${d.ort}'.trim().isNotEmpty) ('Ort', '${d.plz} ${d.ort}'.trim()),
    if (d.krankenkasse.isNotEmpty) ('Krankenkasse', d.krankenkasse),
    if (d.versichertennummer.isNotEmpty)
      ('Versichertennummer', d.versichertennummer),
  ];

  return TerminanfrageText(
    betreff: _betreff(vorlage, d, istMd),
    absaetze: absaetze,
    angaben: angaben,
  );
}

/// Aus den angekreuzten Gründen werden ein bis zwei Sätze: einer für die
/// Beschwerden, einer für die Anliegen.
///
/// ⚠️ Getrennt, weil „Es bestehen eine professionelle Zahnreinigung" kein
/// Deutsch ist. Siehe [AnlassArt].
List<String> _anlassSaetze(ArztFach fach, List<String> gewaehlt) {
  if (gewaehlt.isEmpty) return const [];

  // Reihenfolge des FACHS, nicht die des Anklickens: so liest sich der Satz
  // bei zwei Menschen gleich, und die Wiedererkennbarkeit hilft dem, der
  // hundert dieser Anfragen bearbeitet.
  final beschwerden = <String>[];
  final anliegen = <String>[];
  for (final a in fach.anlaesse) {
    if (!gewaehlt.contains(a.kurz)) continue;
    (a.art == AnlassArt.beschwerde ? beschwerden : anliegen).add(a.phrase);
  }

  return [
    if (beschwerden.isNotEmpty)
      beschwerden.length == 1
          ? 'Es besteht ${beschwerden.first}.'
          : 'Es bestehen ${_aufzaehlungUnd(beschwerden)}.',
    if (anliegen.isNotEmpty)
      anliegen.length == 1
          ? 'Anlass ist ${anliegen.first}.'
          : 'Anlass sind ${_aufzaehlungUnd(anliegen)}.',
  ];
}

/// Die Bitte um die Terminlage.
///
/// 🔴 HIER STECKT DER EIGENTLICHE ZWECK DES 14-bis-17-UHR-FENSTERS.
/// Der Verein begleitet und übersetzt, und das geht nur, wenn jemand da ist.
/// Ein Termin um 9 Uhr ist für einen Menschen, der kein Deutsch spricht, ein
/// Termin ohne Übersetzung — also der halbe Termin. Deshalb wird die
/// Terminlage nicht als Vorliebe formuliert, sondern mit dem Grund: eine
/// Praxis, die den Grund kennt, verschiebt eher um zwei Stunden als eine, die
/// nur „Wunschzeit nachmittags" liest.
///
/// ⚠️ „nach Möglichkeit" bleibt drin. Wer einer überlaufenen Praxis Bedingungen
/// stellt, bekommt keinen Termin, sondern eine Absage.
String _terminlageAbsatz(TerminanfrageDaten d, bool wir) {
  if (d.wunschzeitAbweichend.trim().isNotEmpty) {
    return 'Termine sind ${d.wunschzeitAbweichend.trim()} möglich.';
  }
  if (!d.begleitung || d.erreichbarkeit.trim().isEmpty) return '';

  final wer = d.vereinsname.isEmpty
      ? 'eine Begleitperson'
      : 'eine Begleitperson des Vereins ${d.vereinsname}';
  return 'Bitte legen Sie den Termin nach Möglichkeit '
      '${d.erreichbarkeit.trim()}: In dieser Zeit kann $wer zur '
      'Sprachmittlung und Unterstützung mitkommen. Sollte das nicht möglich '
      'sein, ${wir ? 'nennen wir' : 'nenne ich'} Ihnen gern eine Alternative.';
}

/// Der Absatz, der sagt, ob hier schon einmal jemand war — und was wir davon
/// wirklich wissen.
///
/// 🔴 DER GANZE PUNKT DIESES ABSATZES IST, NICHTS ZU BEHAUPTEN.
/// Wir kennen die Termine, die der Verein selbst erfasst hat. Wer vor Jahren
/// dort war und es nie erzählt hat, steht bei uns mit null Terminen — „der
/// Patient ist neu" wäre also geraten. Umgekehrt ist unser Eintrag ein
/// Anhaltspunkt, mit dem die Anmeldung die Akte sofort findet.
///
/// ⚠️ Beim Akuttermin entfällt der Absatz: dort zählt, dass es eilt, und ein
/// Satz über Aktenlage verwässert die Bitte. Beim MD entfällt er ebenfalls —
/// dort gibt es keine Patientenakte, sondern einen Auftrag der Kasse.
String _herkunftsAbsatz(
  TerminanfrageVorlage vorlage,
  TerminanfrageDaten d,
  bool istMd,
  bool wir,
) {
  if (istMd || vorlage == TerminanfrageVorlage.akut) return '';
  final stelle = arztFachFuer(d.arztTyp).stelleDativ;

  if (d.erfassteTermine > 0) {
    // ⚠️ „vermerkt", NICHT „in Behandlung gewesen". Gezählt werden nur
    // stattgefundene Termine — siehe [terminanfrageHistorie].
    final wo = wir ? 'bei uns' : 'bei mir';
    return d.letzterTermin.isEmpty
        ? 'Ein früherer Termin $stelle ist $wo vermerkt.'
        : 'Ein früherer Termin $stelle ist $wo vermerkt, '
            'zuletzt am ${d.letzterTermin}.';
  }

  return 'Ob $stelle bereits eine Akte besteht, ist hier nicht bekannt — '
      'ein früherer Termin ist nicht vermerkt. Bitte prüfen Sie das anhand '
      'der unten genannten Angaben; andernfalls '
      '${wir ? 'bitten wir' : 'bitte ich'} um Aufnahme als '
      'neue Patientin bzw. neuer Patient.';
}

String _betreff(
  TerminanfrageVorlage vorlage,
  TerminanfrageDaten d,
  bool istMd,
) {
  final wer = d.geburtsdatum.isEmpty
      ? d.vollerName
      : '${d.vollerName}, geb. ${d.geburtsdatum}';
  final art = istMd
      ? switch (vorlage) {
          TerminanfrageVorlage.erstvorstellung => 'Anfrage Begutachtungstermin',
          TerminanfrageVorlage.kontrolle => 'Sachstandsanfrage Begutachtung',
          TerminanfrageVorlage.akut => 'Bitte um kurzfristige Begutachtung',
        }
      : switch (vorlage) {
          TerminanfrageVorlage.erstvorstellung =>
            'Terminanfrage – Erstvorstellung',
          TerminanfrageVorlage.kontrolle => 'Terminanfrage – Kontrolltermin',
          TerminanfrageVorlage.akut => 'Terminanfrage – kurzfristiger Termin',
        };
  return '$art: $wer';
}

/// „a", „a oder b", „a, b oder c" — für die Rückwege.
String _aufzaehlung(List<String> teile) {
  if (teile.length == 1) return teile.first;
  return '${teile.sublist(0, teile.length - 1).join(', ')} oder ${teile.last}';
}

/// Dasselbe mit „und" — für Beschwerden und Anliegen.
String _aufzaehlungUnd(List<String> teile) {
  if (teile.length == 1) return teile.first;
  return '${teile.sublist(0, teile.length - 1).join(', ')} sowie ${teile.last}';
}
