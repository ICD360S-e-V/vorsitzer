import 'dart:convert';

/// Eine Nachricht, die als „Blitz" mitten auf den Bildschirm gelegt wird —
/// die Nachricht kommt zum Vorsitzenden, nicht der Vorsitzende zur Nachricht.
///
/// ⚠️ DIESES OBJEKT REIST ZWISCHEN ZWEI FLUTTER-ENGINES.
/// Unter Linux läuft die Blitz-Karte in einem eigenen Fenster mit eigener
/// Engine und eigenem Isolate. Zwischen Isolates gibt es keine gemeinsamen
/// Objekte, nur Nachrichten — deshalb muss alles, was die Karte anzeigt, hier
/// als JSON durchpassen. Ein Feld, das man „später mal" aus einem Singleton
/// nachlädt, ist im Blitz-Fenster schlicht nicht vorhanden.
class BlitzNachricht {
  final int conversationId;
  final String absender;

  /// Die Zeilen der Unterhaltung, älteste zuerst. Mehrere, weil ein zweiter
  /// Satz desselben Absenders die Karte ergänzt statt sie zu ersetzen — wer
  /// „Guten Tag" und „ich habe eine Frage" schnell hintereinander schickt,
  /// soll nicht den ersten Satz verlieren.
  final List<String> zeilen;

  /// 'app' oder 'sms'. Muss mit, weil die Antwort auf denselben Weg zurück
  /// gehört: eine SMS-Frage per App-Chat zu beantworten heisst, dass das
  /// Mitglied die Antwort nie sieht.
  final String kanal;

  final DateTime zeit;

  const BlitzNachricht({
    required this.conversationId,
    required this.absender,
    required this.zeilen,
    required this.zeit,
    this.kanal = 'app',
  });

  BlitzNachricht ergaenztUm(String zeile, DateTime wann) => BlitzNachricht(
        conversationId: conversationId,
        absender: absender,
        // Deckel bei 5: die Karte ist klein, und die ältesten Zeilen hat der
        // Leser bei einem Schwall ohnehin schon in der Benachrichtigung
        // gesehen. Ohne Deckel wächst das Fenster über den Bildschirm hinaus.
        zeilen: [...zeilen, zeile].length > 5
            ? [...zeilen, zeile].sublist([...zeilen, zeile].length - 5)
            : [...zeilen, zeile],
        zeit: wann,
        kanal: kanal,
      );

  Map<String, dynamic> toJson() => {
        'conversation_id': conversationId,
        'absender': absender,
        'zeilen': zeilen,
        'kanal': kanal,
        'zeit': zeit.toIso8601String(),
      };

  factory BlitzNachricht.fromJson(Map<String, dynamic> j) => BlitzNachricht(
        conversationId: (j['conversation_id'] as num?)?.toInt() ?? 0,
        absender: (j['absender'] as String?)?.trim().isNotEmpty == true
            ? j['absender'] as String
            // Ein leerer Name ergäbe eine Karte mit Anrede-Loch. Lieber
            // ehrlich „Unbekannt" als eine Karte, die kaputt aussieht.
            : 'Unbekannt',
        zeilen: (j['zeilen'] as List?)?.map((e) => '$e').toList() ?? const [],
        kanal: j['kanal'] as String? ?? 'app',
        zeit: DateTime.tryParse('${j['zeit']}') ?? DateTime.now(),
      );

  String kodiert() => jsonEncode(toJson());

  static BlitzNachricht? entschluesselt(String? roh) {
    if (roh == null || roh.isEmpty) return null;
    try {
      final j = jsonDecode(roh);
      if (j is! Map) return null;
      return BlitzNachricht.fromJson(Map<String, dynamic>.from(j));
    } catch (_) {
      return null;
    }
  }
}

/// Name des Kanals zwischen Hauptfenster und Blitz-Fenster.
///
/// ⚠️ Bidirektional heisst beim Paket: genau ZWEI Engines dürfen sich
/// registrieren, und nur die beiden erreichen einander. Das passt hier genau
/// (Hauptfenster + ein Blitz-Fenster) und ist zugleich der Grund, warum es
/// immer nur EIN Blitz-Fenster geben darf.
const String kBlitzKanal = 'icd360sev/blitz';

/// Argument, an dem `main()` das Blitz-Fenster erkennt. Muss ein Präfix sein
/// und kein exakter Vergleich — hinter dem Doppelpunkt reist die erste
/// Nachricht mit, damit das Fenster schon beim ersten Bild etwas anzeigt
/// statt kurz leer aufzublitzen.
const String kBlitzFensterArgument = 'blitz';

/// Methodennamen auf [kBlitzKanal].
class BlitzRuf {
  /// Hauptfenster → Blitz-Fenster: zeig diese Nachricht (JSON).
  static const String zeigen = 'blitz.zeigen';

  /// Blitz-Fenster → Hauptfenster: Antwort abschicken.
  /// Argumente: {conversation_id, text, kanal}. Antwort: {ok, fehler}.
  static const String senden = 'blitz.senden';

  /// Blitz-Fenster → Hauptfenster: Karte weggelegt, Fenster verstecken.
  static const String schliessen = 'blitz.schliessen';

  /// Blitz-Fenster → Hauptfenster: „im Chat öffnen" gedrückt.
  static const String imChatOeffnen = 'blitz.im_chat';

  /// Blitz-Fenster → Hauptfenster: erledigt, gib mir die nächste wartende
  /// Nachricht (oder verstecke dich, wenn keine mehr da ist).
  static const String weiter = 'blitz.weiter';

}
