/// Die Texte der Visitenkarte in allen Sprachen, für die es eine Fahne gibt.
///
/// ## ⚠️ Warum fest übersetzt und nicht durch NLLB
///
/// Dieselbe Entscheidung wie bei den 28 SMS-Vorlagen, und aus demselben Grund:
/// **einzelne Wörter sind der schlechteste Fall für maschinelle Übersetzung.**
/// „Würde" ohne Satz kann als Verbform herauskommen, „Anerkennung" als
/// „Wertschätzung" statt als Anerkennung ausländischer Abschlüsse, „Aufnahme"
/// als Tonaufnahme. Auf einer Visitenkarte steht das dann jahrelang gedruckt
/// im Portemonnaie eines Amtsleiters.
///
/// Übersetzt wird deshalb einmal von Hand und liegt danach im Code.
///
/// ## ⚠️ Was NICHT übersetzt wird
///
/// * **Der Slogan.** `Integration · Chancen · Diversity · 360° Support` ist ein
///   Akrostichon: I · C · D · 360 · S ergibt **ICD360S**. Auf Rumänisch wäre es
///   „Integrare · Șanse · Diversitate" = I·Ș·D, und der Vereinsname wäre weg.
///   Der Slogan bleibt in jeder Sprachfassung deutsch.
/// * **Name, Rufnummern, E-Mail, Mitgliedsnummer, Anschrift.**
/// * **Registerangabe** („VR 201335 · Amtsgericht Memmingen, Bayern"). Das ist
///   die Kennung eines deutschen Registers; übersetzt wäre sie nicht mehr
///   auffindbar.
///
/// ## ⚠️ Die Ämter WERDEN übersetzt — anders als sonst im Haus
///
/// In `api/helpers/vorstand_funktion.php` steht ausdrücklich, Ämter blieben
/// deutsch, „auch für ein Mitglied mit anderer App-Sprache". Das betraf die
/// **App**-Sprache: die Karte sollte sich nicht ändern, nur weil jemand die
/// Oberfläche umstellt.
///
/// Hier ist es eine **Karten**-Sprache, also etwas anderes. Eine Karte, die
/// jemand bewusst auf Rumänisch druckt, um sie einem rumänischen Gegenüber zu
/// geben, ist in sich stimmig — auf ihr steht dann auch das Amt rumänisch. Die
/// deutsche Karte bleibt Wort für Wort, wie sie war.
///
/// ## ⚠️ Zwei Netze halten diese Tabelle
///
/// 1. **Zeichendeckung.** Ein Test schickt jeden Text jeder Sprache gegen die
///    Zeichentabelle von DejaVu Sans (regular *und* fett — die beiden decken
///    nicht dasselbe ab). Ein fehlendes Zeichen käme im PDF als leeres
///    Kästchen heraus, und zwar erst auf dem Papier. Das ist das Gegenstück
///    zum GSM-7-Test der SMS-Vorlagen.
/// 2. **Vollzähligkeit.** Jede Sprache muss alle 22 Schlagwörter tragen und
///    darf kein leeres Feld haben; der Konstruktor verlangt jedes Feld, ein
///    vergessenes ist also schon ein Übersetzungsfehler des Compilers.
///
/// ⚠️ Was die Netze **nicht** können: beurteilen, ob eine Übersetzung stimmt.
/// Die Sprachen, die im Verein tatsächlich gesprochen werden (de ro ru uk en
/// tr), sind belegt; die übrigen sollten vor einem größeren Druck von jemandem
/// gegengelesen werden, der sie spricht.
library;

/// Alle Texte einer Sprachfassung.
///
/// Jedes Feld ist `required` — eine vergessene Zeichenkette ist damit ein
/// Übersetzungsfehler, kein leeres Feld auf dem Ausdruck.
class VisitenkarteTexte {
  /// Der Name der Sprache in ihr selbst, für die Fahnenleiste.
  final String eigenname;

  /// Überschrift der Rückseite („Was wir tun").
  final String ueberschrift;

  /// Die 22 Schlagwörter aus § 2 und § 3 der Satzung, in derselben Reihenfolge
  /// wie die deutsche Fassung. Die Reihenfolge ist nicht beliebig: sie führt
  /// von Ämtern über Sprache, Wohnen und Arbeit zum Alltag und endet bei
  /// Teilhabe und Würde.
  final List<String> schlagworte;

  /// Der Leitsatz aus § 1 der Satzung, in Übersetzung.
  ///
  /// ⚠️ Verbindlich ist die **deutsche** Fassung, so wie sie beim
  /// Registergericht liegt. Die Übersetzung dient dem Verstehen, nicht der
  /// Auslegung.
  final String leitsatz;

  /// Der Hinweis nach § 3 Abs. 4 der Satzung.
  ///
  /// ⚠️ Der wichtigste Satz auf der ganzen Karte, juristisch: er grenzt ab,
  /// was der Verein **nicht** tut. Auf Deutsch nützt er dem nichts, der ihn
  /// nicht lesen kann — deshalb wird er übersetzt. Die Fundstelle „§ 3 Abs. 4"
  /// bleibt unverändert stehen, damit das Original auffindbar ist.
  final String abgrenzung;

  /// „gemeinnützig" — der Status nach §§ 51 ff. AO.
  final String gemeinnuetzig;

  /// Der Zusatz „Gründer" hinter dem Amt.
  final String gruender;

  /// Vorsitz, männlich / weiblich / geschlechtsneutral.
  ///
  /// ⚠️ Darf `{n}` enthalten, dort steht die Nummer des Vorsitzes. Die
  /// Stellung ist sprachabhängig: deutsch „1. Vorsitzender", rumänisch
  /// „Președinte 1". Ohne `{n}` wird die Nummer vorangestellt, wie im
  /// Deutschen üblich. Fehlt die Nummer, verschwindet der Platzhalter samt
  /// Punkt und Leerzeichen.
  final String vorsitzM;
  final String vorsitzF;
  final String vorsitzN;

  final String schatzM;
  final String schatzF;
  final String kassM;
  final String kassF;
  final String gruendungsmitglied;
  final String mitglied;

  /// Schriftgrad des Schlagwortblocks auf der Rückseite.
  ///
  /// ## ⚠️ Gemessen, nicht gewählt — und der Grund ist ein echter Datenverlust
  ///
  /// Die Rückseite ist randvoll. Der `Column` des PDF-Erzeugers wirft
  /// Überzähliges **stillschweigend** weg: bei Russisch und Ukrainisch fehlte
  /// schlagartig die letzte Zeile (`icd360s.de · VR 201335 · …`), ohne Fehler,
  /// ohne Warnung. Aufgefallen ist es nur, weil der Bogen gerastert und
  /// angesehen wurde — die Zählprobe hatte nur Überschrift und letztes
  /// Schlagwort geprüft und blieb grün.
  ///
  /// Die Ursache ist die Sprache selbst: „Повышение квалификации" ist mehr als
  /// doppelt so lang wie „Weiterbildung", der Block wächst von sechs auf acht
  /// Zeilen. Also schrumpft dort, wo es elastisch ist — die Schlagwörter —,
  /// und nur so weit wie nötig.
  ///
  /// Der Wert je Sprache stammt aus einer Suche: von 7,0 pt in Schritten von
  /// 0,1 herunter, bis alle Felder wieder zehnmal auf dem Bogen stehen. Ein
  /// Test hält das Ergebnis fest. Wer eine Übersetzung ändert, muss die Suche
  /// erneut laufen lassen.
  final double schlagwortGrad;

