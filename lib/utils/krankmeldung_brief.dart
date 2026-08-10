/// Erzeugt Betreff und Text der Krankmeldung, die der Verein namens und im
/// Auftrag eines Mitglieds an eine Institution schickt.
///
/// Bewusst ohne Anlage und ohne Diagnose:
/// * Die AU-Bescheinigung wird nicht gespeichert, also kann sie auch nicht
///   angehängt werden — der Brief ist eine *Anzeige*, kein *Nachweis*.
/// * Weder Diagnose noch ICD-Code gehören in ein Schreiben an Jobcenter,
///   Arbeitgeber oder Agentur für Arbeit. Das amtliche AU-Formular für den
///   Arbeitgeber enthält sie ebenfalls nicht.
///
/// Der einzige Satz, der sich je Empfänger unterscheidet, ist der Schlusssatz
/// zum eAU-Abruf. Das ist keine Feinheit, sondern der Kern:
///
/// | Empfänger            | eAU-Abruf | Grundlage        |
/// |----------------------|-----------|------------------|
/// | Arbeitgeber          | ja        | § 5b EntgFG      |
/// | Agentur für Arbeit   | ja        | § 109a SGB IV    |
/// | Jobcenter            | **nein**  | nicht angebunden |
/// | Krankenkasse         | hat sie bereits | § 295 Abs. 1 SGB V |
///
/// Ein an das Jobcenter geschickter eAU-Satz führt dazu, dass dort auf einen
/// Abruf gewartet wird, den es nicht geben kann.
library;

/// Empfängertyp — entscheidet ausschließlich über den Schlusssatz.
enum KrankmeldungEmpfaenger {
  jobcenter,
  krankenkasse,
  arbeitgeber,
  agenturFuerArbeit,
  sonstige,
}

/// Anzeigename für Dropdowns.
String krankmeldungEmpfaengerLabel(KrankmeldungEmpfaenger e) {
  switch (e) {
    case KrankmeldungEmpfaenger.jobcenter:
      return 'Jobcenter';
    case KrankmeldungEmpfaenger.krankenkasse:
      return 'Krankenkasse';
    case KrankmeldungEmpfaenger.arbeitgeber:
      return 'Arbeitgeber';
    case KrankmeldungEmpfaenger.agenturFuerArbeit:
      return 'Agentur für Arbeit';
    case KrankmeldungEmpfaenger.sonstige:
      return 'Sonstige Stelle';
  }
}

/// Alles, was der Brief braucht. Nichts davon wird zusätzlich gespeichert —
/// die Personendaten kommen bei der Erzeugung aus Verifizierung Stufe 1, die
/// Aktenzeichen aus `jobcenter_data` bzw. den Krankenkassendaten, die Termine
/// aus dem Krankmeldungs-Eintrag selbst.
class KrankmeldungBriefDaten {
  final String vorname;
  final String nachname;

  /// ISO (`yyyy-MM-dd`) oder bereits deutsch — beides wird akzeptiert.
  final String geburtsdatum;

  final String strasse;
  final String hausnummer;
  final String plz;
  final String ort;

  /// Aktenzeichen beim Empfänger, z. B. ('Kundennummer', '12345/6789') oder
  /// ('Versichertennummer', 'A123456789'). Leer lassen, wenn unbekannt.
  final String aktenzeichenLabel;
  final String aktenzeichen;

  /// Zweites Aktenzeichen, beim Jobcenter die BG-Nummer.
  final String zweitAktenzeichenLabel;
  final String zweitAktenzeichen;

  /// `'erst'` oder `'folge'`.
  final String art;

  final String feststellungsdatum;
  final String auBeginn;
  final String auEnde;

  final bool arbeitsunfall;

