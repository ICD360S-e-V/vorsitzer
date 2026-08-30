/// Wortvervollständigung für das Schreibfeld — Vorschläge nach den ersten
/// Buchstaben, wie man es aus Arztpraxen kennt.
///
/// ⚠️ GESUCHT WIRD OHNE DIAKRITIKA, ANGEZEIGT WIRD MIT.
/// Das ist der eigentliche Nutzen und kein Nebeneffekt: im Rumänischen sind
/// die fehlenden Häkchen der häufigste Fehler überhaupt. Wer „multu" tippt,
/// bekommt „mulțumesc" vorgeschlagen — die Vervollständigung repariert die
/// Schreibung also nebenbei, ohne dass jemand eine Korrektur anstoßen muss.
///
/// ⚠️ Die Wortliste ist NACH HÄUFIGKEIT sortiert, nicht alphabetisch. Die
/// Reihenfolge IST die Information; wer sie sortiert, macht aus dem obersten
/// Vorschlag ein Wort, das niemand braucht.
library;

class WortIndex {
  /// Erste zwei Buchstaben (ohne Diakritika) → Wörter in Häufigkeitsfolge.
  final Map<String, List<String>> _faecher;

  /// Dieselben Wörter noch einmal als Menge — [kennt] wird bei JEDEM
  /// Tastendruck gefragt, und `List.contains` über ein Fach mit
  /// Zehntausenden Einträgen wäre dafür zu langsam. Die Zeichenketten sind
  /// dieselben Objekte, es kostet also nur den Aufbau der Menge.
  final Set<String> _alle;
  final int anzahl;

  const WortIndex._(this._faecher, this._alle, this.anzahl);

  /// Leerer Index — solange die Liste nicht geladen ist, gibt es einfach
  /// keine Vorschläge. Das Schreibfeld muss deswegen nie warten.
  static const WortIndex leer = WortIndex._({}, {}, 0);

  /// [woerter] muss bereits nach Häufigkeit absteigend sortiert sein.
  factory WortIndex.aufbauen(Iterable<String> woerter) {
    final faecher = <String, List<String>>{};
    final alle = <String>{};
    for (final w in woerter) {
      if (w.length < 2) continue;
      final schluessel = ohneDiakritika(w).substring(0, 2);
      (faecher[schluessel] ??= <String>[]).add(w);
      alle.add(w);
    }
    return WortIndex._(faecher, alle, alle.length);
  }

  /// ă â → a · î → i · ș → s · ț → t, dazu Kleinschreibung.
  ///
  /// ⚠️ Auch die Cedille-Formen ş/ţ, weil manche Tastaturen sie liefern —
  /// sonst fände jemand, der mit der falschen Belegung tippt, gar nichts.
  ///
  /// ⚠️ UND DER BINDESTRICH FÄLLT WEG. Im Rumänischen hängen die kurzen
  /// Wörter mit Bindestrich zusammen — „mi-aș", „s-a", „într-o", „nu-i" —
  /// und beim schnellen Tippen bleibt er weg. Wer 》mias《 schreibt, meint
  /// 》mi-aș《; ohne diese Zeile fände er dazu nichts, weil die Liste den
  /// Strich führt und die Eingabe nicht.
  static String ohneDiakritika(String s) {
    final b = StringBuffer();
    for (final z in s.toLowerCase().split('')) {
      switch (z) {
        case 'ă':
        case 'â':
          b.write('a');
        case 'î':
          b.write('i');
        case 'ș':
        case 'ş':
          b.write('s');
        case 'ț':
        case 'ţ':
          b.write('t');
        case '-':
          break;
        default:
          b.write(z);
      }
    }
    return b.toString();
  }

  /// Vorschläge zu einem angefangenen Wort, beste zuerst.
  ///
  /// Unter [mindestZeichen] Buchstaben kommt nichts — bei einem oder zwei
  /// Zeichen wäre jeder Vorschlag geraten und stünde nur im Weg.
  List<String> vorschlaege(
    String angefangen, {
    int hoechstens = 5,
    int mindestZeichen = 3,
  }) {
    if (angefangen.length < mindestZeichen || angefangen.length < 2) {
      return const [];
    }
    final gesucht = ohneDiakritika(angefangen);
    final fach = _faecher[gesucht.substring(0, 2)];
    if (fach == null) return const [];

    final treffer = <String>[];
    String? gleicheLaenge;
    for (final wort in fach) {
      // Was schon zeichengleich dasteht, ist kein Vorschlag. Die Fassung
      // OHNE Häkchen bleibt dagegen einer — sie ist ja gerade der Gewinn.
      if (wort == angefangen) continue;
      if (!ohneDiakritika(wort).startsWith(gesucht)) continue;
      // ⚠️ Ein Wort gleicher Länge unterscheidet sich NUR in den Häkchen —
      // es ist also dasselbe Wort, richtig geschrieben, und nicht bloß eines,
      // das genauso anfängt. An echten Nachrichten aufgefallen: „numar" wurde
      // „numărul" statt „număr", weil die längere Form häufiger ist.
      gleicheLaenge ??= wort.length == angefangen.length ? wort : null;
      treffer.add(wort);
      // Das Fach ist nach Häufigkeit sortiert, also sind die ersten Treffer
      // die besten — hier abzubrechen kostet nichts und spart bei „de" oder
      // „co" den Durchlauf durch Zehntausende Einträge.
      if (treffer.length >= hoechstens) break;
    }
    if (gleicheLaenge != null && treffer.first != gleicheLaenge) {
      treffer.remove(gleicheLaenge);
      treffer.insert(0, gleicheLaenge);
    }
    return treffer;
  }