  const VisitenkarteTexte({
    required this.eigenname,
    required this.ueberschrift,
    required this.schlagworte,
    required this.leitsatz,
    required this.abgrenzung,
    required this.gemeinnuetzig,
    required this.gruender,
    required this.vorsitzM,
    required this.vorsitzF,
    required this.vorsitzN,
    required this.schatzM,
    required this.schatzF,
    required this.kassM,
    required this.kassF,
    required this.gruendungsmitglied,
    required this.mitglied,
    this.schlagwortGrad = 7,
  });

  /// Dieselbe Fassung mit anderem Schlagwortgrad.
  ///
  /// ⚠️ Existiert für die Messung, nicht für den Betrieb: die Suche nach dem
  /// größten Grad, bei dem noch alles auf die Rückseite passt, braucht einen
  /// Weg, den Wert zu verstellen, ohne diese Tabelle zu bearbeiten. Im
  /// laufenden Programm ruft das niemand.
  VisitenkarteTexte mitSchlagwortGrad(double grad) => VisitenkarteTexte(
        eigenname: eigenname,
        ueberschrift: ueberschrift,
        schlagworte: schlagworte,
        leitsatz: leitsatz,
        abgrenzung: abgrenzung,
        gemeinnuetzig: gemeinnuetzig,
        gruender: gruender,
        vorsitzM: vorsitzM,
        vorsitzF: vorsitzF,
        vorsitzN: vorsitzN,
        schatzM: schatzM,
        schatzF: schatzF,
        kassM: kassM,
        kassF: kassF,
        gruendungsmitglied: gruendungsmitglied,
        mitglied: mitglied,
        schlagwortGrad: grad,
      );

  /// Jede Zeichenkette dieser Fassung, für die Prüfungen.
  List<String> get alleTexte => [
        eigenname,
        ueberschrift,
        ...schlagworte,
        leitsatz,
        abgrenzung,
        gemeinnuetzig,
        gruender,
        vorsitzM,
        vorsitzF,
        vorsitzN,
        schatzM,
        schatzF,
        kassM,
        kassF,
        gruendungsmitglied,
        mitglied,
      ];
}

/// Die Sprache, in der eine Karte gesetzt wird, wenn nichts anderes gewählt
/// ist.
const String kVisitenkarteStandardsprache = 'de';

/// Die Amtsbezeichnung in der gewählten Sprache.
///
/// [rolleKey] ist `users.role` unverändert, [anredeform] das Ergebnis von
/// `vfAnredeform()` auf dem Server (`herr` / `frau` / `neutral`), [vorsitzNr]
/// die Nummer des Vorsitzes oder `null`.
///
/// ⚠️ Bei unbekannter Rolle kommt `mitglied` heraus, nicht die rohe Rolle:
/// „mitgliedergrunder" auf einer Visitenkarte wäre schlimmer als ein zu
/// allgemeines, aber richtiges Wort.
String amtsbezeichnung(
  VisitenkarteTexte t, {
  required String rolleKey,
  required String anredeform,
  int? vorsitzNr,
}) {
  String mitNummer(String vorlage) {
    if (vorlage.contains('{n}')) {
      // Ohne Nummer verschwindet der Platzhalter samt anhängendem Punkt und
      // Leerzeichen — „. Vorsitzender" wäre ein sichtbarer Fehler.
      final ersetzt = vorsitzNr == null
          ? vorlage.replaceAll(RegExp(r'\{n\}\.?\s*'), '')
          : vorlage.replaceAll('{n}', '$vorsitzNr');
      return ersetzt.trim();
    }
    return vorsitzNr == null ? vorlage : '$vorsitzNr. $vorlage';
  }

  switch (rolleKey.trim().toLowerCase()) {
    case 'vorsitzer':
      return mitNummer(switch (anredeform) {
        'frau' => t.vorsitzF,
        'herr' => t.vorsitzM,
        _ => t.vorsitzN,
      });
    case 'schatzmeister':
      return anredeform == 'frau' ? t.schatzF : t.schatzM;
    case 'kassierer':
      return anredeform == 'frau' ? t.kassF : t.kassM;
    case 'mitgliedergrunder':
      return t.gruendungsmitglied;
    default:
      return t.mitglied;
  }
}

/// Die Texte einer Sprache, mit Rückfall auf Deutsch.
///
/// ⚠️ Rückfall statt `null`: eine Karte ohne Rückseitentext wäre schlimmer als
/// eine deutsche Rückseite. Wer prüfen will, ob es eine Fassung überhaupt gibt,
/// fragt [kVisitenkarteSprachen] direkt ab.
VisitenkarteTexte visitenkarteTexte(String? code) =>
    kVisitenkarteSprachen[(code ?? '').trim().toLowerCase()] ??
    kVisitenkarteSprachen[kVisitenkarteStandardsprache]!;

