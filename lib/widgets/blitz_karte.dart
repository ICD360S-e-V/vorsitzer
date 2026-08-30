import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/blitz_nachricht.dart';
import '../utils/app_farben.dart';
import '../utils/auto_korrektur.dart';
import 'wort_vorschlaege.dart';

/// Die Karte selbst — Absender, was er geschrieben hat, und ein Feld zum
/// Antworten. Wird an zwei Stellen gezeigt und ist deshalb bewusst dumm:
/// sie kennt weder ChatService noch ApiService, sondern meldet nur, was der
/// Benutzer getan hat.
///
/// - Linux: im eigenen Fenster mitten auf dem Bildschirm ([BlitzFensterApp]).
/// - Android (Tablet): auf dem Vollbild-Schirm ([BlitzVollbildScreen]).
class BlitzKarte extends StatefulWidget {
  final BlitzNachricht nachricht;

  /// Gibt `null` zurück, wenn es geklappt hat, sonst den Fehlertext.
  ///
  /// ⚠️ Absichtlich kein `bool`: ein fehlgeschlagenes Senden, das nur den
  /// Knopf zurückspringen lässt, ist von „ich habe danebengetippt" nicht zu
  /// unterscheiden. Dieselbe Lehre wie bei den Chat-Reaktionen.
  final Future<String?> Function(String text) onSenden;

  final VoidCallback onSchliessen;
  final VoidCallback? onImChatOeffnen;

  /// Vollbild (Android) bekommt grössere Schrift und mehr Luft als die
  /// kleine Karte am Rechner.
  final bool gross;

  /// Wie viele weitere Absender warten noch.
  ///
  /// ⚠️ Der Zähler ist die Antwort darauf, dass bei zwei gleichzeitigen
  /// Absendern der zweite unsichtbar blieb. Die Karte wird bewusst NICHT
  /// unter den Fingern umgeschaltet — sonst ginge eine halb geschriebene
  /// Antwort an die falsche Person —, aber verschweigen darf sie den
  /// Wartenden auch nicht.
  final int wartend;

  const BlitzKarte({
    super.key,
    required this.nachricht,
    required this.onSenden,
    required this.onSchliessen,
    this.onImChatOeffnen,
    this.gross = false,
    this.wartend = 0,
  });

  @override
  State<BlitzKarte> createState() => _BlitzKarteState();
}

class _BlitzKarteState extends State<BlitzKarte> {
  final _eingabe = TextEditingController();
  final _eingabeFokus = FocusNode();
  bool _sendet = false;
  String? _fehler;

  @override
  void dispose() {
    _eingabe.dispose();
    _eingabeFokus.dispose();
    super.dispose();
  }

  Future<void> _senden() async {
    // ⚠️ Auch hier aufräumen, mit derselben Funktion wie im Chat-Schreibfeld.
    // Dem letzten Wort folgt kein Trennzeichen mehr, es liefe sonst als
    // einziges ungeprüft raus — und im Blitz ist die Nachricht oft nur ein
    // Wort lang, also GENAU dieses.
    final aufgeraeumt = autoKorrigiert(_eingabe.text);
    if (aufgeraeumt != _eingabe.text) {
      _eingabe.value = TextEditingValue(
        text: aufgeraeumt,
        selection: TextSelection.collapsed(offset: aufgeraeumt.length),
      );
    }
    final text = _eingabe.text.trim();
    if (text.isEmpty || _sendet) return;
    setState(() {
      _sendet = true;
      _fehler = null;
    });
    final fehler = await widget.onSenden(text);
    if (!mounted) return;
    if (fehler == null) {
      // ⚠️ `_sendet` MUSS auch im Erfolgsfall zurück. Das Blitz-Fenster wird
      // nie geschlossen, nur versteckt — dieser State lebt weiter. Blieb der
      // Schalter stehen, zeigte die Karte bei der nächsten Nachricht für immer
      // den Wartekreis statt des Sendeknopfes, und nichts liesse sich mehr
      // abschicken. Gefunden hat das ein Test, der an genau diesem Kreis
      // haengen blieb (pumpAndSettle), nicht das Auge.
      setState(() => _sendet = false);
      _eingabe.clear();
      widget.onSchliessen();
      return;
    }
    setState(() {
      _sendet = false;
      _fehler = fehler;
    });
  }