  const KrankmeldungBriefDaten({
    required this.vorname,
    required this.nachname,
    this.geburtsdatum = '',
    this.strasse = '',
    this.hausnummer = '',
    this.plz = '',
    this.ort = '',
    this.aktenzeichenLabel = '',
    this.aktenzeichen = '',
    this.zweitAktenzeichenLabel = '',
    this.zweitAktenzeichen = '',
    this.art = 'erst',
    this.feststellungsdatum = '',
    this.auBeginn = '',
    this.auEnde = '',
    this.arbeitsunfall = false,
  });

  String get vollerName => '$vorname $nachname'.trim();

  bool get istFolge => art == 'folge';
}

/// Liefert Vor- und Nachnamen. Sind die getrennten Felder aus Stufe 1 gefüllt,
/// gewinnen sie; sonst wird der volle Name am letzten Leerzeichen zerlegt.
/// Das ist eine Näherung — bei „Max von der Heide" landet „von der" im Vornamen —
/// aber sie schreibt nie einen falschen Namen, nur eine falsche Grenze, und die
/// getrennten Felder sind bei verifizierten Mitgliedern ohnehin da.
({String vorname, String nachname}) krankmeldungNamenTeilen(
  String? vorname,
  String? nachname,
  String vollerName,
) {
  final vn = (vorname ?? '').trim();
  final nn = (nachname ?? '').trim();
  if (vn.isNotEmpty || nn.isNotEmpty) return (vorname: vn, nachname: nn);

  final voll = vollerName.trim();
  if (voll.isEmpty) return (vorname: '', nachname: '');
  final letzte = voll.lastIndexOf(' ');
  if (letzte < 0) return (vorname: '', nachname: voll);
  return (
    vorname: voll.substring(0, letzte).trim(),
    nachname: voll.substring(letzte + 1).trim(),
  );
}

/// `2026-08-03` → `03.08.2026`. Alles andere bleibt unverändert, damit ein
/// bereits deutsch formatiertes Datum nicht zerschossen wird.
String krankmeldungDatum(String wert) {
  final roh = wert.trim();
  if (roh.isEmpty) return '';
  // Ein evtl. angehängter Zeitanteil interessiert hier nicht.
  final nurDatum = roh.split(' ').first;
  final d = DateTime.tryParse(nurDatum);
  if (d == null) return roh;
  final tt = d.day.toString().padLeft(2, '0');
  final mm = d.month.toString().padLeft(2, '0');
  return '$tt.$mm.${d.year}';
}

/// Betreffzeile. Aktenzeichen gehören hinein: ohne sie landet das Schreiben
/// im Stapel, ohne dem Vorgang zugeordnet zu werden.
String krankmeldungBetreff(KrankmeldungBriefDaten d) {
  final teile = <String>[
    'Arbeitsunfähigkeit (${d.istFolge ? 'Folgebescheinigung' : 'Erstbescheinigung'})',
    d.vollerName,
  ];
  final geb = krankmeldungDatum(d.geburtsdatum);
  if (geb.isNotEmpty) teile.add('geb. $geb');
  if (d.aktenzeichen.trim().isNotEmpty) {
    final label = d.aktenzeichenLabel.trim().isEmpty ? 'Az.' : d.aktenzeichenLabel.trim();
    teile.add('$label ${d.aktenzeichen.trim()}');
  }
  if (d.zweitAktenzeichen.trim().isNotEmpty) {
    final label = d.zweitAktenzeichenLabel.trim().isEmpty ? 'Az.' : d.zweitAktenzeichenLabel.trim();
    teile.add('$label ${d.zweitAktenzeichen.trim()}');
  }
  // Erstes Element mit Gedankenstrich abgetrennt, der Rest mit Komma.
  return '${teile.first} – ${teile.skip(1).join(', ')}';
}

