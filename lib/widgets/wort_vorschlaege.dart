import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;

import '../services/wortliste_service.dart';
import '../utils/app_farben.dart';
import '../utils/auto_korrektur.dart';
import '../utils/wort_vervollstaendigung.dart';

/// Zeigt über dem Schreibfeld Vorschläge zum angefangenen Wort und übernimmt
/// den obersten mit der LEERTASTE.
///
/// ⚠️ WARUM DIE LEERTASTE UND NICHT DIE EINGABETASTE.
/// Die Eingabetaste sendet in diesem Feld seit jeher die Nachricht. Gäbe man
/// ihr eine zweite Bedeutung, ginge irgendwann eine halbe Nachricht raus.
/// Die Leertaste steht ohnehin am Ende jedes Wortes — dort kostet die
/// Übernahme keinen zusätzlichen Anschlag. So bleibt die Eingabetaste
/// unangetastet: sie sendet, immer.
///
/// ⚠️ UND WARUM DAS OHNE ZWEI SICHERUNGEN NICHT GEHT.
/// Genau diese Taste ist der bekannteste Vorwurf gegen Autovervollständigung:
/// wer „add" tippt und ein Leerzeichen will, bekommt „address". Deshalb:
///
///   1. Ein Wort, das SELBST in der Liste steht, wird nie ersetzt.
///      „bine" bleibt „bine", auch wenn „binevoitor" danebensteht.
///   2. Ein großgeschriebenes Wort MITTEN IM SATZ wird nicht angefasst.
///      Gemessen an echtem Text wären sonst „Termin" zu „terminat", „Radu"
///      zu „radule" und „Padurean" zu „pădurean" geworden — Fachwörter und
///      Mitgliedernamen. Am Satzanfang wird weiter vervollständigt, dort
///      sagt der große Buchstabe nichts über das Wort aus.
///   3. Rücktaste unmittelbar danach nimmt die Ersetzung zurück — und das
///      zurückgeholte Wort wird danach in Ruhe gelassen, sonst ersetzte die
///      nächste Leertaste es sofort wieder.
///
/// Angetippt oder mit der Tabulatortaste wird IMMER übernommen; dort gibt es
/// keine zweite Bedeutung, die man kaputtmachen könnte.
///
/// ⚠️ Die Leertaste wird am TEXT erkannt, nicht am Tastendruck. Die
/// Bildschirmtastatur eines Telefons schickt für Buchstaben keine
/// verlässlichen Tastenereignisse — ein Tastenhaken funktionierte also nur am
/// Rechner, und ausgerechnet auf dem Telefon, wo man am langsamsten tippt,
/// gar nicht.
class WortVorschlaege extends StatefulWidget {
  final TextEditingController controller;

  /// Aus, solange niemand die Liste braucht (fremdsprachige Gespräche,
  /// Testfälle). Aus heißt: das Feld verhält sich exakt wie vorher.
  final bool aktiv;

  /// Bekommt die Funktion, die vor dem Senden noch einmal aufräumt. Der
  /// Sendeweg MUSS sie aufrufen, sonst geht das letzte Wort ungeprüft raus.
  final Widget Function(VoidCallback vorDemSenden) bauen;

  const WortVorschlaege({
    super.key,
    required this.controller,
    required this.bauen,
    this.aktiv = true,
  });

  @override
  State<WortVorschlaege> createState() => _WortVorschlaegeState();
}

class _WortVorschlaegeState extends State<WortVorschlaege> {
  /// Zeichen, nach denen ein Wort als fertig gilt.
  static const _abschluss = ' \n\t.,;:!?)]}»…';

  List<String> _vorschlaege = const [];
  AngefangenesWort? _wort;

  /// Textstand der letzten Runde — daran wird die Leertaste erkannt.
  String _letzterText = '';

  /// Die eben durch die Leertaste gemachte Ersetzung, für die Rücktaste.
  _Ersetzung? _rueckgaengig;

  /// Wörter, deren Ersetzung der Mensch schon einmal zurückgenommen hat.
  /// Ohne das setzte die nächste Leertaste sofort wieder dasselbe ein — und
  /// aus einer Hilfe würde ein Kampf.
  final Set<String> _inRuheLassen = {};

  @override
  void initState() {
    super.initState();
    _letzterText = widget.controller.text;
    widget.controller.addListener(_geaendert);
    if (widget.aktiv) {
      // Erst laden, wenn wirklich jemand schreibt — nicht beim Programmstart.
      WortlisteService.laden().then((_) {
        if (mounted) _geaendert();
      });
    }
  }