  /// Eingabe = senden, Umschalt+Eingabe = neue Zeile, Esc = weglegen.
  ///
  /// ⚠️ Über [Focus.onKeyEvent] und nicht über `onSubmitted`: das Feld ist
  /// mehrzeilig, und dort löst `onSubmitted` gar nicht aus — die Antwort
  /// liesse sich per Tastatur nie abschicken.
  KeyEventResult _taste(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.escape) {
      widget.onSchliessen();
      return KeyEventResult.handled;
    }
    final istEingabe = e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (istEingabe && !HardwareKeyboard.instance.isShiftPressed) {
      _senden();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.nachricht;
    final gross = widget.gross;
    return Container(
      decoration: BoxDecoration(
        color: F.flaeche,
        borderRadius: BorderRadius.circular(gross ? 0 : 12),
        border: gross ? null : Border.all(color: F.rand),
        boxShadow: gross
            ? null
            : const [BoxShadow(color: Color(0x2E000000), blurRadius: 14, offset: Offset(0, 4))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _kopf(n, gross),
          // ⚠️ Am Rechner OHNE eigenen Scroller, und das ist der Kern der
          // Grössenlogik: das Blitz-Fenster richtet sich nach der natürlichen
          // Höhe dieser Karte. Ein `SingleChildScrollView` in einem begrenzten
          // Rahmen füllt diesen Rahmen aus, statt sich auf den Inhalt zu
          // ziehen — gemessen: die Karte meldete 301 px für eine einzige
          // Zeile, das Fenster wurde entsprechend zu hoch und darunter klaffte
          // eine Lücke. Ohne Scroller ist die Höhe schlicht die des Textes;
          // die fünf Zeilen aus [BlitzNachricht.ergaenztUm] sind der Deckel,
          // und wird es doch zu hoch, fängt es der Scroller des Fensters.
          //
          // Im Vollbild (Android) ist es umgekehrt richtig: dort gibt die
          // Fläche die Höhe vor, und der Text muss darin scrollen können.
          if (gross) Flexible(child: _verlauf(n, gross)) else _verlauf(n, gross),
          if (_fehler != null) _fehlerZeile(gross),
          _fuss(gross),
        ],
      ),
    );
  }

