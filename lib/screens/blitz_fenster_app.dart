import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../models/blitz_nachricht.dart';
import '../utils/app_farben.dart';
import '../widgets/blitz_karte.dart';

/// Breite der Karte am Rechner. Bewusst schmal: sie legt sich über das, woran
/// gerade gearbeitet wird, und soll dort nichts verdecken, was man noch
/// braucht.
///
/// 26.08.2026 von 460 auf 380 verkleinert — im Betrieb war die Karte „ein
/// bisschen gross" (Rückmeldung des Vorsitzenden, nachdem sie das erste Mal
/// wirklich auf dem Schreibtisch stand). Eine Meldung, die man wegklicken
/// will, darf weniger Platz einnehmen als das, woran man arbeitet.
const double kBlitzBreite = 380;

/// Höhe beim Aufblenden, bevor der erste Rahmen gemessen ist. Danach richtet
/// sich das Fenster nach dem Inhalt ([_BlitzFensterAppState._hoeheAnpassen]).
const double kBlitzStartHoehe = 130;

/// Grenzen für die inhaltsabhängige Höhe. Nach oben gedeckelt, damit ein
/// Schwall von fünf Zeilen die Karte nicht über den halben Bildschirm zieht —
/// darüber scrollt der Text innerhalb der Karte.
const double kBlitzMinHoehe = 96;
const double kBlitzMaxHoehe = 340;

const Size kBlitzFensterGroesse = Size(kBlitzBreite, kBlitzStartHoehe);

/// Die Wurzel des Blitz-Fensters unter Linux.
///
/// ⚠️ EIGENE ENGINE, EIGENES ISOLATE. Hier gibt es weder `ChatService` noch
/// `ApiService` noch den angemeldeten Benutzer — alles, was dieses Fenster
/// weiss, ist durch [kBlitzKanal] hereingereicht worden, und alles, was es
/// tun will, muss es das Hauptfenster tun lassen. Ein `ApiService()` hier
/// wäre eine zweite, nicht angemeldete Instanz und würde still 401 liefern.
class BlitzFensterApp extends StatefulWidget {
  final BlitzNachricht ersteNachricht;

  const BlitzFensterApp({super.key, required this.ersteNachricht});

  @override
  State<BlitzFensterApp> createState() => _BlitzFensterAppState();
}