  @override
  void didUpdateWidget(WortVorschlaege alt) {
    super.didUpdateWidget(alt);
    if (alt.controller != widget.controller) {
      alt.controller.removeListener(_geaendert);
      widget.controller.addListener(_geaendert);
      _letzterText = widget.controller.text;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_geaendert);
    super.dispose();
  }

  void _geaendert() {
    if (!widget.aktiv || !mounted) return;
    final text = widget.controller.text;
    final vorher = _letzterText;

    // ⚠️ Jedes Schreiben in den Controller ruft diesen Hörer ERNEUT auf. Ohne
    // diesen Ausstieg löschte der zweite Durchlauf sofort das Zeitfenster der
    // Rücktaste — die Ersetzung wäre dann nicht mehr zurückzunehmen. Da alle
    // eigenen Schreibvorgänge [_letzterText] vorher mitziehen, ist der
    // Textstand hier gleich und es gibt nichts zu tun.
    if (text == vorher) {
      _neuRechnen();
      return;
    }
    _letzterText = text;

    if (_ruecknahmeVersucht(text, vorher)) return;
    if (_abschlussVersucht(text, vorher)) return;

    // Jede andere Änderung beendet das Zeitfenster der Rücktaste.
    _rueckgaengig = null;
    _neuRechnen();
  }

  /// Rücktaste unmittelbar nach einer Ersetzung: alles zurück auf das, was
  /// wirklich getippt wurde.
  bool _ruecknahmeVersucht(String text, String vorher) {
    final r = _rueckgaengig;
    if (r == null) return false;
    // Genau ein Zeichen weniger, und zwar das angehängte Leerzeichen.
    if (text.length != vorher.length - 1 || vorher != r.nachher) {
      return false;
    }
    _rueckgaengig = null;
    _inRuheLassen.add(r.original);
    final ganz = r.ganzerTextVorher;
    if (ganz != null) {
      // Häkchen-Korrektur: sie kann zwei Wörter berührt haben.
      _letzterText = ganz;
      widget.controller.value = TextEditingValue(
        text: ganz,
        selection: TextSelection.collapsed(offset: ganz.length),
      );
      _neuRechnen();
      return true;
    }
    final wieder = '${text.substring(0, r.von)}${r.original}'
        '${text.substring(r.von + r.eingesetzt.length)}';
    _letzterText = wieder;
    widget.controller.value = TextEditingValue(
      text: wieder,
      selection: TextSelection.collapsed(offset: r.von + r.original.length),
    );
    _neuRechnen();
    return true;
  }

  /// Wurde ein Wort gerade abgeschlossen — durch Leerzeichen ODER
  /// Satzzeichen?
  ///
  /// ⚠️ Anfangs nur das Leerzeichen. Damit blieb „va rog." unkorrigiert,
  /// weil dort ein Punkt steht und kein Leerzeichen — und Satzenden sind
  /// gerade die Stellen, an denen ein Wort besonders oft steht.
  bool _abschlussVersucht(String text, String vorher) {
    final wort = _wort;
    if (wort == null) return false;
    if (text.length != vorher.length + 1) return false;

    final cursor = widget.controller.selection.baseOffset;
    // Das neue Zeichen muss ein Leerzeichen genau hinter dem Wort sein.
    if (cursor != wort.bis + 1) return false;
    if (cursor > text.length || !_abschluss.contains(text[cursor - 1])) {
      return false;
    }
    if (text.substring(0, cursor - 1) != vorher.substring(0, cursor - 1)) {
      return false;
    }
    // Häkchen-Korrektur zuerst: sie greift GERADE dort, wo das Wort selbst
    // eines ist („sa", „ca", „va") — also vor Sicherung 1, die genau das
    // sonst abfängt. Was hier passiert, entscheidet der Nachbar, nicht die
    // Häufigkeit. Siehe [Diakritika].
    if (_haekchenGesetzt(text, wort, cursor)) return true;

    // Ohne Vorschlag bleibt noch der Vertipper: „dovument" ist der Anfang
    // von gar nichts, also kennt die Liste dazu nichts — gemeint ist aber
    // „document". Siehe [Tippfehler].
    if (_vorschlaege.isEmpty) {
      return _tippfehlerGesetzt(text, wort, cursor);
    }

    // Sicherung 1: ein richtiges Wort wird nicht angefasst.
    if (WortlisteService.index.kennt(wort.text)) return false;
    // Sicherung 2: einmal zurückgenommen heißt in Ruhe lassen.
    if (_inRuheLassen.contains(wort.text)) return false;
    // Sicherung 3: Eigennamen mitten im Satz bleiben, wie sie sind.
    if (AngefangenesWort.grossGeschrieben(wort.text) &&
        !AngefangenesWort.istSatzanfang(text, wort.von)) {
      return false;
    }

    final eingesetzt =
        WortIndex.schreibungUebernehmen(wort.text, _vorschlaege.first);
    final neu = '${text.substring(0, wort.von)}$eingesetzt '
        '${text.substring(wort.bis + 1)}';
    _rueckgaengig = _Ersetzung(
      von: wort.von,
      original: wort.text,
      eingesetzt: eingesetzt,
      nachher: neu,
    );
    _letzterText = neu;
    widget.controller.value = TextEditingValue(
      text: neu,
      selection:
          TextSelection.collapsed(offset: wort.von + eingesetzt.length + 1),
    );
    _neuRechnen();
    return true;
  }

