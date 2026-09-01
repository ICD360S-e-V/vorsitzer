import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../models/dock_eintrag.dart';
import '../utils/app_farben.dart';
import 'logger_service.dart';

/// Steuert die Schnellstart-Leiste vom Hauptfenster aus (nur Linux).
///
/// ⚠️ Es gibt IMMER genau EINE Leiste, und sie wird nie geschlossen. Zwei
/// Gründe, dieselben wie beim Blitz-Fenster:
/// 1. [kDockKanal] ist bidirektional — das Paket lässt genau zwei Engines
///    zu. Ein zweites Fenster fände den Kanal besetzt.
/// 2. Eine Engine zu starten dauert rund eine Sekunde. Eine Leiste, die bei
///    jedem Zuklappen neu hochfährt, wäre keine Leiste.
///
/// ⚠️ NUR LINUX. Unter Windows gibt es das Tray-Symbol mit Menü
/// (`TrayService`), unter macOS die Menüleiste — dort wäre eine schwebende
/// Leiste ein Fremdkörper neben etwas, das das System schon anbietet. Und
/// unter Linux ist sie kein Luxus: `TrayService.isSupported` ist dort
/// `false`, es gibt also gar keinen anderen Weg zum minimierten Programm als
/// die Fensterliste.
class DockFensterSteuerung {
  DockFensterSteuerung._();
  static final DockFensterSteuerung instanz = DockFensterSteuerung._();

  static const _kanal = WindowMethodChannel(kDockKanal);
  final _log = LoggerService();

  WindowController? _fenster;
  bool _bereit = false;

  /// Zuletzt gesendeter Stand. Dient als Nutzlast beim Erzeugen des Fensters,
  /// damit die Leiste schon im ersten Bild die richtigen Abzeichen trägt,
  /// statt eine Sekunde lang leer auszusehen und dann umzuspringen.
  Map<String, int> _zaehler = const {};

  /// Liefert die Liste eines Bereichs. Setzt das Dashboard.
  ///
  /// ⚠️ Ohne diesen Lieferanten zeigt die Leiste „Programm noch nicht
  /// bereit" — was am Anmeldebildschirm genau richtig ist: dort gibt es
  /// weder Mitglieder noch Termine, und eine leere Liste wäre eine Lüge.
  Future<List<DockEintrag>> Function(String bereich)? datenGeber;

  /// Auf eine Zeile (oder auf „Im Programm öffnen") getippt. `id` ist die
  /// Zeile, `null` heisst „nur den Bereich". `datum` (`YYYY-MM-DD`) ist nur
  /// bei Terminen gesetzt und sagt dem Bildschirm, auf welche Woche er
  /// stellen muss — siehe [DockEintrag.datum].
  void Function(String bereich, int? id, String datum)? onOeffnen;

  bool get istMoeglich => Platform.isLinux;

  /// Kanal scharf machen. Muss laufen, BEVOR die Leiste erzeugt wird —
  /// sonst fragt sie in ein Loch.
  Future<void> bereitmachen() async {
    if (!istMoeglich || _bereit) return;
    try {
      await _kanal.setMethodCallHandler(_ruf);
      _bereit = true;
    } catch (e) {
      _log.error('Dock-Kanal nicht bereit: $e', tag: 'DOCK');
    }
  }

