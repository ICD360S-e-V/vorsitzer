import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../models/dock_eintrag.dart';
import '../utils/app_farben.dart';

/// Breite des Symbolstreifens am rechten Bildschirmrand.
const double kLeisteBreite = 56;

/// Breite des ausgeklappten Panels daneben.
const double kPanelBreite = 340;

/// Höhe im eingeklappten Zustand: drei Symbole plus Griff.
const double kLeisteHoehe = 232;

/// Höhe im ausgeklappten Zustand.
const double kPanelHoehe = 520;

/// Breite des Schlafzustands — ein schmaler Streifen am Rand.
///
/// ⚠️ Die Leiste lässt sich NICHT ganz schliessen, nur bis hierher
/// zusammenschieben. Ein Fenster ohne Titelleiste, das ganz verschwindet,
/// hat keinen Weg zurück: es steht in keiner Fensterliste
/// (`setSkipTaskbar`) und der Tray ist unter Linux gar nicht eingerichtet
/// (`TrayService.isSupported` ist dort `false`). Wer es schliessen könnte,
/// bekäme es ohne Neustart nicht wieder.
const double kSchlafBreite = 14;
const double kSchlafHoehe = 96;

/// Zustände der Leiste.
enum _Zustand { schlaf, leiste, offen }

/// Die Wurzel der Schnellstart-Leiste unter Linux.
///
/// ⚠️ EIGENE ENGINE, EIGENES ISOLATE — genau wie beim Blitz-Fenster. Hier
/// gibt es weder `ApiService` noch `GlobalChatService` noch den angemeldeten
/// Benutzer. Alles, was diese Leiste zeigt, hat das Hauptfenster über
/// [kDockKanal] hereingereicht, und alles, was sie tun will, muss sie das
/// Hauptfenster tun lassen.
class DockFensterApp extends StatefulWidget {
  final Map<String, int> zaehler;

  const DockFensterApp({super.key, this.zaehler = const {}});

  @override
  State<DockFensterApp> createState() => _DockFensterAppState();
}

class _DockFensterAppState extends State<DockFensterApp> {
  static const _kanal = WindowMethodChannel(kDockKanal);

  _Zustand _zustand = _Zustand.leiste;
  String? _offenerBereich;
  List<DockEintrag> _eintraege = const [];
  bool _laedt = false;
  String? _fehler;
  late Map<String, int> _zaehler = Map.of(widget.zaehler);

  @override
  void initState() {
    super.initState();
    _kanal.setMethodCallHandler(_ruf);
  }

  Future<dynamic> _ruf(MethodCall ruf) async {
    if (ruf.method != DockRuf.stand) return null;
    final n = _karte(ruf.arguments);
    if (!mounted) return true;

    final rohZaehler = n['zaehler'];
    final neueZaehler = <String, int>{};
    if (rohZaehler is Map) {
      rohZaehler.forEach((k, v) {
        final i = v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
        if (i != null) neueZaehler['$k'] = i;
      });
    }

    // ⚠️ Die Farbe muss VOR setState umgeschaltet werden: `F` liest einen
    // statischen Schalter, kein Provider hängt daran. Wird er erst danach
    // gesetzt, zeichnet dieser Rahmen noch in der alten Helligkeit und die
    // Leiste bliebe hell, bis zufällig etwas anderes einen Rahmen auslöst.
    // `F` ist ein statischer Schalter, kein Provider — es hängt nichts
    // daran. Das ist hier unschädlich, weil `setState` gleich darunter den
    // GANZEN Baum dieses Fensters neu baut (er entsteht vollständig in
    // `build`). In einem Fenster mit eigenen Unterzuständen müsste stattdessen
    // `F.uebernehmen(context, ...)` gerufen werden.
    if (n['dunkel'] is bool) F.istDunkel = n['dunkel'] as bool;

    final vorher = _offenerBereich == null ? null : _zaehler[_offenerBereich];
    setState(() => _zaehler = neueZaehler);

    // Steht das Panel offen und hat sich SEIN Zähler bewegt, ist die Liste
    // von eben veraltet — dann gleich nachladen. Bei allen anderen Bereichen
    // wäre das eine Anfrage für etwas, das niemand ansieht.
    final jetzt = _offenerBereich == null ? null : neueZaehler[_offenerBereich];
    if (_zustand == _Zustand.offen && vorher != jetzt) {
      unawaited(_ladenFuer(_offenerBereich!));
    }
    return true;
  }