/// Alle Sprachfassungen.
///
/// ⚠️ Die Schlüssel müssen dieselben sein wie `kFlaggenCodes` in flaggen.dart —
/// ohne Fahne gäbe es keinen Knopf, ohne Fassung führte ein Knopf auf die
/// deutsche Karte. Ein Test hält beide Mengen deckungsgleich.
const Map<String, VisitenkarteTexte> kVisitenkarteSprachen = {
  // ── Deutsch — die Fassung, an der alle anderen gemessen werden ────────────
  'de': VisitenkarteTexte(
    eigenname: 'Deutsch',
    ueberschrift: 'Was wir tun',
    schlagworte: [
      'Behörden', 'Anträge', 'Formulare',
      'Dolmetschen', 'Übersetzen', 'Sprachkurse',
      'Wohnraum', 'Arbeit', 'Bewerbung', 'Anerkennung', 'Weiterbildung',
      'Einkaufen', 'Arzttermine', 'Haushalt', 'Kinderbetreuung',
      'Sozialleistungen', 'Wohngeld', 'Nothilfe',
      'Zuhören', 'Begegnung', 'Teilhabe', 'Würde',
    ],
    leitsatz: 'Der Vorstand besteht mehrheitlich aus Menschen mit Behinderung. '
        'Selbstvertretung statt Fürsorge.',
    abgrenzung: 'Keine Rechts-, Steuer- oder medizinische Beratung '
        '(§ 3 Abs. 4 der Satzung) — wir vermitteln an zugelassene Fachleute '
        'weiter.',
    gemeinnuetzig: 'gemeinnützig',
    gruender: 'Gründer',
    vorsitzM: 'Vorsitzender',
    vorsitzF: 'Vorsitzende',
    vorsitzN: 'Vorsitz',
    schatzM: 'Schatzmeister',
    schatzF: 'Schatzmeisterin',
    kassM: 'Kassierer',
    kassF: 'Kassiererin',
    gruendungsmitglied: 'Gründungsmitglied',
    mitglied: 'Mitglied',
  ),

  // ── Englisch ─────────────────────────────────────────────────────────────
  'en': VisitenkarteTexte(
    eigenname: 'English',
    ueberschrift: 'What we do',
    schlagworte: [
      'Authorities', 'Applications', 'Forms',
      'Interpreting', 'Translation', 'Language courses',
      'Housing', 'Work', 'Job applications', 'Recognition', 'Training',
      'Shopping', 'Doctor visits', 'Household', 'Childcare',
      'Social benefits', 'Housing benefit', 'Emergency aid',
      'Listening', 'Encounter', 'Participation', 'Dignity',
    ],
    leitsatz: 'The board is made up mainly of people with disabilities. '
        'Self-advocacy instead of charity.',
    abgrenzung: 'No legal, tax or medical advice (§ 3 (4) of the statutes) '
        '— we refer you to licensed professionals.',
    gemeinnuetzig: 'non-profit',
    gruender: 'Founder',
    vorsitzM: 'Chairman',
    vorsitzF: 'Chairwoman',
    vorsitzN: 'Chair',
    schatzM: 'Treasurer',
    schatzF: 'Treasurer',
    kassM: 'Finance officer',
    kassF: 'Finance officer',
    gruendungsmitglied: 'Founding member',
    mitglied: 'Member',
  ),

  // ── Rumänisch ────────────────────────────────────────────────────────────
  'ro': VisitenkarteTexte(
    eigenname: 'Română',
    ueberschrift: 'Ce facem',
    schlagworte: [
      'Autorități', 'Cereri', 'Formulare',
      'Interpretariat', 'Traduceri', 'Cursuri de limbă',
      'Locuință', 'Muncă', 'Candidatură', 'Recunoaștere', 'Perfecționare',
      'Cumpărături', 'Consultații', 'Gospodărie', 'Îngrijirea copiilor',
      'Prestații sociale', 'Alocație de locuință', 'Ajutor de urgență',
      'Ascultare', 'Întâlnire', 'Participare', 'Demnitate',
    ],
    leitsatz: 'Consiliul director este format în majoritate din persoane cu '
        'dizabilități. Autoreprezentare, nu asistență.',
    abgrenzung: 'Fără consultanță juridică, fiscală sau medicală '
        '(§ 3 alin. 4 din statut) — vă îndrumăm către specialiști autorizați.',
    gemeinnuetzig: 'de utilitate publică',
    gruender: 'Fondator',
    vorsitzM: 'Președinte {n}',
    vorsitzF: 'Președintă {n}',
    vorsitzN: 'Președinție {n}',
    schatzM: 'Trezorier',
    schatzF: 'Trezorieră',
    kassM: 'Casier',
    kassF: 'Casieră',
    gruendungsmitglied: 'Membru fondator',
    mitglied: 'Membru',
  ),

  // ── Russisch ─────────────────────────────────────────────────────────────
  'ru': VisitenkarteTexte(
    eigenname: 'Русский',
    ueberschrift: 'Чем мы занимаемся',
    schlagworte: [
      'Ведомства', 'Заявления', 'Формуляры',
      'Устный перевод', 'Письменный перевод', 'Языковые курсы',
      'Жильё', 'Работа', 'Резюме', 'Признание дипломов', 'Повышение квалификации',
      'Покупки', 'Приём у врача', 'Быт', 'Уход за детьми',
      'Социальные выплаты', 'Жилищное пособие', 'Экстренная помощь',
      'Выслушать', 'Встречи', 'Участие', 'Достоинство',
    ],
    leitsatz: 'Правление состоит преимущественно из людей с инвалидностью. '
        'Самопредставительство вместо опеки.',
    abgrenzung: 'Мы не оказываем юридических, налоговых и медицинских '
        'консультаций (§ 3 абз. 4 устава) — мы направляем к лицензированным '
        'специалистам.',
    gemeinnuetzig: 'некоммерческая организация',
    gruender: 'Основатель',
    vorsitzM: '{n}-й председатель',
    vorsitzF: '{n}-я председательница',
    vorsitzN: '{n}-е председательство',
    schatzM: 'Казначей',
    schatzF: 'Казначей',
    kassM: 'Кассир',
    kassF: 'Кассир',
    gruendungsmitglied: 'Член-учредитель',
    mitglied: 'Член',
    // Gemessen: „Повышение квалификации" und „Социальные выплаты" treiben den
    // Block von sechs auf acht Zeilen. Bei 6,5 fehlte die Fußzeile noch.
    schlagwortGrad: 6.4,
  ),

  // ── Ukrainisch ───────────────────────────────────────────────────────────
  'uk': VisitenkarteTexte(
    eigenname: 'Українська',
    ueberschrift: 'Чим ми займаємось',
    schlagworte: [
      'Відомства', 'Заяви', 'Формуляри',
      'Усний переклад', 'Письмовий переклад', 'Мовні курси',
      'Житло', 'Робота', 'Резюме', 'Визнання дипломів', 'Підвищення кваліфікації',
      'Покупки', 'Візит до лікаря', 'Побут', 'Догляд за дітьми',
      'Соціальні виплати', 'Житлова допомога', 'Екстрена допомога',
      'Вислухати', 'Зустрічі', 'Участь', 'Гідність',
    ],
    leitsatz: 'Правління складається переважно з людей з інвалідністю. '
        'Самопредставництво замість опіки.',
    abgrenzung: 'Ми не надаємо юридичних, податкових чи медичних консультацій '
        '(§ 3 абз. 4 статуту) — ми направляємо до ліцензованих фахівців.',
    gemeinnuetzig: 'неприбуткова організація',
    gruender: 'Засновник',
    vorsitzM: '{n}-й голова',
    vorsitzF: '{n}-а голова',
    vorsitzN: '{n}-е головування',
    schatzM: 'Скарбник',
    schatzF: 'Скарбниця',
    kassM: 'Касир',
    kassF: 'Касирка',
    gruendungsmitglied: 'Член-засновник',
    mitglied: 'Член',
    // Gemessen; etwas kürzer als das Russische, deshalb reicht mehr Grad.
    schlagwortGrad: 6.8,
  ),

  // ── Türkisch ─────────────────────────────────────────────────────────────
  'tr': VisitenkarteTexte(
    eigenname: 'Türkçe',
    ueberschrift: 'Ne yapıyoruz',
    schlagworte: [
      'Resmî kurumlar', 'Başvurular', 'Formlar',
      'Sözlü çeviri', 'Yazılı çeviri', 'Dil kursları',
      'Konut', 'İş', 'İş başvurusu', 'Denklik', 'Meslek eğitimi',
      'Alışveriş', 'Doktor randevusu', 'Ev işleri', 'Çocuk bakımı',
      'Sosyal yardımlar', 'Kira yardımı', 'Acil yardım',
      'Dinlemek', 'Buluşma', 'Katılım', 'Onur',
    ],
    leitsatz: 'Yönetim kurulu ağırlıklı olarak engelli bireylerden oluşur. '
        'Vesayet değil, kendi sesimiz.',
    abgrenzung: 'Hukuki, mali veya tıbbi danışmanlık vermiyoruz '
        '(tüzük § 3 fıkra 4) — yetkili uzmanlara yönlendiriyoruz.',
    gemeinnuetzig: 'kamu yararına',
    gruender: 'Kurucu',
    vorsitzM: '{n}. Başkan',
    vorsitzF: '{n}. Başkan',
    vorsitzN: '{n}. Başkanlık',
    schatzM: 'Sayman',
    schatzF: 'Sayman',
    kassM: 'Veznedar',
    kassF: 'Veznedar',
    gruendungsmitglied: 'Kurucu üye',
    mitglied: 'Üye',
  ),

  // ── Bulgarisch ─────────────────────────────────────────────────
  'bg': VisitenkarteTexte(
    eigenname: 'Български',
    ueberschrift: 'Какво правим',
    schlagworte: [
      'Институции', 'Заявления', 'Формуляри',
      'Устен превод', 'Писмен превод', 'Езикови курсове',
      'Жилище', 'Работа', 'Кандидатстване',
      'Признаване на дипломи', 'Квалификация', 'Пазаруване',
      'Лекарски прегледи', 'Домакинство', 'Грижа за деца',
      'Социални помощи', 'Жилищна помощ', 'Спешна помощ',
      'Изслушване', 'Срещи', 'Участие',
      'Достойнство',
    ],
    leitsatz: 'Управителният съвет се състои предимно от хора с увреждания. Самозастъпничество вместо опека.',
    abgrenzung: 'Не предоставяме правни, данъчни или медицински консултации (§ 3, ал. 4 от устава) — насочваме към лицензирани специалисти.',
    gemeinnuetzig: 'с нестопанска цел',
    gruender: 'Основател',
    vorsitzM: '{n}-и председател',
    vorsitzF: '{n}-а председателка',
    vorsitzN: '{n}-о председателство',
    schatzM: 'Ковчежник',
    schatzF: 'Ковчежничка',
    kassM: 'Касиер',
    kassF: 'Касиерка',
    gruendungsmitglied: 'Член-основател',
    mitglied: 'Член',
    // Gemessen. „Признаване на дипломи“ und „Лекарски прегледи“ treiben den Block über sechs Zeilen.
    schlagwortGrad: 6.6,
  ),

  // ── Tschechisch ─────────────────────────────────────────────────
  'cs': VisitenkarteTexte(
    eigenname: 'Čeština',
    ueberschrift: 'Co děláme',
    schlagworte: [
      'Úřady', 'Žádosti', 'Formuláře',
      'Tlumočení', 'Překlady', 'Jazykové kurzy',
      'Bydlení', 'Práce', 'Životopis',
      'Uznání diplomů', 'Další vzdělávání', 'Nákupy',
      'Lékařské termíny', 'Domácnost', 'Péče o děti',
      'Sociální dávky', 'Příspěvek na bydlení', 'Nouzová pomoc',
      'Naslouchání', 'Setkávání', 'Účast',
      'Důstojnost',
    ],
    leitsatz: 'Výbor tvoří převážně lidé se zdravotním postižením. Sebeobhajoba místo péče.',
    abgrenzung: 'Neposkytujeme právní, daňové ani lékařské poradenství (§ 3 odst. 4 stanov) — odkazujeme na oprávněné odborníky.',
    gemeinnuetzig: 'nezisková organizace',
    gruender: 'Zakladatel',
    vorsitzM: '{n}. předseda',
    vorsitzF: '{n}. předsedkyně',
    vorsitzN: '{n}. předsednictví',
    schatzM: 'Pokladník',
    schatzF: 'Pokladnice',
    kassM: 'Účetní',
    kassF: 'Účetní',
    gruendungsmitglied: 'Zakládající člen',
    mitglied: 'Člen',
  ),

  // ── Dänisch ─────────────────────────────────────────────────
  'da': VisitenkarteTexte(
    eigenname: 'Dansk',
    ueberschrift: 'Det gør vi',
    schlagworte: [
      'Myndigheder', 'Ansøgninger', 'Blanketter',
      'Tolkning', 'Oversættelse', 'Sprogkurser',
      'Bolig', 'Arbejde', 'Jobansøgning',
      'Anerkendelse', 'Efteruddannelse', 'Indkøb',
      'Lægebesøg', 'Husholdning', 'Børnepasning',
      'Sociale ydelser', 'Boligstøtte', 'Nødhjælp',
      'Lytte', 'Møde', 'Deltagelse',
      'Værdighed',
    ],
    leitsatz: 'Bestyrelsen består overvejende af mennesker med handicap. Selvrepræsentation frem for omsorg.',
    abgrenzung: 'Ingen juridisk, skattemæssig eller lægelig rådgivning (§ 3, stk. 4 i vedtægterne) — vi henviser til autoriserede fagfolk.',
    gemeinnuetzig: 'almennyttig',
    gruender: 'Stifter',
    vorsitzM: '{n}. formand',
    vorsitzF: '{n}. formand',
    vorsitzN: '{n}. forperson',
    schatzM: 'Kasserer',
    schatzF: 'Kasserer',
    kassM: 'Regnskabsfører',
    kassF: 'Regnskabsfører',
    gruendungsmitglied: 'Stiftende medlem',
    mitglied: 'Medlem',
  ),

  // ── Griechisch ─────────────────────────────────────────────────
  'el': VisitenkarteTexte(
    eigenname: 'Ελληνικά',
    ueberschrift: 'Τι κάνουμε',
    schlagworte: [
      'Αρχές', 'Αιτήσεις', 'Έντυπα',
      'Διερμηνεία', 'Μετάφραση', 'Μαθήματα γλώσσας',
      'Στέγη', 'Εργασία', 'Αίτηση εργασίας',
      'Αναγνώριση πτυχίων', 'Επιμόρφωση', 'Ψώνια',
      'Ραντεβού με γιατρό', 'Νοικοκυριό', 'Φροντίδα παιδιών',
      'Κοινωνικές παροχές', 'Επίδομα στέγασης', 'Έκτακτη βοήθεια',
      'Ακρόαση', 'Συνάντηση', 'Συμμετοχή',
      'Αξιοπρέπεια',
    ],
    leitsatz: 'Το διοικητικό συμβούλιο αποτελείται κατά πλειοψηφία από άτομα με αναπηρία. Αυτοεκπροσώπηση αντί για πρόνοια.',
    abgrenzung: 'Δεν παρέχουμε νομικές, φορολογικές ή ιατρικές συμβουλές (§ 3 παρ. 4 του καταστατικού) — παραπέμπουμε σε αδειούχους ειδικούς.',
    gemeinnuetzig: 'μη κερδοσκοπικό',
    gruender: 'Ιδρυτής',
    vorsitzM: '{n}ος πρόεδρος',
    vorsitzF: '{n}η πρόεδρος',
    vorsitzN: '{n}η προεδρία',
    schatzM: 'Ταμίας',
    schatzF: 'Ταμίας',
    kassM: 'Λογιστής',
    kassF: 'Λογίστρια',
    gruendungsmitglied: 'Ιδρυτικό μέλος',
    mitglied: 'Μέλος',
  ),

  // ── Spanisch ─────────────────────────────────────────────────
  'es': VisitenkarteTexte(
    eigenname: 'Español',
    ueberschrift: 'Lo que hacemos',
    schlagworte: [
      'Administración', 'Solicitudes', 'Formularios',
      'Interpretación', 'Traducción', 'Cursos de idiomas',
      'Vivienda', 'Trabajo', 'Candidatura',
      'Homologación', 'Formación continua', 'Compras',
      'Citas médicas', 'Hogar', 'Cuidado infantil',
      'Prestaciones sociales', 'Ayuda de vivienda', 'Ayuda urgente',
      'Escucha', 'Encuentro', 'Participación',
      'Dignidad',
    ],
    leitsatz: 'La junta directiva está formada mayoritariamente por personas con discapacidad. Autorrepresentación en lugar de asistencialismo.',
    abgrenzung: 'No ofrecemos asesoramiento jurídico, fiscal ni médico (§ 3 ap. 4 de los estatutos) — remitimos a profesionales autorizados.',
    gemeinnuetzig: 'sin ánimo de lucro',
    gruender: 'Fundador',
    vorsitzM: 'Presidente {n}',
    vorsitzF: 'Presidenta {n}',
    vorsitzN: 'Presidencia {n}',
    schatzM: 'Tesorero',
    schatzF: 'Tesorera',
    kassM: 'Cajero',
    kassF: 'Cajera',
    gruendungsmitglied: 'Miembro fundador',
    mitglied: 'Miembro',
  ),

  // ── Estnisch ─────────────────────────────────────────────────
  'et': VisitenkarteTexte(
    eigenname: 'Eesti',
    ueberschrift: 'Mida me teeme',
    schlagworte: [
      'Ametiasutused', 'Taotlused', 'Vormid',
      'Suuline tõlge', 'Kirjalik tõlge', 'Keelekursused',
      'Eluase', 'Töö', 'Kandideerimine',
      'Diplomite tunnustamine', 'Täiendõpe', 'Ostud',
      'Arstivisiidid', 'Majapidamine', 'Lastehoid',
      'Sotsiaaltoetused', 'Eluasemetoetus', 'Hädaabi',
      'Kuulamine', 'Kohtumine', 'Osalemine',
      'Väärikus',
    ],
    leitsatz: 'Juhatus koosneb valdavalt puuetega inimestest. Eneseesindus hoolekande asemel.',
    abgrenzung: 'Me ei anna õigus-, maksu- ega meditsiininõu (põhikirja § 3 lg 4) — suuname litsentseeritud spetsialistide juurde.',
    gemeinnuetzig: 'mittetulundusühing',
    gruender: 'Asutaja',
    vorsitzM: '{n}. esimees',
    vorsitzF: '{n}. esinaine',
    vorsitzN: '{n}. eesistuja',
    schatzM: 'Laekur',
    schatzF: 'Laekur',
    kassM: 'Kassapidaja',
    kassF: 'Kassapidaja',
    gruendungsmitglied: 'Asutajaliige',
    mitglied: 'Liige',
  ),

  // ── Finnisch ─────────────────────────────────────────────────
  'fi': VisitenkarteTexte(
    eigenname: 'Suomi',
    ueberschrift: 'Mitä teemme',
    schlagworte: [
      'Viranomaiset', 'Hakemukset', 'Lomakkeet',
      'Tulkkaus', 'Käännökset', 'Kielikurssit',
      'Asuminen', 'Työ', 'Työhakemus',
      'Tutkintojen tunnustaminen', 'Täydennyskoulutus', 'Ostokset',
      'Lääkäriajat', 'Kotitalous', 'Lastenhoito',
      'Sosiaalietuudet', 'Asumistuki', 'Hätäapu',
      'Kuunteleminen', 'Kohtaaminen', 'Osallisuus',
      'Ihmisarvo',
    ],
    leitsatz: 'Hallitus koostuu pääosin vammaisista henkilöistä. Itseedustus hoivan sijaan.',
    abgrenzung: 'Emme anna oikeudellista, verotuksellista tai lääketieteellistä neuvontaa (sääntöjen 3 §:n 4 mom.) — ohjaamme valtuutetuille asiantuntijoille.',
    gemeinnuetzig: 'yleishyödyllinen',
    gruender: 'Perustaja',
    vorsitzM: '{n}. puheenjohtaja',
    vorsitzF: '{n}. puheenjohtaja',
    vorsitzN: '{n}. puheenjohtajuus',
    schatzM: 'Rahastonhoitaja',
    schatzF: 'Rahastonhoitaja',
    kassM: 'Kassanhoitaja',
    kassF: 'Kassanhoitaja',
    gruendungsmitglied: 'Perustajajäsen',
    mitglied: 'Jäsen',
  ),

  // ── Französisch ─────────────────────────────────────────────────
  'fr': VisitenkarteTexte(
    eigenname: 'Français',
    ueberschrift: 'Ce que nous faisons',
    schlagworte: [
      'Administrations', 'Demandes', 'Formulaires',
      'Interprétariat', 'Traduction', 'Cours de langue',
      'Logement', 'Travail', 'Candidature',
      'Reconnaissance des diplômes', 'Formation continue', 'Courses',
      'Rendez-vous médicaux', 'Ménage', 'Garde d’enfants',
      'Prestations sociales', 'Allocation logement', 'Aide d’urgence',
      'Écoute', 'Rencontre', 'Participation',
      'Dignité',
    ],
    leitsatz: 'Le conseil d’administration est composé majoritairement de personnes handicapées. L’autoreprésentation plutôt que l’assistance.',
    abgrenzung: 'Pas de conseil juridique, fiscal ni médical (§ 3 al. 4 des statuts) — nous orientons vers des professionnels agréés.',
    gemeinnuetzig: 'd’utilité publique',
    gruender: 'Fondateur',
    vorsitzM: 'Président {n}',
    vorsitzF: 'Présidente {n}',
    vorsitzN: 'Présidence {n}',
    schatzM: 'Trésorier',
    schatzF: 'Trésorière',
    kassM: 'Caissier',
    kassF: 'Caissière',
    gruendungsmitglied: 'Membre fondateur',
    mitglied: 'Membre',
    // Gemessen. „Reconnaissance des diplômes“ ist das längste Schlagwort aller 27 Fassungen.
    schlagwortGrad: 6.7,
  ),

  // ── Kroatisch ─────────────────────────────────────────────────
  'hr': VisitenkarteTexte(
    eigenname: 'Hrvatski',
    ueberschrift: 'Što radimo',
    schlagworte: [
      'Ustanove', 'Zahtjevi', 'Obrasci',
      'Usmeno prevođenje', 'Pisano prevođenje', 'Tečajevi jezika',
      'Stanovanje', 'Rad', 'Prijava za posao',
      'Priznavanje diploma', 'Usavršavanje', 'Kupovina',
      'Liječnički pregledi', 'Kućanstvo', 'Čuvanje djece',
      'Socijalne naknade', 'Stambena naknada', 'Hitna pomoć',
      'Slušanje', 'Susret', 'Sudjelovanje',
      'Dostojanstvo',
    ],
    leitsatz: 'Upravu većinom čine osobe s invaliditetom. Samozastupanje umjesto skrbi.',
    abgrenzung: 'Ne pružamo pravno, porezno ni medicinsko savjetovanje (§ 3 st. 4 statuta) — upućujemo na ovlaštene stručnjake.',
    gemeinnuetzig: 'neprofitna udruga',
    gruender: 'Osnivač',
    vorsitzM: '{n}. predsjednik',
    vorsitzF: '{n}. predsjednica',
    vorsitzN: '{n}. predsjedanje',
    schatzM: 'Blagajnik',
    schatzF: 'Blagajnica',
    kassM: 'Rizničar',
    kassF: 'Rizničarka',
    gruendungsmitglied: 'Osnivački član',
    mitglied: 'Član',
  ),

  // ── Ungarisch ─────────────────────────────────────────────────
  'hu': VisitenkarteTexte(
    eigenname: 'Magyar',
    ueberschrift: 'Amit csinálunk',
    schlagworte: [
      'Hatóságok', 'Kérelmek', 'Űrlapok',
      'Tolmácsolás', 'Fordítás', 'Nyelvtanfolyamok',
      'Lakhatás', 'Munka', 'Álláspályázat',
      'Diplomák elismerése', 'Továbbképzés', 'Bevásárlás',
      'Orvosi időpontok', 'Háztartás', 'Gyermekfelügyelet',
      'Szociális ellátások', 'Lakhatási támogatás', 'Sürgősségi segítség',
      'Meghallgatás', 'Találkozás', 'Részvétel',
      'Méltóság',
    ],
    leitsatz: 'Az elnökség többségében fogyatékossággal élő emberekből áll. Önérdekképviselet gondoskodás helyett.',
    abgrenzung: 'Nem nyújtunk jogi, adó- vagy orvosi tanácsadást (az alapszabály 3. § (4) bekezdése) — engedéllyel rendelkező szakemberekhez irányítunk.',
    gemeinnuetzig: 'közhasznú',
    gruender: 'Alapító',
    vorsitzM: '{n}. elnök',
    vorsitzF: '{n}. elnök',
    vorsitzN: '{n}. elnökség',
    schatzM: 'Kincstárnok',
    schatzF: 'Kincstárnok',
    kassM: 'Pénztáros',
    kassF: 'Pénztáros',
    gruendungsmitglied: 'Alapító tag',
    mitglied: 'Tag',
  ),

  // ── Italienisch ─────────────────────────────────────────────────
  'it': VisitenkarteTexte(
    eigenname: 'Italiano',
    ueberschrift: 'Cosa facciamo',
    schlagworte: [
      'Uffici pubblici', 'Domande', 'Moduli',
      'Interpretariato', 'Traduzione', 'Corsi di lingua',
      'Alloggio', 'Lavoro', 'Candidatura',
      'Riconoscimento titoli', 'Formazione', 'Spesa',
      'Visite mediche', 'Casa', 'Assistenza ai figli',
      'Prestazioni sociali', 'Sussidio casa', 'Aiuto d’emergenza',
      'Ascolto', 'Incontro', 'Partecipazione',
      'Dignità',
    ],
    leitsatz: 'Il consiglio direttivo è composto in maggioranza da persone con disabilità. Autorappresentanza invece di assistenza.',
    abgrenzung: 'Nessuna consulenza legale, fiscale o medica (§ 3 c. 4 dello statuto) — indirizziamo a professionisti abilitati.',
    gemeinnuetzig: 'senza scopo di lucro',
    gruender: 'Fondatore',
    vorsitzM: 'Presidente {n}',
    vorsitzF: 'Presidente {n}',
    vorsitzN: 'Presidenza {n}',
    schatzM: 'Tesoriere',
    schatzF: 'Tesoriera',
    kassM: 'Cassiere',
    kassF: 'Cassiera',
    gruendungsmitglied: 'Socio fondatore',
    mitglied: 'Socio',
  ),

  // ── Litauisch ─────────────────────────────────────────────────
  'lt': VisitenkarteTexte(
    eigenname: 'Lietuvių',
    ueberschrift: 'Ką mes darome',
    schlagworte: [
      'Įstaigos', 'Prašymai', 'Formos',
      'Vertimas žodžiu', 'Vertimas raštu', 'Kalbų kursai',
      'Būstas', 'Darbas', 'Darbo paraiška',
      'Diplomų pripažinimas', 'Kvalifikacijos kėlimas', 'Apsipirkimas',
      'Vizitai pas gydytoją', 'Buitis', 'Vaikų priežiūra',
      'Socialinės išmokos', 'Būsto pašalpa', 'Skubi pagalba',
      'Išklausymas', 'Susitikimai', 'Dalyvavimas',
      'Orumas',
    ],
    leitsatz: 'Valdybą daugiausia sudaro žmonės su negalia. Savarankiškas atstovavimas vietoj globos.',
    abgrenzung: 'Neteikiame teisinių, mokesčių ar medicininių konsultacijų (įstatų 3 str. 4 d.) — nukreipiame pas licencijuotus specialistus.',
    gemeinnuetzig: 'ne pelno organizacija',
    gruender: 'Įkūrėjas',
    vorsitzM: '{n}-asis pirmininkas',
    vorsitzF: '{n}-oji pirmininkė',
    vorsitzN: '{n}-asis pirmininkavimas',
    schatzM: 'Iždininkas',
    schatzF: 'Iždininkė',
    kassM: 'Kasininkas',
    kassF: 'Kasininkė',
    gruendungsmitglied: 'Steigiamasis narys',
    mitglied: 'Narys',
  ),

  // ── Lettisch ─────────────────────────────────────────────────
  'lv': VisitenkarteTexte(
    eigenname: 'Latviešu',
    ueberschrift: 'Ko mēs darām',
    schlagworte: [
      'Iestādes', 'Pieteikumi', 'Veidlapas',
      'Mutiskā tulkošana', 'Rakstiskā tulkošana', 'Valodu kursi',
      'Mājoklis', 'Darbs', 'Darba pieteikums',
      'Diplomu atzīšana', 'Tālākizglītība', 'Iepirkšanās',
      'Vizītes pie ārsta', 'Mājsaimniecība', 'Bērnu aprūpe',
      'Sociālie pabalsti', 'Mājokļa pabalsts', 'Neatliekamā palīdzība',
      'Uzklausīšana', 'Tikšanās', 'Līdzdalība',
      'Cieņa',
    ],
    leitsatz: 'Valdi galvenokārt veido cilvēki ar invaliditāti. Pašpārstāvība, nevis aprūpe.',
    abgrenzung: 'Mēs nesniedzam juridiskas, nodokļu vai medicīniskas konsultācijas (statūtu 3. panta 4. daļa) — novirzām pie licencētiem speciālistiem.',
    gemeinnuetzig: 'sabiedriskā labuma organizācija',
    gruender: 'Dibinātājs',
    vorsitzM: '{n}. priekšsēdētājs',
    vorsitzF: '{n}. priekšsēdētāja',
    vorsitzN: '{n}. vadība',
    schatzM: 'Mantzinis',
    schatzF: 'Mantzine',
    kassM: 'Kasieris',
    kassF: 'Kasiere',
    gruendungsmitglied: 'Dibinātājs biedrs',
    mitglied: 'Biedrs',
  ),

  // ── Norwegisch (Bokmål) ─────────────────────────────────────────────────
  'nb': VisitenkarteTexte(
    eigenname: 'Norsk',
    ueberschrift: 'Det vi gjør',
    schlagworte: [
      'Myndigheter', 'Søknader', 'Skjemaer',
      'Tolking', 'Oversettelse', 'Språkkurs',
      'Bolig', 'Arbeid', 'Jobbsøknad',
      'Godkjenning av vitnemål', 'Etterutdanning', 'Innkjøp',
      'Legetimer', 'Husholdning', 'Barnepass',
      'Sosiale ytelser', 'Bostøtte', 'Nødhjelp',
      'Lytting', 'Møte', 'Deltakelse',
      'Verdighet',
    ],
    leitsatz: 'Styret består hovedsakelig av mennesker med funksjonsnedsettelse. Selvrepresentasjon i stedet for omsorg.',
    abgrenzung: 'Ingen juridisk, skattemessig eller medisinsk rådgivning (§ 3 fjerde ledd i vedtektene) — vi henviser til autoriserte fagfolk.',
    gemeinnuetzig: 'allmennyttig',
    gruender: 'Grunnlegger',
    vorsitzM: '{n}. leder',
    vorsitzF: '{n}. leder',
    vorsitzN: '{n}. ledelse',
    schatzM: 'Kasserer',
    schatzF: 'Kasserer',
    kassM: 'Regnskapsfører',
    kassF: 'Regnskapsfører',
    gruendungsmitglied: 'Stiftende medlem',
    mitglied: 'Medlem',
  ),

  // ── Niederländisch ─────────────────────────────────────────────────
  'nl': VisitenkarteTexte(
    eigenname: 'Nederlands',
    ueberschrift: 'Wat wij doen',
    schlagworte: [
      'Overheden', 'Aanvragen', 'Formulieren',
      'Tolken', 'Vertalen', 'Taalcursussen',
      'Woonruimte', 'Werk', 'Sollicitatie',
      'Erkenning diploma’s', 'Bijscholing', 'Boodschappen',
      'Doktersafspraken', 'Huishouden', 'Kinderopvang',
      'Sociale uitkeringen', 'Huurtoeslag', 'Noodhulp',
      'Luisteren', 'Ontmoeting', 'Deelname',
      'Waardigheid',
    ],
    leitsatz: 'Het bestuur bestaat overwegend uit mensen met een beperking. Zelfvertegenwoordiging in plaats van zorg.',
    abgrenzung: 'Geen juridisch, fiscaal of medisch advies (§ 3 lid 4 van de statuten) — wij verwijzen door naar erkende deskundigen.',
    gemeinnuetzig: 'algemeen nut',
    gruender: 'Oprichter',
    vorsitzM: '{n}e voorzitter',
    vorsitzF: '{n}e voorzitster',
    vorsitzN: '{n}e voorzitterschap',
    schatzM: 'Penningmeester',
    schatzF: 'Penningmeester',
    kassM: 'Kassier',
    kassF: 'Kassierster',
    gruendungsmitglied: 'Oprichtend lid',
    mitglied: 'Lid',
  ),

  // ── Polnisch ─────────────────────────────────────────────────
  'pl': VisitenkarteTexte(
    eigenname: 'Polski',
    ueberschrift: 'Czym się zajmujemy',
    schlagworte: [
      'Urzędy', 'Wnioski', 'Formularze',
      'Tłumaczenia ustne', 'Tłumaczenia pisemne', 'Kursy językowe',
      'Mieszkanie', 'Praca', 'Podanie o pracę',
      'Uznanie dyplomów', 'Doskonalenie zawodowe', 'Zakupy',
      'Wizyty lekarskie', 'Gospodarstwo domowe', 'Opieka nad dziećmi',
      'Świadczenia socjalne', 'Dodatek mieszkaniowy', 'Pomoc doraźna',
      'Wysłuchanie', 'Spotkanie', 'Uczestnictwo',
      'Godność',
    ],
    leitsatz: 'Zarząd składa się w większości z osób z niepełnosprawnościami. Samorzecznictwo zamiast opieki.',
    abgrenzung: 'Nie udzielamy porad prawnych, podatkowych ani medycznych (§ 3 ust. 4 statutu) — kierujemy do uprawnionych specjalistów.',
    gemeinnuetzig: 'organizacja pożytku publicznego',
    gruender: 'Założyciel',
    vorsitzM: '{n}. przewodniczący',
    vorsitzF: '{n}. przewodnicząca',
    vorsitzN: '{n}. przewodnictwo',
    schatzM: 'Skarbnik',
    schatzF: 'Skarbniczka',
    kassM: 'Kasjer',
    kassF: 'Kasjerka',
    gruendungsmitglied: 'Członek założyciel',
    mitglied: 'Członek',
    // Gemessen. Die schmalste Fassung: „Doskonalenie zawodowe“ und „Gospodarstwo domowe“ nebeneinander.
    schlagwortGrad: 6.0,
  ),

  // ── Portugiesisch ─────────────────────────────────────────────────
  'pt': VisitenkarteTexte(
    eigenname: 'Português',
    ueberschrift: 'O que fazemos',
    schlagworte: [
      'Serviços públicos', 'Requerimentos', 'Formulários',
      'Interpretação', 'Tradução', 'Cursos de língua',
      'Habitação', 'Trabalho', 'Candidatura',
      'Reconhecimento de diplomas', 'Formação contínua', 'Compras',
      'Consultas médicas', 'Casa', 'Apoio às crianças',
      'Prestações sociais', 'Subsídio de habitação', 'Ajuda de emergência',
      'Escuta', 'Encontro', 'Participação',
      'Dignidade',
    ],
    leitsatz: 'A direção é composta maioritariamente por pessoas com deficiência. Autorrepresentação em vez de assistência.',
    abgrenzung: 'Não prestamos aconselhamento jurídico, fiscal ou médico (§ 3 n.º 4 dos estatutos) — encaminhamos para profissionais habilitados.',
    gemeinnuetzig: 'sem fins lucrativos',
    gruender: 'Fundador',
    vorsitzM: 'Presidente {n}',
    vorsitzF: 'Presidente {n}',
    vorsitzN: 'Presidência {n}',
    schatzM: 'Tesoureiro',
    schatzF: 'Tesoureira',
    kassM: 'Caixa',
    kassF: 'Caixa',
    gruendungsmitglied: 'Membro fundador',
    mitglied: 'Membro',
    // Gemessen. „Reconhecimento de diplomas“ und „Subsídio de habitação“.
    schlagwortGrad: 6.6,
  ),

  // ── Slowakisch ─────────────────────────────────────────────────
  'sk': VisitenkarteTexte(
    eigenname: 'Slovenčina',
    ueberschrift: 'Čo robíme',
    schlagworte: [
      'Úrady', 'Žiadosti', 'Formuláre',
      'Tlmočenie', 'Preklady', 'Jazykové kurzy',
      'Bývanie', 'Práca', 'Žiadosť o prácu',
      'Uznanie diplomov', 'Ďalšie vzdelávanie', 'Nákupy',
      'Lekárske termíny', 'Domácnosť', 'Starostlivosť o deti',
      'Sociálne dávky', 'Príspevok na bývanie', 'Núdzová pomoc',
      'Načúvanie', 'Stretnutie', 'Účasť',
      'Dôstojnosť',
    ],
    leitsatz: 'Výbor tvoria prevažne ľudia so zdravotným postihnutím. Sebazastupovanie namiesto opatery.',
    abgrenzung: 'Neposkytujeme právne, daňové ani lekárske poradenstvo (§ 3 ods. 4 stanov) — odkazujeme na oprávnených odborníkov.',
    gemeinnuetzig: 'nezisková organizácia',
    gruender: 'Zakladateľ',
    vorsitzM: '{n}. predseda',
    vorsitzF: '{n}. predsedníčka',
    vorsitzN: '{n}. predsedníctvo',
    schatzM: 'Pokladník',
    schatzF: 'Pokladníčka',
    kassM: 'Účtovník',
    kassF: 'Účtovníčka',
    gruendungsmitglied: 'Zakladajúci člen',
    mitglied: 'Člen',
  ),

  // ── Slowenisch ─────────────────────────────────────────────────
  'sl': VisitenkarteTexte(
    eigenname: 'Slovenščina',
    ueberschrift: 'Kaj počnemo',
    schlagworte: [
      'Uradi', 'Vloge', 'Obrazci',
      'Tolmačenje', 'Prevajanje', 'Jezikovni tečaji',
      'Stanovanje', 'Delo', 'Prijava za delo',
      'Priznavanje diplom', 'Izpopolnjevanje', 'Nakupovanje',
      'Zdravniški pregledi', 'Gospodinjstvo', 'Varstvo otrok',
      'Socialni prejemki', 'Stanovanjski dodatek', 'Nujna pomoč',
      'Poslušanje', 'Srečanje', 'Udeležba',
      'Dostojanstvo',
    ],
    leitsatz: 'Upravni odbor večinoma sestavljajo osebe z invalidnostjo. Samozastopanje namesto oskrbe.',
    abgrenzung: 'Ne nudimo pravnega, davčnega ali zdravstvenega svetovanja (§ 3 odst. 4 statuta) — napotimo k pooblaščenim strokovnjakom.',
    gemeinnuetzig: 'nepridobitna organizacija',
    gruender: 'Ustanovitelj',
    vorsitzM: '{n}. predsednik',
    vorsitzF: '{n}. predsednica',
    vorsitzN: '{n}. predsedstvo',
    schatzM: 'Blagajnik',
    schatzF: 'Blagajničarka',
    kassM: 'Računovodja',
    kassF: 'Računovodkinja',
    gruendungsmitglied: 'Ustanovni član',
    mitglied: 'Član',
  ),

  // ── Serbisch (lateinisch) ─────────────────────────────────────────────────
  'sr': VisitenkarteTexte(
    eigenname: 'Srpski',
    ueberschrift: 'Šta radimo',
    schlagworte: [
      'Ustanove', 'Zahtevi', 'Obrasci',
      'Usmeno prevođenje', 'Pismeno prevođenje', 'Kursevi jezika',
      'Stanovanje', 'Rad', 'Prijava za posao',
      'Priznavanje diploma', 'Usavršavanje', 'Kupovina',
      'Lekarski pregledi', 'Domaćinstvo', 'Čuvanje dece',
      'Socijalna davanja', 'Stambeni dodatak', 'Hitna pomoć',
      'Slušanje', 'Susret', 'Učešće',
      'Dostojanstvo',
    ],
    leitsatz: 'Upravu većinom čine osobe sa invaliditetom. Samozastupanje umesto staranja.',
    abgrenzung: 'Ne pružamo pravne, poreske ni medicinske savete (§ 3 st. 4 statuta) — upućujemo na ovlašćene stručnjake.',
    gemeinnuetzig: 'neprofitno udruženje',
    gruender: 'Osnivač',
    vorsitzM: '{n}. predsednik',
    vorsitzF: '{n}. predsednica',
    vorsitzN: '{n}. predsedavanje',
    schatzM: 'Blagajnik',
    schatzF: 'Blagajnica',
    kassM: 'Rizničar',
    kassF: 'Rizničarka',
    gruendungsmitglied: 'Osnivački član',
    mitglied: 'Član',
  ),

  // ── Schwedisch ─────────────────────────────────────────────────
  'sv': VisitenkarteTexte(
    eigenname: 'Svenska',
    ueberschrift: 'Det vi gör',
    schlagworte: [
      'Myndigheter', 'Ansökningar', 'Blanketter',
      'Tolkning', 'Översättning', 'Språkkurser',
      'Bostad', 'Arbete', 'Jobbansökan',
      'Erkännande av betyg', 'Vidareutbildning', 'Inköp',
      'Läkarbesök', 'Hushåll', 'Barnomsorg',
      'Sociala förmåner', 'Bostadsbidrag', 'Akuthjälp',
      'Lyssnande', 'Möte', 'Delaktighet',
      'Värdighet',
    ],
    leitsatz: 'Styrelsen består till största delen av personer med funktionsnedsättning. Självföreträde i stället för omsorg.',
    abgrenzung: 'Ingen juridisk, skatterättslig eller medicinsk rådgivning (§ 3 fjärde stycket i stadgarna) — vi hänvisar till behöriga fackpersoner.',
    gemeinnuetzig: 'allmännyttig',
    gruender: 'Grundare',
    vorsitzM: '{n}. ordförande',
    vorsitzF: '{n}. ordförande',
    vorsitzN: '{n}. ordförandeskap',
    schatzM: 'Kassör',
    schatzF: 'Kassör',
    kassM: 'Kassaförvaltare',
    kassF: 'Kassaförvaltare',
    gruendungsmitglied: 'Grundande medlem',
    mitglied: 'Medlem',
  ),
};