class _BlitzFensterAppState extends State<BlitzFensterApp>
    with WidgetsBindingObserver {
  static const _kanal = WindowMethodChannel(kBlitzKanal);

  late BlitzNachricht _nachricht = widget.ersteNachricht;
  final _entwurf = ValueNotifier<bool>(false);

  /// Schlüssel auf die Karte, um ihre wirkliche Höhe zu messen.
  final _karteSchluessel = GlobalKey();
  double _letzteHoehe = kBlitzStartHoehe;

  @override
  void initState() {
    super.initState();
    // ⚠️ Nötig, weil der erste Rahmen mit einem 1×1-Fenster kommt und dort
    // nicht gemessen werden darf. Ohne diesen Beobachter bliebe die Karte auf
    // [kBlitzStartHoehe] stehen, bis zufällig die nächste Nachricht einen
    // neuen Rahmen auslöst — gemessen: 460×170 statt der nötigen 460×154,
    // also ein leerer Streifen unter der Karte.
    WidgetsBinding.instance.addObserver(this);
    _kanal.setMethodCallHandler((ruf) async {
      switch (ruf.method) {
        case BlitzRuf.zeigen:
          final n = BlitzNachricht.entschluesselt('${ruf.arguments}');
          if (n != null && mounted) {
            setState(() => _nachricht = n);
            await _nachVorneHolen();
          }
          return true;
        // Das Hauptfenster fragt vor einem Wechsel auf eine ANDERE
        // Unterhaltung, ob hier schon getippt wurde. Sagt es ja, lässt das
        // Hauptfenster die Karte in Ruhe und schickt die neue Nachricht
        // stattdessen als gewöhnliche Benachrichtigung.
        case BlitzRuf.hatEntwurf:
          return _entwurf.value;
        default:
          return null;
      }
    });
  }

  /// Die Engine hat neue Fenstermasse bekommen — jetzt lässt sich die Karte
  /// zum ersten Mal ehrlich messen.
  @override
  void didChangeMetrics() => _hoeheAnpassen();

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entwurf.dispose();
    super.dispose();
  }

  /// Fenster auf die Höhe der Karte bringen.
  ///
  /// ⚠️ Ohne das steht die Karte oben in einem festen 460×300-Fenster und
  /// darunter klafft ein leeres Rechteck — auf einem Bildschirm ohne
  /// Compositor schwarz, gemessen im Probelauf.
  ///
  /// ⚠️ Nur bei einem Unterschied von mehr als 4 px, sonst schaukelt sich
  /// Messen → Verändern → Neu vermessen endlos auf.
  void _hoeheAnpassen() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final box = _karteSchluessel.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) return;
      // ⚠️ Der ERSTE Rahmen kommt mit einem 1×1-Fenster: die Engine hat die
      // Fenstermasse noch nicht bekommen. Bei einem Pixel Breite bricht jeder
      // Text nach jedem Buchstaben um, und die Karte meldet eine Höhe von
      // über tausend Pixeln — gemessen: karte=Size(1.0, 1049.0),
      // fenster=Size(1.0, 1.0). Ungefiltert riss das Fenster beim ersten
      // Blitz auf die volle Deckelhöhe auf und schrumpfte erst bei der
      // nächsten Nachricht wieder.
      if (box.size.width < kBlitzBreite - 1) return;
      final ziel = box.size.height.clamp(kBlitzMinHoehe, kBlitzMaxHoehe);
      if ((ziel - _letzteHoehe).abs() <= 4) return;
      _letzteHoehe = ziel;
      try {
        await windowManager.setSize(Size(kBlitzBreite, ziel));
        await windowManager.setAlignment(Alignment.center);
      } catch (_) {/* Fenster weg — dann gibt es auch nichts anzupassen */}
    });
  }

  Future<void> _nachVorneHolen() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (_) {
      // Ein Fensterverwalter, der den Fokus verweigert, ist kein Grund die
      // Karte zu verlieren — sie steht dann eben unfokussiert oben.
    }
  }

  Future<String?> _senden(String text) async {
    try {
      final antwort = await _kanal.invokeMethod<dynamic>(BlitzRuf.senden, {
        'conversation_id': _nachricht.conversationId,
        'text': text,
        'kanal': _nachricht.kanal,
      });
      if (antwort is Map && antwort['ok'] == true) return null;
      if (antwort is Map && antwort['fehler'] != null) return '${antwort['fehler']}';
      return 'Senden fehlgeschlagen';
    } catch (e) {
      // Häufigster Fall: das Hauptfenster ist weg (Abmeldung, Absturz).
      return 'Hauptfenster nicht erreichbar';
    }
  }

  Future<void> _schliessen() async {
    // Erst selbst verstecken — das ist sofort sichtbar und hängt nicht daran,
    // ob das Hauptfenster gerade antwortet.
    try {
      await windowManager.hide();
    } catch (_) {/* siehe oben */}
    try {
      await _kanal.invokeMethod(BlitzRuf.schliessen);
    } catch (_) {/* Hauptfenster weg — dann ist ohnehin nichts mehr zu melden */}
  }

  Future<void> _imChatOeffnen() async {
    try {
      await windowManager.hide();
    } catch (_) {}
    try {
      await _kanal.invokeMethod(BlitzRuf.imChatOeffnen, {
        'conversation_id': _nachricht.conversationId,
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Nach jedem Rahmen prüfen, ob das Fenster noch zur Karte passt — die
    // Karte wächst, wenn eine zweite Zeile desselben Absenders dazukommt.
    _hoeheAnpassen();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4a90d9),
          brightness: F.istDunkel ? Brightness.dark : Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: Scaffold(
        // Durchsichtig, damit die abgerundeten Ecken der Karte nicht auf einem
        // grauen Rechteck sitzen.
        backgroundColor: Colors.transparent,
        // ⚠️ Der Scroller gibt der Karte nach unten UNBEGRENZTEN Platz. Nur
        // so hat sie eine eigene natürliche Höhe, an der sich das Fenster
        // ausrichten kann; in einem festen Rahmen gemessen wäre die Karte
        // immer genau so hoch wie das Fenster und würde nie wachsen.
        body: SingleChildScrollView(
          child: BlitzKarte(
            key: _karteSchluessel,
            nachricht: _nachricht,
            entwurfMelder: _entwurf,
            onSenden: _senden,
            onSchliessen: _schliessen,
            onImChatOeffnen: _imChatOeffnen,
          ),
        ),
      ),
    );
  }
}