  /// Steht das Wort so, wie es dasteht, in der Liste?
  ///
  /// ⚠️ Zeichengleich, also MIT Häkchen. Genau darauf beruht die Regel für
  /// die Eingabetaste: „multumesc" ist kein Wort der Liste (nur „mulțumesc"
  /// ist eines), deshalb wird dort vervollständigt statt gesendet.
  /// ⚠️ Auch klein geschrieben nachschlagen. Die Liste führt „acceptă" und
  /// „bună", nicht „Acceptă" und „Bună" — am Satzanfang gilt sonst ein völlig
  /// richtiges Wort als unbekannt und wird „verbessert". An echten
  /// Nachrichten aufgefallen: aus „Acceptă-l cu bucurie." wurde „Accepta-l".
  bool kennt(String wort) =>
      wort.length >= 2 &&
      (_alle.contains(wort) || _alle.contains(wort.toLowerCase()));

  /// Überträgt die Groß-/Kleinschreibung des Getippten auf den Vorschlag.
  /// Wer „Multu" schreibt, will „Mulțumesc", nicht „mulțumesc".
  static String schreibungUebernehmen(String eingabe, String wort) {
    if (eingabe.isEmpty || wort.isEmpty) return wort;
    final ersterGross = eingabe[0] == eingabe[0].toUpperCase() &&
        eingabe[0] != eingabe[0].toLowerCase();
    if (!ersterGross) return wort;
    // Durchgehend groß nur ab zwei Zeichen — ein einzelnes „M" heißt noch
    // nicht, dass jemand schreien will.
    if (eingabe.length >= 2 && eingabe == eingabe.toUpperCase()) {
      return wort.toUpperCase();
    }
    return wort[0].toUpperCase() + wort.substring(1);
  }
}

/// Das angefangene Wort links vom Textcursor.
///
/// ⚠️ Nur wenn der Cursor am Wortende steht. Wer mitten in einem fertigen
/// Wort etwas ausbessert, will keine Vorschläge — die würden dann den Rest
/// des Wortes verschlucken.
class AngefangenesWort {
  final String text;
  final int von;
  final int bis;

  const AngefangenesWort(this.text, this.von, this.bis);

  /// ⚠️ Der Bindestrich ist KEIN Trenner. „mi-aș" ist ein Wort, kein
  /// Wortpaar — würde er trennen, bliebe beim Tippen nur noch „aș"
  /// übrig und die ganze Form wäre nicht mehr zu finden. Gedankenstrich
  /// und Halbgeviertstrich trennen weiterhin.
  static const _trenner = ' \t\n\r.,;:!?()[]{}"\'„“”«»/\\–—… ';

  /// Steht das Wort am Satzanfang?
  ///
  /// ⚠️ Daran hängt der Schutz für Eigennamen. Gemessen an dem, was in
  /// diesem Verein wirklich getippt wird, würde die Leertaste sonst
  /// „Termin" zu „terminat", „Radu" zu „radule" und „Padurean" zu
  /// „pădurean" machen — deutsche Fachwörter und die Namen von Mitgliedern,
  /// beides täglich im Text. Alle fingen mit einem Großbuchstaben an.
  ///
  /// Am Satzanfang wird trotzdem vervollständigt: dort ist der große
  /// Buchstabe nur Rechtschreibung und sagt nichts über das Wort aus —
  /// „Multumesc" soll weiterhin zu „Mulțumesc" werden.
  static bool istSatzanfang(String text, int von) {
    var i = von - 1;
    while (i >= 0 && (text[i] == ' ' || text[i] == '\t')) {
      i--;
    }
    if (i < 0) return true;
    return '.!?\n'.contains(text[i]);
  }

  /// Fängt das Wort mit einem Großbuchstaben an?
  static bool grossGeschrieben(String wort) =>
      wort.isNotEmpty &&
      wort[0] == wort[0].toUpperCase() &&
      wort[0] != wort[0].toLowerCase();

  static AngefangenesWort? ausEingabe(String text, int cursor) {
    if (cursor < 0 || cursor > text.length) return null;
    // Rechts vom Cursor muss Schluss oder ein Trenner sein.
    if (cursor < text.length && !_trenner.contains(text[cursor])) return null;
    var von = cursor;
    while (von > 0 && !_trenner.contains(text[von - 1])) {
      von--;
    }
    if (von == cursor) return null;
    return AngefangenesWort(text.substring(von, cursor), von, cursor);
  }
}
