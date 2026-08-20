/// Sucheingaben in Felder zerlegen.
///
/// Die Suche war bisher Freitext im gerade offenen Ordner — und wurde beim
/// Ordnerwechsel verworfen. Für ein Postfach, das jahrelang wächst, ist das die
/// falsche Frage: „wo liegt der Brief vom Jobcenter?" lässt sich so nur
/// beantworten, wenn man schon weiß, wo er liegt.
///
/// Deshalb hier eine kleine Feldsprache, deutsch wie die Oberfläche:
///
/// ```text
/// von:jobcenter hat:anhang seit:2026-01-01 Widerspruch
/// ```
///
/// ⚠️ Alles, was nicht als Feld erkannt wird, bleibt Freitext. Wer nur
/// „Widerspruch" tippt, bekommt genau das, was er vorher bekommen hat — eine
/// Suchsprache, die einfache Eingaben umdeutet, ist eine Falle.
library;

/// Eine zerlegte Suchanfrage.
class MailSuche {
  /// Freitext über die ganze Nachricht.
  final String text;

  final String von;
  final String an;
  final String betreff;

  /// `null` = nicht gefragt. `true` = nur mit Anhang, `false` = nur ohne.
  final bool? hatAnhang;

  /// `null` = nicht gefragt. `true` = nur ungelesen.
  final bool? ungelesen;

  /// `null` = nicht gefragt. `true` = nur markierte (Stern).
  final bool? markiert;

  /// ISO-Datum `YYYY-MM-DD`, leer = offen.
  final String seit;
  final String bis;

  /// Über alle Ordner suchen statt nur im geöffneten.
  final bool alleOrdner;

  const MailSuche({
    this.text = '',
    this.von = '',
    this.an = '',
    this.betreff = '',
    this.hatAnhang,
    this.ungelesen,
    this.markiert,
    this.seit = '',
    this.bis = '',
    this.alleOrdner = false,
  });

  /// Nichts angegeben — dann ist es keine Suche, sondern der normale Ordner.
  bool get istLeer =>
      text.isEmpty &&
      von.isEmpty &&
      an.isEmpty &&
      betreff.isEmpty &&
      hatAnhang == null &&
      ungelesen == null &&
      markiert == null &&
      seit.isEmpty &&
      bis.isEmpty;

  /// Es steht mehr da als Freitext — nur dann lohnt es, dem Nutzer die erkannten
  /// Felder als Chips zu zeigen.
  bool get hatFelder =>
      von.isNotEmpty ||
      an.isNotEmpty ||
      betreff.isNotEmpty ||
      hatAnhang != null ||
      ungelesen != null ||
      markiert != null ||
      seit.isNotEmpty ||
      bis.isNotEmpty ||
      alleOrdner;

  /// Für die Übertragung an `mail/list.php`. Leere Felder fallen weg, damit ein
  /// alter Server die Anfrage weiterhin als reine Textsuche versteht.
  Map<String, dynamic> alsFelder() => {
        if (text.isNotEmpty) 'search': text,
        if (von.isNotEmpty) 'von': von,
        if (an.isNotEmpty) 'an': an,
        if (betreff.isNotEmpty) 'betreff': betreff,
        if (hatAnhang != null) 'hat_anhang': hatAnhang! ? 1 : 0,
        if (ungelesen != null) 'ungelesen': ungelesen! ? 1 : 0,
        if (markiert != null) 'markiert': markiert! ? 1 : 0,
        if (seit.isNotEmpty) 'seit': seit,
        if (bis.isNotEmpty) 'bis': bis,
        if (alleOrdner) 'alle_ordner': 1,
      };
}

/// Schlüsselwort => Feld. Deutsch und englisch, weil beides getippt wird.
const _felder = {
  'von': 'von', 'from': 'von', 'absender': 'von',
  'an': 'an', 'to': 'an', 'empfaenger': 'an', 'empfänger': 'an',
  'betreff': 'betreff', 'subject': 'betreff',
  'hat': 'hat', 'has': 'hat',
  'ist': 'ist', 'is': 'ist',
  'seit': 'seit', 'after': 'seit', 'nach': 'seit',
  'bis': 'bis', 'before': 'bis', 'vor': 'bis',
  'ordner': 'ordner', 'in': 'ordner',
};

// Ein Wort, dann ':', dann entweder "in Anführungszeichen" oder bis zum
// nächsten Leerzeichen.
final _token = RegExp(r'(\w+):(?:"([^"]*)"|(\S+))');

