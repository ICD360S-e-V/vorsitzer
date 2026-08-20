/// Wie echt ist dieser Absender?
///
/// Zwei getrennte Quellen, die nie vermischt werden dürfen:
///
/// * **`Authentication-Results`** — was der eigene Mailserver beim Empfang
///   geprüft hat (DKIM, SPF, DMARC). Das ist eine Messung.
/// * **Anzeigename gegen Adresse** — was ein Mensch sieht, gegen das, was
///   wirklich dasteht. Das ist ein Verdacht, keine Messung.
///
/// ⚠️ Die zweite Prüfung ist der Grund, warum es diese Datei überhaupt gibt.
/// DMARC kann `pass` melden und die Mail trotzdem eine Fälschung sein: geprüft
/// wird die Domain im `From`, nicht der Name davor. Wer
/// `"Amtsgericht Ulm" <kontakt@gmx.net>` schickt, besteht DMARC für gmx.net —
/// und im Posteingang steht „Amtsgericht Ulm“. Genau diese Post geht hier
/// durch.
library;

/// Ergebnis einer einzelnen Prüfung des empfangenden Servers.
enum MailPruefwert {
  /// Bestanden.
  bestanden,

  /// Durchgefallen — die Domain behauptet, das nicht geschickt zu haben.
  gescheitert,

  /// Der Absender hat es weich formuliert (`softfail`, `neutral`, `policy`).
  weich,

  /// Der Absender veröffentlicht dazu nichts (`none`).
  keine,

  /// Die Prüfung selbst ging schief (`temperror`, `permerror`).
  fehler,

  /// Der Server hat dazu nichts geliefert.
  unbekannt,
}

MailPruefwert _wert(String roh) {
  switch (roh.trim().toLowerCase()) {
    case 'pass':
      return MailPruefwert.bestanden;
    case 'fail':
      return MailPruefwert.gescheitert;
    case 'softfail':
    case 'neutral':
    case 'policy':
      return MailPruefwert.weich;
    case 'none':
      return MailPruefwert.keine;
    case 'temperror':
    case 'permerror':
      return MailPruefwert.fehler;
    default:
      return MailPruefwert.unbekannt;
  }
}

/// Die drei Prüfungen aus `Authentication-Results`, so wie unser Server sie
/// beim Empfang festgehalten hat.
class MailEchtheit {
  final MailPruefwert dkim;
  final MailPruefwert spf;
  final MailPruefwert dmarc;

  /// Die Domain, für die DKIM signiert hat (`header.d=`).
  final String dkimDomain;

  const MailEchtheit({
    this.dkim = MailPruefwert.unbekannt,
    this.spf = MailPruefwert.unbekannt,
    this.dmarc = MailPruefwert.unbekannt,
    this.dkimDomain = '',
  });

  /// Der Server hat überhaupt etwas geprüft.
  bool get hatBefund =>
      dkim != MailPruefwert.unbekannt ||
      spf != MailPruefwert.unbekannt ||
      dmarc != MailPruefwert.unbekannt;

  /// Mindestens eine Prüfung ist durchgefallen.
  ///
  /// ⚠️ Bewusst nur `gescheitert`, nicht `keine`: sehr viele kleine Absender —
  /// Praxen, Kanzleien, Ämter — veröffentlichen bis heute kein DKIM. Wer das
  /// als Warnung zeigt, warnt bei jeder zweiten echten Mail, und dann liest
  /// niemand mehr hin, wenn es einmal zählt.
  bool get istGescheitert =>
      dkim == MailPruefwert.gescheitert ||
      spf == MailPruefwert.gescheitert ||
      dmarc == MailPruefwert.gescheitert;

  /// Alles, was geprüft wurde, ist bestanden — und DMARC war dabei.
  ///
  /// DMARC ist die Bedingung, weil nur es Absenderdomain und Signatur
  /// aneinander bindet: SPF allein bestätigt den Umschlag, nicht den Briefkopf.
  bool get istBestaetigt =>
      dmarc == MailPruefwert.bestanden && !istGescheitert;
}