  static Map<String, dynamic> _karte(dynamic a) {
    if (a is Map) return Map<String, dynamic>.from(a);
    if (a is String) {
      try {
        final j = jsonDecode(a);
        if (j is Map) return Map<String, dynamic>.from(j);
      } catch (_) {}
    }
    return const {};
  }

  // ──────────────────────────────────────────────────────────────────
  // Fenstergeometrie
  // ──────────────────────────────────────────────────────────────────

  Size _groesseFuer(_Zustand z) => switch (z) {
        _Zustand.schlaf => const Size(kSchlafBreite, kSchlafHoehe),
        _Zustand.leiste => const Size(kLeisteBreite, kLeisteHoehe),
        _Zustand.offen =>
          const Size(kLeisteBreite + kPanelBreite, kPanelHoehe),
      };

  /// ⚠️ ERST die Grösse, DANN die Ausrichtung — und nicht umgekehrt.
  /// `windowManager.setAlignment` liest intern die AKTUELLE Grösse und
  /// rechnet daraus die Position. Vor dem Verkleinern gerufen, positioniert
  /// es nach dem alten, breiteren Fenster; die Leiste rutschte dann bei
  /// jedem Zuklappen ein Stück vom Rand weg statt bündig zu bleiben.
  Future<void> _fensterAnpassen(_Zustand z) async {
    // ⚠️ FÄNGT ALLES. Und das ist keine Vorsichtsmassnahme, sondern die
    // Reparatur eines beobachteten Fehlers: `_bereichAntippen` wartet erst
    // auf `_wechseln` und lädt DANACH die Liste. Fliegt hier etwas heraus,
    // wird die Liste nie geholt — das Panel steht offen und bleibt für immer
    // leer, ohne Fehlermeldung, weil die Ausnahme aus einem Future kommt und
    // am Bildschirm vorbeigeht. Gesehen beim Rendern der Leiste, wo
    // `getSize` (das `setAlignment` intern ruft) nichts zurückgab.
    //
    // Das Schlimmste, was jetzt passieren kann, ist ein Fenster in der alten
    // Grösse — sichtbar, und der Inhalt ist trotzdem da.
    try {
      await windowManager.setSize(_groesseFuer(z));
      await windowManager.setAlignment(Alignment.centerRight);
    } catch (e) {
      // ⚠️ `debugPrint`, NICHT `LoggerService`. Die Leiste ist eine eigene
      // Engine; der Protokolldienst des Hauptfensters schriebe von hier aus
      // in dieselbe Datei — dieselbe Doppelung, wegen der `main()` für
      // Nebenfenster überhaupt abbiegt.
      debugPrint('Leiste: Fenstergrösse nicht gesetzt ($z): $e');
    }
  }

  Future<void> _wechseln(_Zustand z) async {
    if (!mounted) return;
    setState(() => _zustand = z);
    await _fensterAnpassen(z);
  }

  // ──────────────────────────────────────────────────────────────────
  // Daten
  // ──────────────────────────────────────────────────────────────────

  Future<void> _ladenFuer(String bereich) async {
    if (!mounted) return;
    setState(() {
      _laedt = true;
      _fehler = null;
    });
    try {
      final antwort = _karte(
        await _kanal.invokeMethod(DockRuf.daten, {'bereich': bereich}),
      );
      if (!mounted || _offenerBereich != bereich) return;
      if (antwort['ok'] == true) {
        setState(() {
          _eintraege = DockEintrag.listeAusJson(antwort['eintraege']);
          _laedt = false;
        });
      } else {
        setState(() {
          _eintraege = const [];
          _fehler = '${antwort['fehler'] ?? 'Keine Daten erhalten'}';
          _laedt = false;
        });
      }
    } on WindowChannelException {
      if (!mounted || _offenerBereich != bereich) return;
      // ⚠️ Das ist der häufigste Fall und KEIN Netzfehler: das Hauptfenster
      // hat sich noch nicht auf dem Kanal gemeldet (Anmeldebildschirm, oder
      // die Engine fährt gerade hoch). Der Text muss das sagen — „Fehler
      // beim Laden" schickte den Benutzer auf die falsche Fährte.
      setState(() {
        _eintraege = const [];
        _fehler = 'Programm noch nicht bereit';
        _laedt = false;
      });
    } catch (e) {
      if (!mounted || _offenerBereich != bereich) return;
      setState(() {
        _eintraege = const [];
        _fehler = 'Laden fehlgeschlagen';
        _laedt = false;
      });
    }
  }