  /// Ersetzt ein vertipptes Wort durch das gemeinte.
  bool _tippfehlerGesetzt(String text, AngefangenesWort wort, int cursor) {
    if (!_erlaubt(wort, text)) return false;
    final neu = WortlisteService.tippfehler.korrektur(wort.text);
    if (neu == null) return false;
    final ergebnis = text.replaceRange(wort.von, wort.bis, neu);
    _rueckgaengig = _Ersetzung(
      von: wort.von,
      original: wort.text,
      eingesetzt: neu,
      nachher: ergebnis,
      ganzerTextVorher: text,
    );
    _letzterText = ergebnis;
    widget.controller.value = TextEditingValue(
      text: ergebnis,
      selection: TextSelection.collapsed(
          offset: cursor + neu.length - wort.text.length),
    );
    _neuRechnen();
    return true;
  }

  /// Setzt die Häkchen im eben getippten Wort UND im Wort davor.
  ///
  /// ⚠️ Beide, und das ist keine Bequemlichkeit: eine Regel wie
  /// `va` + rechter Nachbar `rog` kann erst greifen, wenn „rog" dasteht —
  /// also erst beim Leerzeichen NACH „rog". Wer nur das eben getippte Wort
  /// ansieht, verliert alle Regeln, die nach rechts schauen. Und das sind
  /// die wichtigsten: „vă rog", „până în", „faptul că".
  bool _haekchenGesetzt(String text, AngefangenesWort wort, int cursor) {
    final d = WortlisteService.diakritika;
    if (!d.bereit) return false;

    final davor = AngefangenesWort.ausEingabe(text, wort.von > 0 ? wort.von - 1 : 0);
    final davorDavor = davor == null || davor.von == 0
        ? null
        : AngefangenesWort.ausEingabe(text, davor.von - 1);

    // Von hinten nach vorn ersetzen, damit die Stellen der vorderen Wörter
    // gültig bleiben.
    final neu = d.korrektur(wort.text, links: davor?.text);
    final neuDavor = davor == null
        ? null
        : d.korrektur(davor.text, links: davorDavor?.text, rechts: wort.text);
    if (neu == null && neuDavor == null) return false;

    var ergebnis = text;
    var verschoben = 0;
    if (neu != null && !_inRuheLassen.contains(wort.text)) {
      ergebnis = ergebnis.replaceRange(wort.von, wort.bis, neu);
      verschoben += neu.length - wort.text.length;
    }
    if (neuDavor != null && !_inRuheLassen.contains(davor!.text)) {
      ergebnis = ergebnis.replaceRange(davor.von, davor.bis, neuDavor);
      verschoben += neuDavor.length - davor.text.length;
    }
    if (ergebnis == text) return false;

    _rueckgaengig = _Ersetzung(
      von: wort.von,
      original: wort.text,
      eingesetzt: neu ?? wort.text,
      nachher: ergebnis,
      ganzerTextVorher: text,
    );
    _letzterText = ergebnis;
    widget.controller.value = TextEditingValue(
      text: ergebnis,
      selection: TextSelection.collapsed(offset: cursor + verschoben),
    );
    _neuRechnen();
    return true;
  }

  /// Korrigiert das LETZTE Wort, bevor die Nachricht rausgeht.
  ///
  /// ⚠️ Ohne das blieb das letzte Wort jeder Nachricht immer unkorrigiert —
  /// es folgt ihm ja kein Leerzeichen mehr. Bei „va rog" ist das ausgerechnet
  /// das Wort, um das es geht.
  ///
  /// Es gelten dieselben Sicherungen wie sonst: ein richtiges Wort und ein
  /// großgeschriebener Eigenname mitten im Satz bleiben unangetastet.
  void vorDemSenden() {
    if (!widget.aktiv || !mounted) return;
    final text = widget.controller.text;
    // ⚠️ Dieselbe Funktion wie im Blitz — siehe [autoKorrigiert]. Zwei
    // Fassungen derselben Regel wären zwei Fassungen, die auseinanderlaufen.
    final neu = autoKorrigiert(text, inRuheLassen: _inRuheLassen);
    if (neu == text) return;
    _letzterText = neu;
    _rueckgaengig = null;
    widget.controller.value = TextEditingValue(
      text: neu,
      selection: TextSelection.collapsed(offset: neu.length),
    );
  }