final _arTeil = RegExp(r'\b(dkim|spf|dmarc)\s*=\s*([a-z]+)', caseSensitive: false);
final _arDomain = RegExp(r'header\.d\s*=\s*([A-Za-z0-9.-]+)', caseSensitive: false);

/// Liest `Authentication-Results`.
///
/// ⚠️ Es kann **mehrere** solche Kopfzeilen geben — jede Station auf dem Weg
/// darf eine anhängen, und eine gefälschte davon ist trivial hinzuzufügen. Der
/// Server liefert uns deshalb nur die **eigene**; hier wird zusätzlich die
/// zuerst gefundene Angabe je Prüfung behalten und nicht die letzte, damit ein
/// nachgereichtes „dmarc=pass“ ein früheres `fail` nicht überschreibt.
MailEchtheit mailEchtheitLesen(String? authResults) {
  final roh = (authResults ?? '').trim();
  if (roh.isEmpty) return const MailEchtheit();
  var dkim = MailPruefwert.unbekannt;
  var spf = MailPruefwert.unbekannt;
  var dmarc = MailPruefwert.unbekannt;
  for (final m in _arTeil.allMatches(roh)) {
    final wert = _wert(m.group(2)!);
    switch (m.group(1)!.toLowerCase()) {
      case 'dkim':
        if (dkim == MailPruefwert.unbekannt) dkim = wert;
        break;
      case 'spf':
        if (spf == MailPruefwert.unbekannt) spf = wert;
        break;
      case 'dmarc':
        if (dmarc == MailPruefwert.unbekannt) dmarc = wert;
        break;
    }
  }
  return MailEchtheit(
    dkim: dkim,
    spf: spf,
    dmarc: dmarc,
    dkimDomain: _arDomain.firstMatch(roh)?.group(1)?.toLowerCase() ?? '',
  );
}

// ---------------------------------------------------------------------------
// Anzeigename gegen Adresse
// ---------------------------------------------------------------------------

/// Warum ein Absender verdächtig aussieht.
enum MailVerdacht {
  /// Kein Verdacht.
  keiner,

  /// Der Anzeigename IST eine E-Mail-Adresse — eine andere als die echte.
  ///
  /// Der schärfste Fall: `"post@amtsgericht-ulm.de" <abc@gmail.com>`. In jeder
  /// Liste steht dann die fremde Adresse, und sie ist nicht die, an die eine
  /// Antwort geht.
  andereAdresseImNamen,

  /// Der Anzeigename nennt eine Domain, die nicht die des Absenders ist.
  andereDomainImNamen,

  /// Der Anzeigename mischt Schriftsysteme — lateinische und kyrillische
  /// Buchstaben im selben Wort. Anders als bei einem Namen, der ganz kyrillisch
  /// geschrieben ist, gibt es dafür keinen harmlosen Grund.
  gemischteSchrift,
}