  Future<void> _bereichAntippen(String bereich) async {
    // Dasselbe Symbol noch einmal: zuklappen.
    if (_zustand == _Zustand.offen && _offenerBereich == bereich) {
      setState(() {
        _offenerBereich = null;
        _eintraege = const [];
        _fehler = null;
      });
      await _wechseln(_Zustand.leiste);
      return;
    }
    setState(() {
      _offenerBereich = bereich;
      _eintraege = const [];
      _fehler = null;
    });
    await _wechseln(_Zustand.offen);
    await _ladenFuer(bereich);
  }

  /// „Im Programm öffnen" — das Hauptfenster nach vorn holen.
  ///
  /// ⚠️ Ein fehlgeschlagener Sprung wird ANGEZEIGT, nicht verschluckt. Sonst
  /// tippt jemand auf eine Zeile, es passiert nichts, und er tippt weiter.
  Future<void> _oeffnen(String bereich, int? id) async {
    try {
      await _kanal.invokeMethod(DockRuf.oeffnen, {
        'bereich': bereich,
        if (id != null) 'id': id,
      });
    } catch (_) {
      if (mounted) setState(() => _fehler = 'Programm antwortet nicht');
    }
  }

  // ──────────────────────────────────────────────────────────────────
  // Aufbau
  // ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Material(
        // ⚠️ Deckend, und die Ecken bleiben eckig. Der Linux-Runner setzt den
        // Hintergrund der Ansicht auf `#000000` (my_application.cc); was hier
        // nicht selbst bemalt wird, ist SCHWARZ, nicht durchsichtig. Runde
        // Ecken oder ein Abstand zwischen Panel und Streifen ergäben schwarze
        // Zwickel — auf einem Bildschirm ohne Compositor bleiben sie stehen.
        color: F.flaeche,
        child: _zustand == _Zustand.schlaf ? _schlaf() : _wach(),
      ),
    );
  }

  Widget _schlaf() => Tooltip(
        message: 'Schnellstart ausklappen',
        child: InkWell(
          onTap: () => _wechseln(_Zustand.leiste),
          child: Container(
            decoration: BoxDecoration(
              color: F.flaecheBetont,
              border: Border(left: BorderSide(color: F.rand)),
            ),
            child: Icon(Icons.chevron_left,
                size: 14, color: F.textSchwach),
          ),
        ),
      );

  /// ⚠️ Das Panel bekommt [Expanded], KEINE feste Breite — und das ist eine
  /// gemessene Reparatur, kein Geschmack.
  ///
  /// Der Baum wird neu gebaut, BEVOR das Fenster breiter ist: `_wechseln`
  /// setzt erst den Zustand und wartet danach auf `_fensterAnpassen`. Es gibt
  /// also mindestens einen Rahmen, in dem 340 + 56 Pixel in ein 56 Pixel
  /// breites Fenster sollen. Mit fester Breite ist das ein
  /// „RenderFlex overflowed by 340 pixels" — im Prüflauf eine rote Fläche,
  /// im Betrieb ein abgeschnittener Rahmen.
  ///
  /// Schlimmer wäre der Dauerzustand: seit `_fensterAnpassen` Fehler
  /// schluckt (siehe dort), kann das Fenster auch schmal BLEIBEN. Mit
  /// [Expanded] wird das Panel dann nur zusammengedrückt und der Streifen
  /// bleibt bedienbar; mit fester Breite stünde dort dauerhaft das
  /// Überlauf-Muster.
  ///
  /// Der Streifen behält seine feste Breite: er ist das, was in jedem Fall
  /// erreichbar bleiben muss.
  Widget _wach() => ClipRect(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_zustand == _Zustand.offen) Expanded(child: _panel()),
            Container(width: 1, color: F.rand),
            SizedBox(width: kLeisteBreite - 1, child: _streifen()),
          ],
        ),
      );

  Widget _streifen() => Container(
        color: F.flaecheGedaempft,
        child: Column(
          children: [
            for (final b in DockBereich.alle) _symbol(b),
            const Spacer(),
            Tooltip(
              message: 'Leiste an den Rand schieben',
              child: IconButton(
                iconSize: 18,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                    minWidth: kLeisteBreite - 1, minHeight: 40),
                icon: Icon(Icons.chevron_right, color: F.textLeise),
                onPressed: () {
                  setState(() {
                    _offenerBereich = null;
                    _eintraege = const [];
                  });
                  _wechseln(_Zustand.schlaf);
                },
              ),
            ),
          ],
        ),
      );

  Widget _symbol(String bereich) {
    final aktiv = _zustand == _Zustand.offen && _offenerBereich == bereich;
    final anzahl = _zaehler[bereich] ?? 0;
    return Tooltip(
      message: _titel(bereich),
      child: InkWell(
        onTap: () => _bereichAntippen(bereich),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: aktiv ? F.flaeche : null,
            border: Border(
              // Der aktive Bereich wird links markiert, also auf der Seite,
              // an der das Panel hängt — der Strich verbindet Symbol und
              // Inhalt, statt sie zu trennen.
              left: BorderSide(
                color: aktiv ? Colors.blue.shade600 : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          // ⚠️ `StackFit.expand` — ohne das misst sich der Stack am grössten
          // NICHT positionierten Kind, also am 22 Pixel breiten Symbol. Die
          // Zahl sass dann mit `right: 8` acht Pixel vom rechten Rand des
          // SYMBOLS, lag also mitten darauf statt in der Ecke des Streifens.
          // Nur auf dem Bild zu sehen gewesen, nicht im Quelltext.
          child: Stack(
            fit: StackFit.expand,
            children: [
              Center(
                child: Icon(
                  _ikone(bereich),
                  size: 22,
                  color: aktiv ? Colors.blue.shade600 : F.textSchwach,
                ),
              ),
              if (anzahl > 0)
                Positioned(
                  top: 8,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 1),
                    constraints: const BoxConstraints(minWidth: 16),
                    decoration: BoxDecoration(
                      color: Colors.red.shade600,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      anzahl > 9 ? '9+' : '$anzahl',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _panel() {
    final bereich = _offenerBereich;
    if (bereich == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _kopf(bereich),
        Divider(height: 1, color: F.randLeise),
        Expanded(child: _inhalt(bereich)),
      ],
    );
  }

  Widget _kopf(String bereich) => Container(
        height: 44,
        color: F.flaecheGedaempft,
        padding: const EdgeInsets.only(left: 12, right: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _titel(bereich),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: F.textStark,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              iconSize: 17,
              tooltip: 'Neu laden',
              icon: Icon(Icons.refresh, color: F.textSchwach),
              onPressed: _laedt ? null : () => _ladenFuer(bereich),
            ),
            IconButton(
              iconSize: 17,
              tooltip: 'Im Programm öffnen',
              icon: Icon(Icons.open_in_new, color: F.textSchwach),
              onPressed: () => _oeffnen(bereich, null),
            ),
          ],
        ),
      );

  Widget _inhalt(String bereich) {
    if (_laedt && _eintraege.isEmpty) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_fehler != null) return _hinweis(_fehler!, Icons.error_outline);
    if (_eintraege.isEmpty) {
      return _hinweis(_leerText(bereich), Icons.inbox_outlined);
    }
    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: _eintraege.length,
      separatorBuilder: (_, __) => Divider(height: 1, color: F.randLeise),
      itemBuilder: (_, i) => _zeile(bereich, _eintraege[i]),
    );
  }

  Widget _hinweis(String text, IconData ikone) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(ikone, size: 26, color: F.textLeise),
              const SizedBox(height: 8),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: F.textSchwach),
              ),
            ],
          ),
        ),
      );

  Widget _zeile(String bereich, DockEintrag e) => InkWell(
        onTap: () => _oeffnen(bereich, e.id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.titel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: F.textStark,
                        fontWeight:
                            e.betont ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                    if (e.unterzeile.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        e.unterzeile,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: F.textSchwach),
                      ),
                    ],
                  ],
                ),
              ),
              if (e.zusatz.isNotEmpty || e.abzeichen > 0) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (e.zusatz.isNotEmpty)
                      Text(
                        e.zusatz,
                        style: TextStyle(fontSize: 10.5, color: F.textLeise),
                      ),
                    if (e.abzeichen > 0) ...[
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.red.shade600,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          e.abzeichen > 9 ? '9+' : '${e.abzeichen}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      );

  static IconData _ikone(String bereich) => switch (bereich) {
        DockBereich.mitglieder => Icons.people_outline,
        DockBereich.termine => Icons.event_outlined,
        DockBereich.chat => Icons.chat_bubble_outline,
        _ => Icons.circle_outlined,
      };

  static String _titel(String bereich) => switch (bereich) {
        DockBereich.mitglieder => 'Mitglieder',
        DockBereich.termine => 'Terminverwaltung',
        DockBereich.chat => 'Live-Chat',
        _ => bereich,
      };

  static String _leerText(String bereich) => switch (bereich) {
        DockBereich.mitglieder => 'Keine Mitglieder geladen',
        DockBereich.termine => 'Keine Termine in den nächsten 14 Tagen',
        DockBereich.chat => 'Keine offenen Unterhaltungen',
        _ => 'Nichts vorhanden',
      };
}

