import 'dart:convert';

/// Name des Kanals zwischen Hauptfenster und Schnellstart-Leiste.
///
/// ⚠️ EIGENER NAME, NICHT [kBlitzKanal] MITBENUTZEN. Bidirektional heisst
/// beim Paket: genau ZWEI Engines dürfen sich auf **einem** Kanal
/// registrieren. Die Grenze gilt je Kanal, nicht je Anwendung — nachgelesen
/// in `desktop_multi_window/src/window_channel.dart`. Deshalb dürfen Blitz
/// und Leiste nebeneinander laufen, aber nur auf getrennten Kanälen; wer
/// hier `kBlitzKanal` einträgt, findet ihn besetzt und die Leiste bleibt
/// stumm — ohne Fehler, weil das Registrieren erst beim dritten Teilnehmer
/// scheitert und der Rückfall „keine Daten" heisst.
const String kDockKanal = 'icd360sev/dock';

/// Argument, an dem `main()` das Leisten-Fenster erkennt. Präfix, kein
/// exakter Vergleich — dahinter reist der Startzustand mit (Dunkelmodus,
/// Zähler), damit die Leiste beim ersten Bild schon richtig aussieht statt
/// kurz hell aufzublitzen und dann umzuspringen.
const String kDockFensterArgument = 'dock';

/// Die drei Bereiche, die die Leiste zeigt.
///
/// ⚠️ Diese Schlüssel stehen an DREI Stellen: hier, im Datenlieferanten des
/// Dashboards ([DockFensterSteuerung.datenGeber]) und in der Sprungtabelle
/// von `onOeffnen`. Ein Tippfehler ist nirgends ein Fehler — die Liste
/// bliebe leer und der Sprung führte ins Nichts. `test/dock_bereiche_test.dart`
/// hält die drei Stellen zusammen.
class DockBereich {
  static const String mitglieder = 'mitglieder';
  static const String termine = 'termine';
  static const String chat = 'chat';

  /// Reihenfolge der Symbole in der Leiste, von oben nach unten.
  static const List<String> alle = [mitglieder, termine, chat];
}

/// Methodennamen auf [kDockKanal].
class DockRuf {
  /// Leiste → Hauptfenster: gib mir die Liste für diesen Bereich.
  /// Argumente: `{bereich}`. Antwort: `{ok, eintraege, fehler}`.
  static const String daten = 'dock.daten';

  /// Leiste → Hauptfenster: hol dich nach vorn und geh in diesen Bereich.
  /// Argumente: `{bereich, id}` — `id` ist optional und meint die Zeile,
  /// auf die getippt wurde (Unterhaltung, Termin, Mitglied).
  static const String oeffnen = 'dock.oeffnen';

  /// Hauptfenster → Leiste: neue Abzeichen und/oder neues Farbschema.
  /// Argumente: JSON `{zaehler: {bereich: n}, dunkel: bool}`.
  static const String stand = 'dock.stand';
}

/// Eine Zeile im ausgeklappten Panel der Leiste.
///
/// ⚠️ Bewusst ein Allerweltssatz aus vier Feldern und nicht je Bereich ein
/// eigenes Modell. Das Leisten-Fenster hat eine EIGENE Engine: dort gibt es
/// weder `User` noch `Termin` noch den angemeldeten Benutzer, und ein
/// `ApiService()` wäre dort eine zweite, nicht angemeldete Instanz. Alles,
/// was die Leiste weiss, ist durch [kDockKanal] hereingereicht worden —
/// also muss es sich in JSON fassen lassen, und zwar für alle drei Bereiche
/// gleich.
class DockEintrag {
  /// Fachliche Kennung der Zeile (Unterhaltung, Termin, Mitglied). Wird beim
  /// Antippen an [DockRuf.oeffnen] weitergereicht. `null` = die Zeile ist
  /// nur Auskunft und führt nirgendwohin.
  final int? id;

  /// Erste Zeile, fett. Name des Mitglieds, Titel des Termins.
  final String titel;

  /// Zweite Zeile, klein. Ort und Uhrzeit, Mitgliedsnummer, letzte Nachricht.
  final String unterzeile;

  /// Rechts aussen, klein. Uhrzeit, Status, Rolle.
  final String zusatz;

  /// Zahl auf dem Abzeichen rechts (ungelesene Nachrichten). 0 = keins.
  final int abzeichen;

  /// Hervorgehoben darstellen — heute fälliger Termin, Notfall, ungelesen.
  final bool betont;

  const DockEintrag({
    this.id,
    required this.titel,
    this.unterzeile = '',
    this.zusatz = '',
    this.abzeichen = 0,
    this.betont = false,
  });

  Map<String, dynamic> toJson() => {
        if (id != null) 'id': id,
        'titel': titel,
        if (unterzeile.isNotEmpty) 'unterzeile': unterzeile,
        if (zusatz.isNotEmpty) 'zusatz': zusatz,
        if (abzeichen > 0) 'abzeichen': abzeichen,
        if (betont) 'betont': true,
      };

  /// ⚠️ Jedes Feld einzeln abgesichert. Die Gegenseite ist zwar unser
  /// eigener Code, aber sie ist eine ANDERE Engine mit eigenem Lebenslauf:
  /// nach einem Update läuft dort für einen Augenblick noch die alte
  /// Fassung. Eine fehlende Unterzeile darf die ganze Liste nicht kippen.
  factory DockEintrag.fromJson(Map<String, dynamic> j) => DockEintrag(
        id: _alsInt(j['id']),
        titel: '${j['titel'] ?? ''}',
        unterzeile: '${j['unterzeile'] ?? ''}',
        zusatz: '${j['zusatz'] ?? ''}',
        abzeichen: _alsInt(j['abzeichen']) ?? 0,
        betont: j['betont'] == true,
      );

  static int? _alsInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));

  /// Liste aus einer JSON-Nutzlast lesen. Gibt bei Unsinn eine leere Liste
  /// zurück, nie `null` — der Aufrufer soll „nichts da" anzeigen und nicht
  /// abstürzen.
  static List<DockEintrag> listeAusJson(dynamic roh) {
    if (roh is! List) return const [];
    final raus = <DockEintrag>[];
    for (final e in roh) {
      if (e is Map) {
        raus.add(DockEintrag.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return raus;
  }

  /// Nutzlast des Fensterarguments lesen (der Teil hinter dem Doppelpunkt).
  ///
  /// ⚠️ Schluckt Fehler und liefert eine leere Karte. Kommt die Leiste mit
  /// kaputtem Argument hoch, soll sie trotzdem erscheinen — die Zähler holt
  /// sie sich beim nächsten [DockRuf.stand] ohnehin neu.
  static Map<String, dynamic> nutzlastLesen(String argument) {
    final trenn = argument.indexOf(':');
    if (trenn < 0) return const {};
    try {
      final j = jsonDecode(argument.substring(trenn + 1));
      return j is Map ? Map<String, dynamic>.from(j) : const {};
    } catch (_) {
      return const {};
    }
  }
}
