/// Datenbank der in Deutschland aktiven Mobilfunkanbieter.
///
/// Quelle der Anbieter, Netze und Einordnung: Wikipedia „Liste der
/// Mobilfunkanbieter in Deutschland“, Tabelle „Übersicht aktiver Anbieter“
/// (abgerufen 2026-08-22). Übernommen wurden **nur** die dort als aktiv
/// geführten Anbieter — eingestellte Marken stehen bewusst nicht hier, sonst
/// böte die Suche Verträge an, die man gar nicht mehr abschließen kann.
///
/// ⚠️ Die Kündigungs-URLs sind **einzeln abgerufen und geprüft** (HTTP-Status
/// und Seitentitel), nicht aus dem Muster `<marke>.de/kuendigung` geraten. Das
/// Muster trägt nämlich nicht: bei blau, fraenk, WhatsApp SIM und Simyo läuft
/// es ins Leere, bei Lycamobile landet man auf der Startseite und bei NORMA
/// connect auf einer Statistik-Seite. Ein toter Link in der App ist schlimmer
/// als gar kein Knopf — deshalb steht bei allem Ungeprüften `null`, und der
/// Knopf erscheint dort schlicht nicht.
///
/// ⚠️ Wer eine URL ergänzt: vorher wirklich aufrufen. Ein 200 allein genügt
/// nicht, viele Anbieter liefern ihre 404-Seite mit Status 200 aus.
library;

/// Ein Anbieter mit dem Netz, in dem er funkt.
class MobilfunkAnbieter {
  /// Anzeigename — genau dieser Text landet im Feld „Anbieter“.
  final String name;

  /// Netz, in dem der Anbieter funkt (nicht der Vertragspartner).
  final String netz;

  /// Netzbetreiber / Eigenmarke / Brandingmarke / Service-Provider.
  final String art;

  /// Geprüfte Seite zur Online-Kündigung (§ 312k BGB), sonst `null`.
  final String? kuendigungUrl;

  /// Weitere Schreibweisen, unter denen gesucht wird. Der Anzeigename selbst
  /// muss hier nicht stehen.
  final List<String> alias;

  const MobilfunkAnbieter(
    this.name,
    this.netz,
    this.art, {
    this.kuendigungUrl,
    this.alias = const [],
  });

  bool get hatKuendigungOnline => (kuendigungUrl ?? '').isNotEmpty;
}

const String kNetzTelekom = 'Telekom';
const String kNetzVodafone = 'Vodafone';
const String kNetzO2 = 'O2 (Telefónica)';
const String kNetzEinsUndEins = '1&1';