  /// Dieselben Sicherungen wie beim Tippen.
  bool _erlaubt(AngefangenesWort w, String text) =>
      !_inRuheLassen.contains(w.text) &&
      !(AngefangenesWort.grossGeschrieben(w.text) &&
          !AngefangenesWort.istSatzanfang(text, w.von));

  void _neuRechnen() {
    final wahl = widget.controller.selection;
    // Bei einer Auswahl über mehrere Zeichen gibt es kein „angefangenes"
    // Wort — und ein Vorschlag würde die Auswahl beim Übernehmen fressen.
    final wort = (wahl.isValid && wahl.isCollapsed)
        ? AngefangenesWort.ausEingabe(widget.controller.text, wahl.baseOffset)
        : null;

    final neu = wort == null
        ? const <String>[]
        : WortlisteService.index.vorschlaege(wort.text);

    _wort = wort;
    if (neu.length == _vorschlaege.length &&
        (neu.isEmpty || neu.first == _vorschlaege.first)) {
      return;
    }
    setState(() => _vorschlaege = neu);
  }

  /// Setzt [wahl] (oder den obersten Vorschlag) an die Stelle des
  /// angefangenen Wortes — der Weg über Antippen und Tabulator, ohne
  /// Sicherungen, weil er ausdrücklich angefordert wurde.
  bool _uebernehmen({String? wahl}) {
    final wort = _wort;
    if (wort == null || _vorschlaege.isEmpty) return false;
    final gewaehlt = WortIndex.schreibungUebernehmen(
      wort.text,
      wahl ?? _vorschlaege.first,
    );
    final text = widget.controller.text;
    // Das Leerzeichen ist der halbe Gewinn: sonst müsste man es nach jedem
    // übernommenen Wort selbst nachtippen.
    final neu = '${text.substring(0, wort.von)}$gewaehlt '
        '${text.substring(wort.bis)}';
    _rueckgaengig = null;
    _letzterText = neu;
    widget.controller.value = TextEditingValue(
      text: neu,
      selection:
          TextSelection.collapsed(offset: wort.von + gewaehlt.length + 1),
    );
    _neuRechnen();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.aktiv && _vorschlaege.isNotEmpty) _leiste(context),
        Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.tab): _UebernehmenIntent(),
          },
          child: Actions(
            actions: {
              _UebernehmenIntent: CallbackAction<_UebernehmenIntent>(
                onInvoke: (_) => _uebernehmen(),
              ),
            },
            child: widget.bauen(vorDemSenden),
          ),
        ),
      ],
    );
  }

  Widget _leiste(BuildContext context) {
    return Container(
      height: 38,
      margin: const EdgeInsets.only(bottom: 4),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _vorschlaege.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, i) {
          final wort = _vorschlaege[i];
          // Der erste ist der, den die Eingabetaste nimmt — das muss man
          // sehen können, sonst ist die Regel oben unsichtbar.
          final erster = i == 0;
          return Material(
            color: erster ? const Color(0xFF1a1a2e) : F.h(Colors.grey, 200),
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _uebernehmen(wahl: wort),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Center(
                  child: Text(
                    WortIndex.schreibungUebernehmen(_wort?.text ?? '', wort),
                    style: TextStyle(
                      color: erster ? Colors.white : F.h(Colors.grey, 900),
                      fontWeight: erster ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _UebernehmenIntent extends Intent {
  const _UebernehmenIntent();
}

/// Was die Leertaste zuletzt ersetzt hat — alles, was die Rücktaste braucht,
/// um den Stand davor wiederherzustellen.
class _Ersetzung {
  final int von;
  final String original;
  final String eingesetzt;

  /// Der volle Text NACH der Ersetzung. Nur wenn er noch genau so dasteht,
  /// war die Rücktaste wirklich der nächste Anschlag.
  final String nachher;

  /// Bei der Häkchen-Korrektur der volle Text DAVOR — dort können zwei Wörter
  /// auf einmal geändert worden sein, und dann ist das Zurücksetzen des
  /// ganzen Textes die einzige Fassung, die stimmt.
  final String? ganzerTextVorher;

  const _Ersetzung({
    required this.von,
    required this.original,
    required this.eingesetzt,
    required this.nachher,
    this.ganzerTextVorher,
  });
}