/// Einstiegspunkt des Leisten-Isolats. Wird aus `main()` gerufen, sobald das
/// Fensterargument mit [kDockFensterArgument] beginnt.
Future<void> dockFensterStarten(String argument) async {
  final nutzlast = DockEintrag.nutzlastLesen(argument);
  F.istDunkel = nutzlast['dunkel'] == true;

  final zaehler = <String, int>{};
  final rohZaehler = nutzlast['zaehler'];
  if (rohZaehler is Map) {
    rohZaehler.forEach((k, v) {
      final i = v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
      if (i != null) zaehler['$k'] = i;
    });
  }

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: Size(kLeisteBreite, kLeisteHoehe),
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
    ),
    () async {
      await windowManager.setAlwaysOnTop(true);
      // Nicht in der Fensterliste: die Leiste ist Zubehör des Programms,
      // kein zweites Programm. Stünde sie dort, hätte der Vorsitzende künftig
      // ZWEI Einträge in derselben Leiste, aus der er heraus wollte.
      await windowManager.setSkipTaskbar(true);
      await windowManager.show();
      // ⚠️ Grösse und Platz ERST NACH dem Anzeigen. `desktop_multi_window`
      // ruft beim Erzeugen `gtk_window_set_default_size(window, 1280, 720)`;
      // mit `hiddenAtLaunch` wird das Fenster nur realisiert, nicht
      // abgebildet, und GTK überschreibt beim Abbilden alles, was vorher
      // gesetzt wurde. Beim Blitz-Fenster stand deshalb 1280×720 statt der
      // Karte auf dem Schirm — hier wäre es eine bildschirmfüllende Leiste.
      await windowManager.setSize(const Size(kLeisteBreite, kLeisteHoehe));
      await windowManager.setAlignment(Alignment.centerRight);
      // ⚠️ KEIN setResizable(false). GTK ignoriert `gtk_window_resize` auf
      // einem nicht veränderbaren Fenster — die Leiste bliebe für immer bei
      // der ersten Grösse und liesse sich nie ausklappen. Ohne Titelleiste
      // gibt es ohnehin keinen Rand zum Ziehen.
      //
      // ⚠️ Und KEIN focus(). Die Leiste soll das Feld nicht stehlen, in dem
      // gerade getippt wird — anders als der Blitz, wo genau das gewollt ist.
    },
  );

  runApp(DockFensterApp(zaehler: zaehler));
}