/// Alle aktiven Anbieter, alphabetisch wie in der Quelle.
const List<MobilfunkAnbieter> kMobilfunkAnbieter = [
  // ── Netzbetreiber ────────────────────────────────────────────────────────
  MobilfunkAnbieter('Telekom', kNetzTelekom, 'Netzbetreiber',
      kuendigungUrl: 'https://www.telekom.de/vertrag-kuendigen',
      alias: ['telekom deutschland', 'deutsche telekom', 'd1', 'magenta', 'magentamobil', 't-mobile']),
  MobilfunkAnbieter('Vodafone', kNetzVodafone, 'Netzbetreiber',
      kuendigungUrl: 'https://www.vodafone.de/einfache-kuendigung.html',
      alias: ['d2', 'callya', 'gigamobil']),
  MobilfunkAnbieter('O2', kNetzO2, 'Netzbetreiber',
      kuendigungUrl: 'https://info.o2online.de/kuendigung/',
      // „telefónica“ braucht keinen eigenen Eintrag — der Schlüssel löst das
      // Akzentzeichen ohnehin auf.
      alias: ['o2 telefonica', 'telefonica', 'o2online', 'e-plus']),
  MobilfunkAnbieter('1&1', kNetzEinsUndEins, 'Netzbetreiber',
      kuendigungUrl: 'https://www.1und1.de/kuendigung',
      alias: ['1und1', 'einsundeins', 'drillisch']),

  // ── Telekom-Netz ─────────────────────────────────────────────────────────
  MobilfunkAnbieter('congstar', kNetzTelekom, 'Eigenmarke',
      kuendigungUrl: 'https://www.congstar.de/hilfe-service/mein-vertrag/kuendigen/'),
  MobilfunkAnbieter('EDEKA smart', kNetzTelekom, 'Brandingmarke',
      kuendigungUrl: 'https://www.edeka-smart.de/vertrag-kuendigen', alias: ['edeka']),
  MobilfunkAnbieter('fraenk', kNetzTelekom, 'Eigenmarke'),
  MobilfunkAnbieter('High Mobile', kNetzTelekom, 'Brandingmarke', alias: ['high mobil']),
  MobilfunkAnbieter('ja! mobil', kNetzTelekom, 'Brandingmarke',
      kuendigungUrl: 'https://www.ja-mobil.de/kuendigung', alias: ['rewe']),
  MobilfunkAnbieter('Kaufland mobil', kNetzTelekom, 'Brandingmarke',
      kuendigungUrl: 'https://www.kaufland-mobil.de/kuendigung/', alias: ['kaufland']),
  MobilfunkAnbieter('NORMA Connect', kNetzTelekom, 'Brandingmarke', alias: ['norma']),
  MobilfunkAnbieter('Penny Mobil', kNetzTelekom, 'Brandingmarke', alias: ['penny']),
  MobilfunkAnbieter('VARIATEL', kNetzTelekom, 'Eigenmarke'),

  // ── Vodafone-Netz ────────────────────────────────────────────────────────
  MobilfunkAnbieter('otelo', kNetzVodafone, 'Eigenmarke',
      kuendigungUrl: 'https://www.otelo.de/otelo-vertrag-kuendigen'),
  MobilfunkAnbieter('LIDL Connect', kNetzVodafone, 'Brandingmarke',
      kuendigungUrl: 'https://www.lidl-connect.de/vertrag-kuendigen', alias: ['lidl', 'lidl mobile']),
  MobilfunkAnbieter('SIMon mobile', kNetzVodafone, 'Eigenmarke',
      kuendigungUrl: 'https://www.simonmobile.de/kuendigung', alias: ['simon']),
  MobilfunkAnbieter('Fyve', kNetzVodafone, 'Brandingmarke'),
  MobilfunkAnbieter('Rossmann mobil', kNetzVodafone, 'Brandingmarke', alias: ['rossmann']),
  MobilfunkAnbieter('MTEL Deutschland', kNetzVodafone, 'Eigenmarke', alias: ['mtel']),
  MobilfunkAnbieter('spusu', kNetzVodafone, 'Eigenmarke',
      kuendigungUrl: 'https://www.spusu.de/vertrag-kuendigen'),
  MobilfunkAnbieter('WEtell', kNetzVodafone, 'Eigenmarke',
      kuendigungUrl: 'https://www.wetell.de/kuendigung'),
  MobilfunkAnbieter('Goood', kNetzVodafone, 'Brandingmarke', alias: ['goood mobile']),

  // ── O2-Netz (Telefónica) ─────────────────────────────────────────────────
  MobilfunkAnbieter('ALDI TALK', kNetzO2, 'Brandingmarke',
      kuendigungUrl: 'https://www.alditalk-kundenportal.de/kuendigung/', alias: ['aldi']),
  MobilfunkAnbieter('Ay Yildiz', kNetzO2, 'Eigenmarke',
      kuendigungUrl: 'https://info.ayyildiz.de/kuendigung'),
  MobilfunkAnbieter('Blau', kNetzO2, 'Eigenmarke', alias: ['blau.de', 'blau mobilfunk']),
  MobilfunkAnbieter('FONIC', kNetzO2, 'Eigenmarke',
      kuendigungUrl: 'https://www.fonic.de/kuendigung/', alias: ['fonic mobile']),
  MobilfunkAnbieter('Lebara', kNetzO2, 'Eigenmarke'),
  MobilfunkAnbieter('Lycamobile', kNetzO2, 'Service-Provider', alias: ['lyca']),
  MobilfunkAnbieter('Mega SIM', kNetzO2, 'Eigenmarke'),
  MobilfunkAnbieter('NettoKOM', kNetzO2, 'Eigenmarke',
      kuendigungUrl: 'https://www.nettokom.de/kuendigung/', alias: ['netto']),
  MobilfunkAnbieter('Ortel Mobile', kNetzO2, 'Eigenmarke',
      kuendigungUrl: 'https://www.ortelmobile.de/kuendigungsseite/', alias: ['ortel']),
  MobilfunkAnbieter('simyo', kNetzO2, 'Eigenmarke'),
  MobilfunkAnbieter('sipgate', kNetzO2, 'Eigenmarke'),
  MobilfunkAnbieter('Talkline', kNetzO2, 'Eigenmarke'),
  MobilfunkAnbieter('Tchibo mobil', kNetzO2, 'Brandingmarke',
      kuendigungUrl: 'https://www.tchibo-mobil.de/kuendigung', alias: ['tchibo']),
  MobilfunkAnbieter('WhatsApp SIM', kNetzO2, 'Brandingmarke'),
  MobilfunkAnbieter('aipi.tel', kNetzO2, 'Eigenmarke', alias: ['aipi']),
  MobilfunkAnbieter('freenet FUNK', kNetzO2, 'Brandingmarke'),
  MobilfunkAnbieter('freenet Mobile', kNetzO2, 'Brandingmarke',
      kuendigungUrl: 'https://www.freenet-digital.de/onlineservice/kuendigung/freenet-mobilfunk',
      alias: ['freenet']),

  // ── 1&1-Netz (Marken der Drillisch Online GmbH) ──────────────────────────
  MobilfunkAnbieter('winSIM', kNetzEinsUndEins, 'Brandingmarke',
      kuendigungUrl: 'https://www.winsim.de/kuendigung'),
  MobilfunkAnbieter('PremiumSIM', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.premiumsim.de/kuendigung'),
  MobilfunkAnbieter('sim.de', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.sim.de/kuendigung'),
  MobilfunkAnbieter('smartmobil.de', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.smartmobil.de/kuendigung', alias: ['smartmobil']),
  MobilfunkAnbieter('simplytel', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.simplytel.de/kuendigung', alias: ['simply']),
  MobilfunkAnbieter('handyvertrag.de', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.handyvertrag.de/kuendigung', alias: ['handyvertrag']),
  MobilfunkAnbieter('yourfone', kNetzEinsUndEins, 'Brandingmarke'),
  MobilfunkAnbieter('maXXim', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.maxxim.de/kuendigung'),
  MobilfunkAnbieter('Black SIM', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.blacksim.de/kuendigung'),
  MobilfunkAnbieter('CyberSIM', kNetzEinsUndEins, 'Eigenmarke',
      kuendigungUrl: 'https://www.cybersim.de/kuendigung'),
  MobilfunkAnbieter('BILDconnect', kNetzEinsUndEins, 'Brandingmarke', alias: ['bild']),
  MobilfunkAnbieter('SIM 24', kNetzEinsUndEins, 'Eigenmarke'),
  MobilfunkAnbieter('simdiscount', kNetzEinsUndEins, 'Eigenmarke'),
  MobilfunkAnbieter('M2M-mobil', kNetzEinsUndEins, 'Eigenmarke', alias: ['m2m']),

  // ── Netzübergreifend (Netz hängt vom gebuchten Tarif ab) ─────────────────
  MobilfunkAnbieter('mobilcom-debitel', 'Telekom, Vodafone oder O2', 'Service-Provider',
      kuendigungUrl: 'https://www.freenet-digital.de/onlineservice/kuendigung/freenet-mobilfunk',
      alias: ['mobilcom', 'debitel', 'md']),
  MobilfunkAnbieter('klarmobil', 'Telekom, Vodafone oder O2', 'Eigenmarke',
      kuendigungUrl: 'https://www.freenet-digital.de/onlineservice/kuendigung/klarmobil/',
      alias: ['klarmobil.de']),
  MobilfunkAnbieter('Crash', 'Vodafone oder Telekom', 'Eigenmarke',
      kuendigungUrl: 'https://www.crash-tarife.de/kuendigung', alias: ['crash tarife']),
  MobilfunkAnbieter('Amiva', 'Vodafone oder O2', 'Eigenmarke', alias: ['tele2']),
  MobilfunkAnbieter('Wherever SIM', 'Telekom, Vodafone oder O2', 'Service-Provider',
      alias: ['wherever']),
  MobilfunkAnbieter('FUSION IoT', 'Telekom, Vodafone oder O2', 'Service-Provider',
      alias: ['fusion']),
];

/// Vergleichsform: Kleinschreibung, Umlaute aufgelöst, alles weg, was nur
/// Schreibweise ist.
///
/// ⚠️ Ohne das findet „o2“ nicht „O₂“, „1und1“ nicht „1&1“ und „ay yildiz“
/// nicht „Ay-Yildiz“ — also genau die Fälle, in denen jemand tippt, was er auf
/// der Rechnung sieht.
String mobilfunkSchluessel(String s) {
  var t = s.toLowerCase();
  const ersatz = {
    'ä': 'ae', 'ö': 'oe', 'ü': 'ue', 'ß': 'ss', 'æ': 'ae',
    'é': 'e', 'è': 'e', 'ó': 'o', 'á': 'a', '₂': '2',
  };
  ersatz.forEach((k, v) => t = t.replaceAll(k, v));
  return t.replaceAll(RegExp(r'[^a-z0-9]'), '');
}

/// Sucht den Anbieter zu einem freien Text — auch für Karten, die schon vor
/// dieser Datenbank angelegt wurden.
///
/// ⚠️ Bewusst **nur exakt** (nach Normalisierung), weder `contains` noch
/// Präfix. Ein Präfixtreffer klang zunächst hilfreich, ordnete beim Test aber
/// „SIM“ dem Anbieter sim.de und „Mobil“ dem Anbieter mobilcom-debitel zu —
/// und daran hängt der Knopf „Kündigung online jetzt“. Eine Kündigung beim
/// falschen Anbieter ist teurer als ein fehlender Knopf. Wer eine
/// Schreibweise vermisst, trägt sie als `alias` ein; das ist die Stelle, an
/// der so etwas geprüft werden kann.
MobilfunkAnbieter? mobilfunkAnbieterFinden(String? eingabe) {
  final k = mobilfunkSchluessel(eingabe ?? '');
  if (k.isEmpty) return null;

  for (final a in kMobilfunkAnbieter) {
    if (mobilfunkSchluessel(a.name) == k) return a;
    for (final al in a.alias) {
      if (mobilfunkSchluessel(al) == k) return a;
    }
  }
  return null;
}

/// Filtert die Liste für das Suchfeld. Leere Eingabe = alle.
List<MobilfunkAnbieter> mobilfunkAnbieterSuchen(String eingabe) {
  final k = mobilfunkSchluessel(eingabe);
  if (k.isEmpty) return kMobilfunkAnbieter;

  bool passt(MobilfunkAnbieter a) {
    if (mobilfunkSchluessel(a.name).contains(k)) return true;
    if (a.alias.any((al) => mobilfunkSchluessel(al).contains(k))) return true;
    // Nach Netz suchen dürfen: „vodafone“ soll auch otelo und LIDL Connect
    // zeigen, sonst findet niemand die Zweitmarken seines eigenen Netzes.
    return mobilfunkSchluessel(a.netz).contains(k);
  }

  final treffer = kMobilfunkAnbieter.where(passt).toList();
  // Wer den Namen tippt, will ihn oben sehen — nicht hinter drei Zweitmarken,
  // die ihn nur im Netz-Feld tragen.
  treffer.sort((a, b) {
    int rang(MobilfunkAnbieter x) {
      final n = mobilfunkSchluessel(x.name);
      if (n == k) return 0;
      if (n.startsWith(k)) return 1;
      if (n.contains(k)) return 2;
      return 3;
    }
    final r = rang(a).compareTo(rang(b));
    return r != 0 ? r : a.name.toLowerCase().compareTo(b.name.toLowerCase());
  });
  return treffer;
}

/// Nur die Namen — für die Autovervollständigung im Textfeld.
List<String> get kMobilfunkAnbieterNamen =>
    kMobilfunkAnbieter.map((a) => a.name).toList();
