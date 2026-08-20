/// Textbausteine für wiederkehrende Briefe.
///
/// Der Verein schreibt dieselben Schreiben immer wieder: Widerspruch,
/// Terminanfrage an eine Praxis, Anschreiben zu einer Vollmacht, Erinnerung an
/// eine Frist. Bisher gab es dafür nur die Signatur — den Brieftext hat jedes
/// Mal jemand neu getippt, und jedes Mal ein bisschen anders.
///
/// ⚠️ Eine Vorlage füllt **nie** automatisch aus und sendet **nie** von selbst.
/// Sie legt Text ins Verfassen-Feld, wo er gelesen und geändert wird, bevor er
/// hinausgeht. Ein Schreiben an ein Amt, das niemand vor dem Senden gelesen
/// hat, ist der eigentliche Schaden — nicht die Tipparbeit.
library;

/// Ein gespeicherter Baustein.
class MailVorlage {
  final int id;
  final String titel;
  final String betreff;
  final String text;

  /// Sortierung in der Liste; gleiche Werte sortieren alphabetisch nach Titel.
  final int reihenfolge;

  const MailVorlage({
    this.id = 0,
    required this.titel,
    this.betreff = '',
    required this.text,
    this.reihenfolge = 0,
  });

  factory MailVorlage.fromJson(Map<String, dynamic> j) => MailVorlage(
        id: (j['id'] as num?)?.toInt() ?? 0,
        titel: '${j['titel'] ?? ''}',
        betreff: '${j['betreff'] ?? ''}',
        text: '${j['text'] ?? ''}',
        reihenfolge: (j['reihenfolge'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'titel': titel,
        'betreff': betreff,
        'text': text,
        'reihenfolge': reihenfolge,
      };

  MailVorlage copyWith({String? titel, String? betreff, String? text}) =>
      MailVorlage(
        id: id,
        titel: titel ?? this.titel,
        betreff: betreff ?? this.betreff,
        text: text ?? this.text,
        reihenfolge: reihenfolge,
      );
}

/// Ein Platzhalter, den eine Vorlage benutzen darf.
class MailPlatzhalter {
  final String schluessel;
  final String beschreibung;

  const MailPlatzhalter(this.schluessel, this.beschreibung);
}

/// Die vollständige Liste. Was hier nicht steht, wird nicht ersetzt.
///
/// ⚠️ Bewusst geschlossen und klein. Ein Platzhalter, der aus irgendeinem Feld
/// der Mitgliederverwaltung liest, wäre ein Weg, über den Gesundheits- oder
/// Behördendaten unbemerkt in ein Schreiben an einen Dritten geraten. Hier
/// steht nur, was auf einem Briefkopf ohnehin steht.
const List<MailPlatzhalter> kMailPlatzhalter = [
  MailPlatzhalter('anrede', 'Sehr geehrte Frau … / Sehr geehrter Herr …'),
  MailPlatzhalter('name', 'Vor- und Nachname des Empfängers'),
  MailPlatzhalter('vorname', 'Vorname des Empfängers'),
  MailPlatzhalter('nachname', 'Nachname des Empfängers'),
  MailPlatzhalter('mitgliedsnummer', 'Mitgliedsnummer des Empfängers'),
  MailPlatzhalter('datum', 'heutiges Datum, z. B. 20.08.2026'),
  MailPlatzhalter('absender', 'Name der angemeldeten Person'),
];

final _platzhalterMuster = RegExp(r'\{([a-zA-Z_]+)\}');

/// Die Werte, mit denen eine Vorlage gefüllt wird.
class MailVorlageDaten {
  final String anrede;
  final String vorname;
  final String nachname;
  final String mitgliedsnummer;
  final String absender;
  final DateTime? heute;

  const MailVorlageDaten({
    this.anrede = '',
    this.vorname = '',
    this.nachname = '',
    this.mitgliedsnummer = '',
    this.absender = '',
    this.heute,
  });

  String get name => [vorname, nachname]
      .where((s) => s.trim().isNotEmpty)
      .join(' ')
      .trim();
}

String _zwei(int n) => n.toString().padLeft(2, '0');

/// Setzt die Platzhalter ein.
///
/// ⚠️ Ein Platzhalter ohne Wert wird **stehen gelassen**, nicht durch nichts
/// ersetzt. „Sehr geehrte {anrede}," fällt beim Lesen auf; „Sehr geehrte ,"
/// sieht nach einem Programmfehler aus und geht trotzdem hinaus — genau das ist
/// bei der Kontakt-Erinnerung schon einmal an sieben echte Menschen gegangen.
///
/// ⚠️ Ein unbekannter Platzhalter bleibt ebenfalls stehen. Er ist ein Tippfehler
/// des Verfassers, und stillschweigendes Löschen macht daraus eine Lücke, die
/// niemand mehr findet.
String mailVorlageFuellen(String text, MailVorlageDaten d) {
  final tag = d.heute;
  final werte = <String, String>{
    'anrede': d.anrede,
    'name': d.name,
    'vorname': d.vorname,
    'nachname': d.nachname,
    'mitgliedsnummer': d.mitgliedsnummer,
    'absender': d.absender,
    'datum': tag == null
        ? ''
        : '${_zwei(tag.day)}.${_zwei(tag.month)}.${tag.year}',
  };
  return text.replaceAllMapped(_platzhalterMuster, (m) {
    final wert = werte[m.group(1)!.toLowerCase()];
    if (wert == null || wert.trim().isEmpty) return m.group(0)!;
    return wert;
  });
}

/// Die Platzhalter, die nach dem Füllen noch offen sind — sie gehören dem
/// Verfasser gemeldet, bevor er auf Senden drückt.
List<String> mailVorlageOffenePlatzhalter(String gefuellterText) => _platzhalterMuster
    .allMatches(gefuellterText)
    .map((m) => m.group(1)!)
    .toSet()
    .toList()
  ..sort();