/// Der je Empfänger unterschiedliche Schlusssatz. Leer für [KrankmeldungEmpfaenger.sonstige]:
/// zu einer unbekannten Stelle lässt sich nichts Wahres über den eAU-Abruf sagen,
/// und ein falscher Satz ist schlechter als keiner.
String krankmeldungHinweissatz(KrankmeldungEmpfaenger empfaenger) {
  switch (empfaenger) {
    case KrankmeldungEmpfaenger.jobcenter:
      return 'Die ärztliche Arbeitsunfähigkeitsbescheinigung wird gesondert vorgelegt. '
          'Ein elektronischer Abruf der eAU ist für das Jobcenter nicht möglich.';
    case KrankmeldungEmpfaenger.arbeitgeber:
      return 'Die elektronische Arbeitsunfähigkeitsbescheinigung (eAU) können Sie '
          'gemäß § 5b EntgFG bei der Krankenkasse abrufen.';
    case KrankmeldungEmpfaenger.agenturFuerArbeit:
      return 'Die elektronische Arbeitsunfähigkeitsbescheinigung (eAU) können Sie '
          'gemäß § 109a SGB IV bei der Krankenkasse abrufen.';
    case KrankmeldungEmpfaenger.krankenkasse:
      return 'Die elektronische Arbeitsunfähigkeitsbescheinigung (eAU) wurde von der '
          'behandelnden Praxis nach § 295 Abs. 1 SGB V an Sie übermittelt.';
    case KrankmeldungEmpfaenger.sonstige:
      return '';
  }
}

/// Der vollständige Brieftext ohne Signatur — die hängt der Aufrufer aus der
/// Mail-Signatur des Vereins an, damit Vorstand und Impressum aus derselben
/// Quelle stammen wie in jeder anderen Vereinsmail.
String krankmeldungText(KrankmeldungBriefDaten d, KrankmeldungEmpfaenger empfaenger) {
  final sb = StringBuffer();
  sb.writeln('Sehr geehrte Damen und Herren,');
  sb.writeln();

  // --- Satz 1: wer, für wen, welcher Zeitraum ---
  final anschrift = <String>[
    '${d.strasse} ${d.hausnummer}'.trim(),
    '${d.plz} ${d.ort}'.trim(),
  ].where((t) => t.isNotEmpty).join(', ');

  final person = StringBuffer('namens und im Auftrag unseres Mitglieds ${d.vollerName}');
  final geb = krankmeldungDatum(d.geburtsdatum);
  if (geb.isNotEmpty) person.write(', geboren am $geb');
  if (anschrift.isNotEmpty) person.write(', wohnhaft $anschrift');

  final beginn = krankmeldungDatum(d.auBeginn);
  final ende = krankmeldungDatum(d.auEnde);
  final String zeitraum;
  if (beginn.isNotEmpty && ende.isNotEmpty) {
    zeitraum = 'vom $beginn bis voraussichtlich $ende';
  } else if (beginn.isNotEmpty) {
    zeitraum = 'seit dem $beginn';
  } else if (ende.isNotEmpty) {
    zeitraum = 'bis voraussichtlich $ende';
  } else {
    zeitraum = '';
  }
  person.write(zeitraum.isEmpty ? ', melden wir Arbeitsunfähigkeit.' : ', melden wir Arbeitsunfähigkeit $zeitraum.');
  sb.writeln(person.toString());
  sb.writeln();

  // --- Satz 2: Art der Bescheinigung ---
  final artWort = d.istFolge ? 'eine Folgebescheinigung' : 'eine Erstbescheinigung';
  final fest = krankmeldungDatum(d.feststellungsdatum);
  sb.writeln(fest.isEmpty
      ? 'Es handelt sich um $artWort.'
      : 'Es handelt sich um $artWort, festgestellt am $fest.');

  // --- Satz 3 (nur bei Arbeitsunfall): ändert die Zuständigkeit ---
  if (d.arbeitsunfall) {
    sb.writeln('Die Arbeitsunfähigkeit beruht auf einem Arbeitsunfall.');
  }

  // --- Satz 4: Schlusssatz je Empfänger ---
  final hinweis = krankmeldungHinweissatz(empfaenger);
  if (hinweis.isNotEmpty) {
    sb.writeln();
    sb.writeln(hinweis);
  }

  sb.writeln();
  sb.write('Mit freundlichen Grüßen');
  return sb.toString();
}