/// Startet das Blitz-Fenster. Wird aus `main()` gerufen, wenn das Fenster-
/// argument mit [kBlitzFensterArgument] beginnt.
Future<void> blitzFensterStarten(String argument) async {
  // Format: 'blitz:<json>' mit {nachricht: {...}, dunkel: bool}
  final doppelpunkt = argument.indexOf(':');
  Map<String, dynamic> nutzlast = const {};
  if (doppelpunkt >= 0 && doppelpunkt + 1 < argument.length) {
    try {
      final j = jsonDecode(argument.substring(doppelpunkt + 1));
      if (j is Map) nutzlast = Map<String, dynamic>.from(j);
    } catch (_) {/* unten aufgefangen */}
  }

  // ⚠️ `F.istDunkel` ist ein statisches Feld — in DIESEM Isolate eine eigene
  // Kopie, die ohne diese Zeile immer `false` bliebe. Die Karte stünde dann
  // hell vor einer dunklen App.
  F.istDunkel = nutzlast['dunkel'] == true;

  final nachricht = BlitzNachricht.fromJson(
      Map<String, dynamic>.from(nutzlast['nachricht'] as Map? ?? const {}));

  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(
    const WindowOptions(
      size: kBlitzFensterGroesse,
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      alwaysOnTop: true,
    ),
    () async {
      await windowManager.setAlwaysOnTop(true);
      // Nicht in der Fensterliste: die Karte ist eine Meldung, kein Programm.
      await windowManager.setSkipTaskbar(true);
      await windowManager.show();
      // ⚠️ Grösse und Mitte ERST NACH dem Anzeigen, und das ist kein Aberglaube:
      // desktop_multi_window ruft beim Erzeugen
      // `gtk_window_set_default_size(window, 1280, 720)`, und mit
      // `hiddenAtLaunch` wird das Fenster nur *realisiert*, nicht abgebildet.
      // Alles, was vor dem Abbilden gesetzt wird, überschreibt GTK dabei mit
      // dieser Vorgabe — gemessen: 1280×720 statt 460×300.
      await windowManager.setSize(kBlitzFensterGroesse);
      await windowManager.setAlignment(Alignment.center);
      // ⚠️ KEIN setResizable(false). GTK ignoriert `gtk_window_resize` auf
      // einem nicht veränderbaren Fenster — stand es hier, blieb die Karte
      // bei 1280×720 und ragte rechts aus dem Bildschirm. Gemessen: mit
      // Aufruf 1280×720, ohne Aufruf 460×300 an 730,390 (also mittig auf
      // 1920×1080). Ohne Titelleiste gibt es ohnehin keinen Rand zum Ziehen.
      // Der Benutzer hat sich für „nimmt die Tastatur sofort" entschieden.
      await windowManager.focus();
    },
  );

  runApp(BlitzFensterApp(ersteNachricht: nachricht));
}