final _adresseImNamen =
    RegExp(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
final _domainImNamen = RegExp(
    r'\b([A-Za-z0-9](?:[A-Za-z0-9-]*[A-Za-z0-9])?(?:\.[A-Za-z0-9-]+)*\.'
    r'(?:de|com|net|org|eu|at|ch|info|biz|io|gov|bayern))\b',
    caseSensitive: false);

// U+0400..U+04FF kyrillisch, U+0370..U+03FF griechisch — die beiden Blöcke, aus
// denen die bekannten Verwechslungszeichen (а, е, о, р, с, ѕ / ο, ρ, ς) stammen.
final _fremdeSchrift = RegExp(r'[Ѐ-ӿͰ-Ͽ]');
final _lateinisch = RegExp(r'[A-Za-z]');

/// Zerlegt `"Name" <adresse@example.org>`.
///
/// Gibt `('', roh)` zurück, wenn kein Anzeigename dasteht — dann gibt es auch
/// nichts zu vergleichen.
({String name, String adresse}) mailAbsenderTeile(String roh) {
  final s = roh.trim();
  final spitz = RegExp(r'^(.*?)<([^<>]+)>\s*$').firstMatch(s);
  if (spitz == null) return (name: '', adresse: s);
  var name = spitz.group(1)!.trim();
  if (name.length >= 2 && name.startsWith('"') && name.endsWith('"')) {
    name = name.substring(1, name.length - 1).trim();
  }
  return (name: name, adresse: spitz.group(2)!.trim());
}

String _domainVon(String adresse) {
  final at = adresse.lastIndexOf('@');
  return at < 0 ? '' : adresse.substring(at + 1).trim().toLowerCase();
}

/// Ist [kandidat] dieselbe Domain wie [echt] oder eine Unterdomain davon?
///
/// ⚠️ Auf Labelgrenze prüfen, nicht mit `endsWith`: sonst gilt
/// `boesesparkasse.de` als Unterdomain von `sparkasse.de` und der Verdacht
/// fällt genau bei der Schreibweise weg, für die er gedacht war.
bool _gleicheDomain(String kandidat, String echt) {
  if (kandidat.isEmpty || echt.isEmpty) return false;
  if (kandidat == echt) return true;
  return kandidat.endsWith('.$echt') || echt.endsWith('.$kandidat');
}

/// Prüft den Anzeigename gegen die wirkliche Adresse.
///
/// ⚠️ Das Ergebnis ist ein **Verdacht**, kein Urteil. Ein Newsletter, der sich
/// „service@example.com“ nennt und von „bounce@mailer.example.com“ kommt, ist
/// nicht bösartig — nur schlecht eingerichtet. Deshalb heißt die Anzeige
/// „Absender prüfen“ und nicht „Betrug“.
MailVerdacht mailAbsenderVerdacht(String rohesFrom) {
  final teile = mailAbsenderTeile(rohesFrom);
  final name = teile.name;
  if (name.isEmpty) return MailVerdacht.keiner;
  final echteDomain = _domainVon(teile.adresse);

  final imNamen = _adresseImNamen.firstMatch(name)?.group(0);
  if (imNamen != null) {
    if (imNamen.toLowerCase() != teile.adresse.toLowerCase()) {
      return MailVerdacht.andereAdresseImNamen;
    }
    // Name und Adresse sind dieselbe Adresse — der Normalfall bei Absendern
    // ganz ohne Namen. Kein Verdacht, und die Domainprüfung würde hier nur
    // dieselbe Domain mit sich selbst vergleichen.
    return MailVerdacht.keiner;
  }

  for (final m in _domainImNamen.allMatches(name)) {
    if (!_gleicheDomain(m.group(1)!.toLowerCase(), echteDomain)) {
      return MailVerdacht.andereDomainImNamen;
    }
  }

  // Gemischt heißt: beide Schriften im GANZEN Namen. Ein durchgehend
  // kyrillischer Name ist einfach ein Name — bei 52 Mitgliedern mit ru/uk/bg
  // wäre alles andere eine Beleidigung.
  if (_fremdeSchrift.hasMatch(name) && _lateinisch.hasMatch(name)) {
    return MailVerdacht.gemischteSchrift;
  }
  return MailVerdacht.keiner;
}

/// Ein Satz, der erklärt, was auffällt — nie ein Urteil.
String mailVerdachtText(MailVerdacht v) {
  switch (v) {
    case MailVerdacht.andereAdresseImNamen:
      return 'Der angezeigte Name ist selbst eine E-Mail-Adresse — aber eine '
          'andere als die, von der diese Nachricht kommt.';
    case MailVerdacht.andereDomainImNamen:
      return 'Der angezeigte Name nennt eine andere Herkunft, als die Adresse '
          'des Absenders hat.';
    case MailVerdacht.gemischteSchrift:
      return 'Im Namen des Absenders stehen lateinische und kyrillische oder '
          'griechische Buchstaben gemischt — ein bekannter Trick, um einen '
          'vertrauten Namen nachzuahmen.';
    case MailVerdacht.keiner:
      return '';
  }
}