  Widget _verlauf(BlitzNachricht n, bool gross) {
    final inhalt = Padding(
        padding: EdgeInsets.fromLTRB(gross ? 24 : 11, 2, gross ? 24 : 11, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final z in n.zeilen)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  z,
                  style: TextStyle(
                    fontSize: gross ? 19 : 13,
                    height: 1.3,
                    color: F.textStark,
                  ),
                ),
              ),
          ],
        ));
    return gross ? SingleChildScrollView(child: inhalt) : inhalt;
  }

  Widget _kopf(BlitzNachricht n, bool gross) {
    final farbe = _farbeFuer(n.absender);
    return Padding(
      padding: EdgeInsets.fromLTRB(gross ? 24 : 11, gross ? 20 : 8, gross ? 12 : 4, 3),
      child: Row(
        children: [
          CircleAvatar(
            radius: gross ? 22 : 12,
            backgroundColor: farbe,
            child: Text(
              _initiale(n.absender),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: gross ? 18 : 11.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  n.absender,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: gross ? 20 : 13,
                    color: F.textStark,
                  ),
                ),
                Row(
                  children: [
                    if (n.kanal == 'sms') ...[
                      Icon(Icons.sms_outlined, size: gross ? 15 : 11, color: F.textLeise),
                      const SizedBox(width: 4),
                      Text('SMS · ',
                          style: TextStyle(fontSize: gross ? 13 : 10, color: F.textLeise)),
                    ],
                    Text(
                      _uhrzeit(n.zeit),
                      style: TextStyle(fontSize: gross ? 13 : 10, color: F.textLeise),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (widget.wartend > 0) _warteMarke(gross),
          IconButton(
            tooltip: 'Weglegen (Esc)',
            icon: Icon(Icons.close, size: gross ? 26 : 16, color: F.textSchwach),
            onPressed: widget.onSchliessen,
          ),
        ],
      ),
    );
  }

  /// „noch 1" — wer nach dieser Karte an der Reihe ist.
  Widget _warteMarke(bool gross) => Container(
        padding: EdgeInsets.symmetric(horizontal: gross ? 10 : 7, vertical: gross ? 5 : 3),
        decoration: BoxDecoration(
          color: F.flaecheBetont,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          'noch ${widget.wartend}',
          style: TextStyle(
            fontSize: gross ? 13 : 10.5,
            fontWeight: FontWeight.w600,
            color: F.textSchwach,
          ),
        ),
      );

  Widget _fehlerZeile(bool gross) => Container(
        width: double.infinity,
        color: const Color(0x22D32F2F),
        padding: EdgeInsets.symmetric(horizontal: gross ? 24 : 14, vertical: 7),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 16, color: Color(0xFFD32F2F)),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                _fehler!,
                style: TextStyle(fontSize: gross ? 14 : 12, color: F.textStark),
              ),
            ),
          ],
        ),
      );

  Widget _fuss(bool gross) {
    return Padding(
      padding: EdgeInsets.fromLTRB(gross ? 24 : 8, 2, gross ? 24 : 8, gross ? 24 : 8),
      child: WortVorschlaege(
        controller: _eingabe,
        bauen: (_) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (widget.onImChatOeffnen != null)
            IconButton(
              tooltip: 'Im Chat öffnen',
              icon: Icon(Icons.open_in_new, size: gross ? 24 : 17, color: F.textSchwach),
              onPressed: widget.onImChatOeffnen,
            ),
          Expanded(
            child: Focus(
              onKeyEvent: _taste,
              child: TextField(
                controller: _eingabe,
                focusNode: _eingabeFokus,
                // Der ganze Sinn des Blitzes: sofort schreiben können.
                autofocus: true,
                enabled: !_sendet,
                // ⚠️ EINZEILIG, und das ist der ganze Punkt.
                //
                // Hier stand `maxLines: 2` mit `TextInputAction.newline` —
                // also die ausdrückliche Ansage an das System „Eingabetaste
                // bedeutet neue Zeile". [_taste] wollte gleichzeitig senden,
                // aber gegen den Vertrag des Feldes kommt der Tastenhaken
                // nicht an: gemeldet aus dem Betrieb „wenn ich Enter drücke,
                // kommt eine neue Zeile, statt dass die Nachricht rausgeht".
                //
                // Bei einem einzeiligen Feld KANN die Eingabetaste keine Zeile
                // einfügen; sie löst die Aktion aus. Damit gibt es nur noch
                // ein mögliches Verhalten statt zweier, die sich streiten.
                //
                // Preis: keine mehrzeilige Antwort aus der Karte. Die Karte
                // ist für die schnelle Antwort da — für einen langen Text
                // führt der Knopf daneben in den vollen Chat.
                minLines: 1,
                maxLines: 1,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _senden(),
                style: TextStyle(fontSize: gross ? 17 : 13, color: F.textStark),
                decoration: InputDecoration(
                  hintText: 'Antwort schreiben…',
                  hintStyle: TextStyle(color: F.textLeise, fontSize: gross ? 17 : 13),
                  filled: true,
                  fillColor: F.flaecheGedaempft,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: gross ? 12 : 10, vertical: gross ? 14 : 7),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(gross ? 12 : 8),
                    borderSide: BorderSide(color: F.rand),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(gross ? 12 : 8),
                    borderSide: BorderSide(color: F.rand),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          _sendet
              ? SizedBox(
                  width: gross ? 44 : 32,
                  height: gross ? 44 : 32,
                  child: const Center(
                    child: SizedBox(
                        width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                )
              : IconButton(
                  tooltip: 'Senden (Eingabe)',
                  icon: Icon(Icons.send, size: gross ? 26 : 18),
                  color: const Color(0xFF4a90d9),
                  onPressed: _senden,
                ),
        ],
        ),
      ),
    );
  }

  static String _initiale(String name) {
    final t = name.trim();
    return t.isEmpty ? '?' : String.fromCharCode(t.runes.first).toUpperCase();
  }

  static String _uhrzeit(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  /// Feste Farbe je Name, damit derselbe Absender immer gleich aussieht.
  static Color _farbeFuer(String name) {
    const palette = [
      Color(0xFF4a90d9), Color(0xFF7E57C2), Color(0xFF00897B),
      Color(0xFFEF6C00), Color(0xFFC2185B), Color(0xFF546E7A),
    ];
    var h = 0;
    for (final c in name.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    return palette[h % palette.length];
  }
}