/// Deutsche und ISO-Datumsangaben zu `YYYY-MM-DD`.
///
/// ⚠️ Zweistellige Jahre werden **nicht** geraten. `01.02.26` könnte 1926 oder
/// 2026 sein, und eine Suche, die stillschweigend hundert Jahre danebenliegt,
/// liefert null Treffer, ohne zu sagen warum.
String mailDatumNormalisieren(String roh) {
  final s = roh.trim();
  final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})$').firstMatch(s);
  if (iso != null) {
    return '${iso.group(1)}-${_zwei(iso.group(2)!)}-${_zwei(iso.group(3)!)}';
  }
  final de = RegExp(r'^(\d{1,2})\.(\d{1,2})\.(\d{4})$').firstMatch(s);
  if (de != null) {
    return '${de.group(3)}-${_zwei(de.group(2)!)}-${_zwei(de.group(1)!)}';
  }
  return '';
}

String _zwei(String n) => n.padLeft(2, '0');

/// Zerlegt die Eingabe des Suchfelds.
MailSuche mailSucheLesen(String eingabe) {
  var rest = eingabe;
  var von = '', an = '', betreff = '', seit = '', bis = '';
  bool? hatAnhang, ungelesen, markiert;
  var alleOrdner = false;

  for (final m in _token.allMatches(eingabe)) {
    final feld = _felder[m.group(1)!.toLowerCase()];
    if (feld == null) continue; // kein Feld — bleibt Freitext, z. B. „http://"
    final wert = (m.group(2) ?? m.group(3) ?? '').trim();
    var erkannt = true;
    switch (feld) {
      case 'von':
        von = wert;
        break;
      case 'an':
        an = wert;
        break;
      case 'betreff':
        betreff = wert;
        break;
      case 'hat':
        final w = wert.toLowerCase();
        if (w == 'anhang' || w == 'attachment' || w == 'datei') {
          hatAnhang = true;
        } else {
          erkannt = false;
        }
        break;
      case 'ist':
        switch (wert.toLowerCase()) {
          case 'ungelesen':
          case 'unread':
            ungelesen = true;
            break;
          case 'gelesen':
          case 'read':
            ungelesen = false;
            break;
          case 'markiert':
          case 'flagged':
            markiert = true;
            break;
          default:
            erkannt = false;
        }
        break;
      case 'seit':
        seit = mailDatumNormalisieren(wert);
        erkannt = seit.isNotEmpty;
        break;
      case 'bis':
        bis = mailDatumNormalisieren(wert);
        erkannt = bis.isNotEmpty;
        break;
      case 'ordner':
        final w = wert.toLowerCase();
        alleOrdner = w == 'alle' || w == 'all' || w == '*';
        erkannt = alleOrdner;
        break;
    }
    // Nur wegschneiden, was auch verstanden wurde. Ein unverstandenes
    // „hat:zeit" muss als Freitext übrig bleiben, sonst sucht der Nutzer nach
    // etwas, das er nie eingegeben hat.
    if (erkannt) rest = rest.replaceFirst(m.group(0)!, ' ');
  }

  return MailSuche(
    text: rest.trim().replaceAll(RegExp(r'\s+'), ' '),
    von: von,
    an: an,
    betreff: betreff,
    hatAnhang: hatAnhang,
    ungelesen: ungelesen,
    markiert: markiert,
    seit: seit,
    bis: bis,
    alleOrdner: alleOrdner,
  );
}

/// Die erkannten Felder als kurze Beschriftungen — für die Chips unter dem
/// Suchfeld. Sie sind der einzige Weg, auf dem der Nutzer merkt, dass aus
/// seinem Getippten eine Feldsuche geworden ist.
List<String> mailSucheChips(MailSuche s) => [
      if (s.von.isNotEmpty) 'Von: ${s.von}',
      if (s.an.isNotEmpty) 'An: ${s.an}',
      if (s.betreff.isNotEmpty) 'Betreff: ${s.betreff}',
      if (s.hatAnhang == true) 'mit Anhang',
      if (s.ungelesen == true) 'ungelesen',
      if (s.ungelesen == false) 'gelesen',
      if (s.markiert == true) 'markiert',
      if (s.seit.isNotEmpty) 'seit ${s.seit}',
      if (s.bis.isNotEmpty) 'bis ${s.bis}',
      if (s.alleOrdner) 'alle Ordner',
    ];

/// Die Hilfe, die im leeren Suchfeld steht.
const List<({String muster, String bedeutung})> kMailSucheHilfe = [
  (muster: 'von:jobcenter', bedeutung: 'Absender enthält „jobcenter“'),
  (muster: 'an:datenschutz', bedeutung: 'Empfänger enthält „datenschutz“'),
  (muster: 'betreff:"Widerspruch"', bedeutung: 'Betreff enthält den Ausdruck'),
  (muster: 'hat:anhang', bedeutung: 'nur Nachrichten mit Datei'),
  (muster: 'ist:ungelesen', bedeutung: 'nur ungelesene'),
  (muster: 'seit:01.01.2026', bedeutung: 'ab diesem Tag'),
  (muster: 'ordner:alle', bedeutung: 'in allen Ordnern suchen'),
];
