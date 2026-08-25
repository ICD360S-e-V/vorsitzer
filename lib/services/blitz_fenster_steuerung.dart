import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../models/blitz_nachricht.dart';
import '../utils/app_farben.dart';
import 'api_service.dart';
import 'global_chat_service.dart';
import 'logger_service.dart';

/// Steuert das Blitz-Fenster vom Hauptfenster aus (Desktop).
///
/// ⚠️ Es gibt IMMER genau ein Blitz-Fenster, und es wird nie geschlossen,
/// nur versteckt. Zwei Gründe:
/// 1. [kBlitzKanal] ist bidirektional — das Paket lässt genau zwei Engines
///    zu. Ein zweites Fenster fände den Kanal besetzt.
/// 2. Eine Engine zu starten dauert spürbar. Ein „Blitz", der erst eine
///    halbe Sekunde nachdenkt, ist keiner.
class BlitzFensterSteuerung {
  BlitzFensterSteuerung._();
  static final BlitzFensterSteuerung instanz = BlitzFensterSteuerung._();

  static const _kanal = WindowMethodChannel(kBlitzKanal);
  final _log = LoggerService();

  WindowController? _fenster;
  BlitzNachricht? _aktuell;
  bool _sichtbar = false;

  /// Wird gerufen, wenn im Blitz-Fenster „im Chat öffnen" gedrückt wurde.
  /// Setzt das Dashboard.
  void Function(int conversationId)? onImChatOeffnen;

  bool get sichtbar => _sichtbar;

  /// Muss einmal laufen, bevor das erste Fenster entsteht — sonst hat das
  /// Blitz-Fenster niemanden, dem es die Antwort geben kann.
  Future<void> bereitmachen() async {
    await _kanal.setMethodCallHandler(_ruf);
  }

  Future<dynamic> _ruf(MethodCall ruf) async {
    switch (ruf.method) {
      case BlitzRuf.senden:
        return _senden(ruf.arguments);
      case BlitzRuf.schliessen:
        _sichtbar = false;
        _aktuell = null;
        return true;
      case BlitzRuf.imChatOeffnen:
        _sichtbar = false;
        final id = _alsInt(_karte(ruf.arguments)['conversation_id']);
        _aktuell = null;
        if (id != null) onImChatOeffnen?.call(id);
        return true;
      default:
        return null;
    }
  }

  Future<Map<String, dynamic>> _senden(dynamic argumente) async {
    final a = _karte(argumente);
    final convId = _alsInt(a['conversation_id']);
    final text = '${a['text'] ?? ''}'.trim();
    final kanal = '${a['kanal'] ?? 'app'}';
    final mnr = GlobalChatService().currentMitgliedernummer;

    if (convId == null || text.isEmpty) {
      return {'ok': false, 'fehler': 'Leere Nachricht'};
    }
    if (mnr == null || mnr.isEmpty) {
      // Passiert nach dem Abmelden: das Fenster lebt noch, der Benutzer nicht
      // mehr. Ehrlich melden statt ein stilles 401 zu erzeugen.
      return {'ok': false, 'fehler': 'Nicht angemeldet'};
    }

    try {
      final r = await ApiService().sendChatMessage(
        convId,
        mnr,
        text,
        // Auf demselben Weg zurück, auf dem es hereinkam: eine per SMS
        // gestellte Frage im App-Chat zu beantworten heisst, dass das
        // Mitglied die Antwort nie zu sehen bekommt.
        channel: kanal == 'sms' ? 'sms' : 'app',
      );
      if (r['success'] == true) {
        _sichtbar = false;
        _aktuell = null;
        return {'ok': true};
      }
      return {'ok': false, 'fehler': '${r['message'] ?? 'Senden fehlgeschlagen'}'};
    } catch (e) {
      _log.error('Blitz-Antwort fehlgeschlagen: $e', tag: 'BLITZ');
      return {'ok': false, 'fehler': 'Netzwerkfehler'};
    }
  }

  /// Legt die Karte auf den Bildschirm.
  ///
  /// Gibt `false` zurück, wenn der Blitz NICHT gezeigt wurde — dann muss der
  /// Aufrufer auf die gewöhnliche Benachrichtigung ausweichen, damit die
  /// Nachricht nicht einfach verschwindet.
  Future<bool> zeigen({
    required int conversationId,
    required String absender,
    required String text,
    required String kanal,
    required DateTime zeit,
  }) async {
    try {
      // Gleiche Unterhaltung, Karte steht schon: anhängen statt ersetzen.
      final vorhanden = _aktuell;
      BlitzNachricht neu;
      if (_sichtbar && vorhanden != null && vorhanden.conversationId == conversationId) {
        neu = vorhanden.ergaenztUm(text, zeit);
      } else {
        // ⚠️ ANDERE Unterhaltung, und im Feld steht ein angefangener Satz:
        // Karte in Ruhe lassen. Umschalten würde die halbe Antwort an die
        // falsche Person schicken.
        if (_sichtbar && vorhanden != null && vorhanden.conversationId != conversationId) {
          if (await _hatEntwurf()) {
            _log.info('Blitz übersprungen — Entwurf für andere Unterhaltung offen',
                tag: 'BLITZ');
            return false;
          }
        }
        neu = BlitzNachricht(
          conversationId: conversationId,
          absender: absender,
          zeilen: [text],
          kanal: kanal,
          zeit: zeit,
        );
      }

      if (_fenster == null) {
        _fenster = await WindowController.create(WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: '$kBlitzFensterArgument:${jsonEncode({
                'nachricht': neu.toJson(),
                'dunkel': F.istDunkel,
              })}',
        ));
      } else {
        // ⚠️ ÜBER [kBlitzKanal], NICHT über `_fenster.invokeMethod`.
        // `WindowController.invokeMethod` spricht den paketeigenen Kanal
        // `mixin.one/window_controller/<id>` an, auf dem hier niemand hört —
        // gemessen: die zweite Nachricht derselben Unterhaltung wurde
        // abgelehnt, `_fenster` daraufhin verworfen, und die dritte öffnete
        // ein ZWEITES Blitz-Fenster übereinander.
        await _kanal.invokeMethod(BlitzRuf.zeigen, neu.kodiert());
      }
      _aktuell = neu;
      _sichtbar = true;
      return true;
    } catch (e) {
      _log.error('Blitz-Fenster konnte nicht gezeigt werden: $e', tag: 'BLITZ');
      // ⚠️ `_fenster` wird NICHT verworfen. Das Fenster wird nie geschlossen,
      // nur versteckt; es wegzuwerfen hiess beim nächsten Mal ein zweites zu
      // erzeugen — genau das ist in der Probe passiert, zwei Karten
      // übereinander. Der Aufrufer weicht auf die Benachrichtigung aus.
      _sichtbar = false;
      _aktuell = null;
      return false;
    }
  }

  Future<bool> _hatEntwurf() async {
    try {
      if (_fenster == null) return false;
      return await _kanal.invokeMethod<bool>(BlitzRuf.hatEntwurf) ?? false;
    } catch (_) {
      // Keine Antwort heisst „weiss nicht". Dann lieber nicht umschalten:
      // eine übersprungene Karte kostet einen Klick, eine an die falsche
      // Person geschickte Antwort kostet mehr.
      return true;
    }
  }

  static Map<String, dynamic> _karte(dynamic a) =>
      a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{};

  static int? _alsInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}