  /// Leiste anzeigen (erzeugt das Fenster beim ersten Mal).
  ///
  /// Gibt `false` zurück, wenn es nicht ging. Der Aufrufer soll das NICHT
  /// als Fehler behandeln: das Programm ist ohne Leiste vollständig
  /// benutzbar, sie ist eine Abkürzung.
  Future<bool> starten() async {
    if (!istMoeglich) return false;
    if (_fenster != null) return true;
    await bereitmachen();
    try {
      _fenster = await WindowController.create(WindowConfiguration(
        hiddenAtLaunch: true,
        arguments: '$kDockFensterArgument:${jsonEncode({
              'zaehler': _zaehler,
              'dunkel': F.istDunkel,
            })}',
      ));
      _log.info('Schnellstart-Leiste gestartet', tag: 'DOCK');
      return true;
    } catch (e) {
      // ⚠️ `_fenster` bleibt `null`, damit ein späterer Anlauf es noch einmal
      // versuchen darf. Anders als beim Blitz gibt es hier kein halb
      // erzeugtes Fenster, das man doppeln könnte: schlägt `create` fehl,
      // existiert keines.
      _log.error('Schnellstart-Leiste ging nicht auf: $e', tag: 'DOCK');
      return false;
    }
  }

  /// Neue Abzeichen (und ggf. neues Farbschema) an die Leiste schieben.
  ///
  /// ⚠️ Fehler werden GESCHLUCKT und nur protokolliert. Das ist Absicht: der
  /// Aufrufer ist das Dashboard mitten im Aufbau seiner Zähler. Eine Leiste,
  /// die gerade hochfährt, darf dort nichts umwerfen.
  Future<void> standSetzen(Map<String, int> zaehler) async {
    _zaehler = Map.unmodifiable(zaehler);
    if (!istMoeglich || _fenster == null) return;
    try {
      await _kanal.invokeMethod(DockRuf.stand, {
        'zaehler': _zaehler,
        'dunkel': F.istDunkel,
      });
    } on WindowChannelException {
      // Die Leiste meldet sich erst auf dem Kanal, wenn ihre Engine steht —
      // rund eine Sekunde. Wer in dieser Zeit schiebt, bekommt
      // `CHANNEL_UNREGISTERED`. Kein Grund für Lärm: der nächste Zählerstand
      // kommt ohnehin, und die Startnutzlast trug den letzten schon.
    } catch (e) {
      _log.warning('Dock-Stand nicht zugestellt: $e', tag: 'DOCK');
    }
  }

  Future<dynamic> _ruf(MethodCall ruf) async {
    switch (ruf.method) {
      case DockRuf.daten:
        return _daten(_karte(ruf.arguments));
      case DockRuf.oeffnen:
        final a = _karte(ruf.arguments);
        final bereich = '${a['bereich'] ?? ''}';
        if (bereich.isEmpty) return false;
        onOeffnen?.call(bereich, _alsInt(a['id']), '${a['datum'] ?? ''}');
        return true;
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _daten(Map<String, dynamic> a) async {
    final bereich = '${a['bereich'] ?? ''}';
    final geber = datenGeber;
    if (bereich.isEmpty) return {'ok': false, 'fehler': 'Kein Bereich'};
    if (geber == null) {
      // Passiert am Anmeldebildschirm und nach dem Abmelden: die Leiste lebt
      // noch, das Dashboard nicht. Ehrlich melden statt eine leere Liste zu
      // liefern, die wie „keine Mitglieder" aussieht.
      return {'ok': false, 'fehler': 'Nicht angemeldet'};
    }
    try {
      final liste = await geber(bereich);
      return {
        'ok': true,
        'eintraege': liste.map((e) => e.toJson()).toList(),
      };
    } catch (e) {
      _log.error('Dock-Daten für $bereich fehlgeschlagen: $e', tag: 'DOCK');
      return {'ok': false, 'fehler': 'Laden fehlgeschlagen'};
    }
  }

  /// Nach dem Abmelden: die Leiste darf keine Namen mehr zeigen.
  ///
  /// ⚠️ Das Fenster bleibt stehen (siehe Klassenkommentar), aber ohne
  /// Lieferanten antwortet es „Nicht angemeldet" — und die Abzeichen werden
  /// geleert, sonst hinge über dem Chat-Symbol weiter eine Zahl aus der
  /// Sitzung von jemand anderem.
  Future<void> abmelden() async {
    datenGeber = null;
    onOeffnen = null;
    await standSetzen(const {});
  }

  static Map<String, dynamic> _karte(dynamic a) =>
      a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{};

  static int? _alsInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}
