/// Das Adressbuch des Verfassen-Bildschirms — Antwort lesen und Adressen in ein
/// Empfängerfeld einsetzen.
///
/// Hier steht nur, was ohne Bildschirm prüfbar ist. Genau das ist der Teil, der
/// still danebenliegen kann: eine Liste, die als Objekt gelesen wird, oder eine
/// Adresse, die zweimal im Feld landet, fällt beim Hinsehen nicht auf.
library;

/// Ein Eintrag aus dem Adressbuch.
class MailKontakt {
  const MailKontakt({
    required this.name,
    required this.email,
    this.kategorie = '',
    this.quelle = '',
    this.eigen = false,
    this.id,
    this.notiz = '',
  });

  final String name;
  final String email;

  /// Kennung wie `arzt`, `behoerde`, `eigen` — danach wird gefiltert.
  final String kategorie;

  /// Tabelle, aus der der Eintrag stammt. Nur zur Anzeige im Detail.
  final String quelle;

  /// Selbst angelegt, also änderbar und löschbar.
  final bool eigen;

  final int? id;
  final String notiz;

  static MailKontakt? ausMap(Map<String, dynamic> m) {
    final email = '${m['email'] ?? ''}'.trim();
    final name = '${m['name'] ?? ''}'.trim();
    // Ohne Adresse ist der Eintrag im Empfängerfeld nichts, was man anklicken
    // könnte — und ein Name ohne Adresse sähe aus wie ein kaputter Knopf.
    if (email.isEmpty || name.isEmpty) return null;
    return MailKontakt(
      name: name,
      email: email,
      kategorie: '${m['kategorie'] ?? ''}',
      quelle: '${m['quelle'] ?? ''}',
      eigen: m['eigen'] == true,
      id: m['id'] is num ? (m['id'] as num).toInt() : int.tryParse('${m['id']}'),
      notiz: '${m['notiz'] ?? ''}',
    );
  }
}

/// Was der Server geschickt hat, in lesbarer Form.
typedef MailKontakteAntwort = ({
  int gesamt,
  List<MailKontakt> kontakte,
  Map<String, int> kategorien,
});

/// Liest die Antwort von `api/mail/kontakte.php`.
///
/// ⚠️ `kategorien` kommt als Objekt — **außer** wenn es leer ist. PHP kennt nur
/// einen Array-Typ: ein leeres Array wird zu `[]`, also zu einer JSON-Liste,
/// und `as Map?` wirft darauf nicht `null`, sondern eine Ausnahme. Im
/// Release-Build ist das Ergebnis eine graue Fläche ohne jede Meldung. Genau so
/// ist der Speedtest-Bildschirm am 05.08.2026 in Produktion ausgefallen; hier
/// wird der Fall deshalb gelesen, nicht angenommen.
///
/// ⚠️ Die Antwort ist **flach** — `jsonResponse` mischt die Daten in die
/// Wurzel, es gibt kein `data`-Fach zum Auspacken.
MailKontakteAntwort mailKontakteAusAntwort(Map<String, dynamic> antwort) {
  final rohListe = antwort['kontakte'];
  final kontakte = rohListe is List
      ? rohListe
          .whereType<Map>()
          .map((e) => MailKontakt.ausMap(Map<String, dynamic>.from(e)))
          .whereType<MailKontakt>()
          .toList()
      : <MailKontakt>[];

  final rohKat = antwort['kategorien'];
  final kategorien = <String, int>{};
  if (rohKat is Map) {
    rohKat.forEach((k, v) {
      final zahl = v is num ? v.toInt() : int.tryParse('$v');
      if (zahl != null) kategorien['$k'] = zahl;
    });
  }

  final gesamt = antwort['gesamt'];
  return (
    gesamt: gesamt is num ? gesamt.toInt() : kontakte.length,
    kontakte: kontakte,
    kategorien: kategorien,
  );
}

/// Kategorie als lesbares Wort.
///
/// ⚠️ Was hier nicht steht, wird **nicht** verschluckt, sondern durchgereicht:
/// eine neue Tabelle auf dem Server soll in der Liste auftauchen, auch wenn
/// niemand daran gedacht hat, sie hier einzutragen. Dieselbe Tabelle wie in
/// `SipgateService.kategorieName` — beide lesen dieselben Kennungen.
String mailKategorieName(String? kennung) {
  return switch ((kennung ?? '').trim()) {
    'eigen' => 'Eigene Kontakte',
    'mitglied' => 'Mitglieder',
    'arzt' => 'Ärzte',
    'klinik' => 'Kliniken',
    'apotheke' => 'Apotheken',
    'sanitaetshaus' => 'Sanitätshäuser',
    'pflege' => 'Pflege',
    'kasse' => 'Kassen',
    'behoerde' => 'Behörden',
    'gericht' => 'Gerichte',
    'polizei' => 'Polizei',
    'rettung' => 'Rettungsdienst',
    'bank' => 'Banken',
    'versicherung' => 'Versicherungen',
    'vermieter' => 'Vermieter',
    'arbeitgeber' => 'Arbeitgeber',
    'bildung' => 'Bildung',
    'dienstleister' => 'Dienstleister',
    'verein' => 'Verein',
    'sonstige' => 'Sonstige',
    '' => 'Sonstige',
    final andere => andere,
  };
}

/// Zerlegt ein Empfängerfeld in einzelne Adressen.
///
/// Das Feld trennt mit Komma — dieselbe Regel, nach der der Hinweis unter dem
/// Feld („Mehrere Adressen mit Komma trennen") und die Prüfung vor dem Senden
/// arbeiten. Leere Stücke fallen weg, damit ein abschließendes Komma keine
/// leere Adresse ergibt.
List<String> mailAdressenAufteilen(String feld) => feld
    .split(',')
    .map((e) => e.trim())
    .where((e) => e.isNotEmpty)
    .toList();

/// Hängt ausgewählte Adressen an ein Empfängerfeld an.
///
/// ⚠️ **Anhängen, nicht ersetzen.** Eine E-Mail hat oft mehrere Empfänger, und
/// wer die Hälfte schon getippt hat, verliert sie sonst mit einem Griff ins
/// Adressbuch — ohne Warnung und ohne Weg zurück.
///
/// ⚠️ Doppelte werden **ohne Rücksicht auf Groß- und Kleinschreibung** erkannt.
/// Der lokale Teil einer Adresse ist zwar streng genommen unterscheidbar, aber
/// kein Postfach dieser Welt nutzt das — `Info@amt.de` und `info@amt.de` zweimal
/// anzuschreiben ist immer ein Versehen. Behalten wird die Schreibweise, die
/// schon im Feld steht.
String mailAdressenAnhaengen(String vorhanden, Iterable<String> neue) {
  final liste = mailAdressenAufteilen(vorhanden);
  final bekannt = liste.map((e) => e.toLowerCase()).toSet();

  for (final roh in neue) {
    final adresse = roh.trim();
    if (adresse.isEmpty) continue;
    if (!bekannt.add(adresse.toLowerCase())) continue;
    liste.add(adresse);
  }
  return liste.join(', ');
}
