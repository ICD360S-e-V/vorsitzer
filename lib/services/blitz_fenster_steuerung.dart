import 'dart:async';
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
///
/// ⚠️ SCHREIBEN ZWEI GLEICHZEITIG, GEHT KEINER VERLOREN.
/// Die Karte zeigt einen nach dem anderen; wer warten muss, steht als Zähler
/// („noch 1") in der Karte und rückt nach, sobald der erste beantwortet oder
/// weggelegt ist. Die Karte NICHT unter den Fingern umzuschalten ist Absicht:
/// sonst ginge eine halb geschriebene Antwort an die falsche Person.
class BlitzFensterSteuerung {
  BlitzFensterSteuerung._();
  static final BlitzFensterSteuerung instanz = BlitzFensterSteuerung._();

  static const _kanal = WindowMethodChannel(kBlitzKanal);
  final _log = LoggerService();

  WindowController? _fenster;
  BlitzNachricht? _aktuell;
  bool _sichtbar = false;

  /// Wer warten muss, in Ankunftsreihenfolge. Höchstens eine Zeile je
  /// Unterhaltung — ein zweiter Satz derselben Person wird an ihre wartende
  /// Nachricht angehängt, statt eine zweite Wartemarke zu erzeugen.
  final List<BlitzNachricht> _warteschlange = [];

  /// ⚠️ Alle Zugriffe laufen NACHEINANDER durch diese Kette.
  ///
  /// Ohne sie gab es eine echte Wettlaufsituation: `WindowController.create`
  /// ist asynchron, `_fenster` wird erst danach gesetzt. Trafen zwei
  /// Nachrichten in derselben Sekunde ein, sah die zweite noch `null` und
  /// baute ein ZWEITES Fenster — auf dem bidirektionalen Kanal ist das der
  /// dritte Teilnehmer, also scheiterte es, und die zweite Nachricht fiel auf
  /// die gewöhnliche Benachrichtigung zurück, die von selbst verschwindet.
  /// Genau das war „bei zwei Absendern sieht man nur den ersten".
  Future<void> _kette = Future.value();

  /// Wird gerufen, wenn im Blitz-Fenster „im Chat öffnen" gedrückt wurde.
  void Function(int conversationId)? onImChatOeffnen;

  /// Wird gerufen, nachdem aus der Karte heraus geantwortet wurde.
  ///
  /// ⚠️ Damit der ungelesen-Zähler im Kopf mitbekommt, dass die Unterhaltung
  /// erledigt ist. Er zählte sonst weiter hoch, WÄHREND man antwortete, und
  /// beim Antippen war dann keine einzige Nachricht da — auf dem Server
  /// längst gelesen, nur diese Zahl wusste nichts davon.
  ///
  /// ⚠️ Absichtlich ein direkter Rückruf und nicht nur der WebSocket-Nachhall
  /// der eigenen Nachricht: der Nachhall kommt zwar an, aber er ist der
  /// Umweg über das Netz. Fällt er einmal aus, bliebe die Zahl stehen.
  void Function(int conversationId)? onBeantwortet;

  bool get sichtbar => _sichtbar;
  int get wartend => _warteschlange.length;

  Future<void> bereitmachen() async {
    await _kanal.setMethodCallHandler(_ruf);
  }

  Future<T> _nacheinander<T>(Future<T> Function() arbeit) {
    final naechste = _kette.then((_) => arbeit());
    _kette = naechste.then((_) {}, onError: (_) {});
    return naechste;
  }

  Future<dynamic> _ruf(MethodCall ruf) async {
    switch (ruf.method) {
      case BlitzRuf.senden:
        return _senden(ruf.arguments);
      case BlitzRuf.schliessen:
      case BlitzRuf.weiter:
        return _nacheinander(_nachruecken);
      case BlitzRuf.imChatOeffnen:
        final id = _alsInt(_karte(ruf.arguments)['conversation_id']);
        if (id != null) onImChatOeffnen?.call(id);
        return _nacheinander(_nachruecken);
      default:
        return null;
    }
  }

  /// Erledigte Karte weglegen und die nächste wartende nachziehen.
  Future<bool> _nachruecken() async {
    _aktuell = null;
    if (_warteschlange.isEmpty) {
      _sichtbar = false;
      return true;
    }
    final naechste = _warteschlange.removeAt(0);
    return _hinlegen(naechste);
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
        await _alsGelesenMarkieren(convId, mnr);
        onBeantwortet?.call(convId);
        return {'ok': true};
      }
      return {'ok': false, 'fehler': '${r['message'] ?? 'Senden fehlgeschlagen'}'};
    } catch (e) {
      _log.error('Blitz-Antwort fehlgeschlagen: $e', tag: 'BLITZ');
      return {'ok': false, 'fehler': 'Netzwerkfehler'};
    }
  }

  /// Wer aus der Karte heraus antwortet, hat gelesen.
  ///
  /// ⚠️ Ohne das wuchs der ungelesen-Zähler ins Endlose, WÄHREND man
  /// antwortete. Gemessen am 26.08.2026 in Unterhaltung 21 — ein Hin und Her
  /// über mehrere Minuten, und jede eingehende Zeile blieb auf `sent`:
  ///
  ///   29360 MITGLIED sent  23:40:28
  ///   29358 ICH      read  23:40:08   ← hier wurde geantwortet
  ///   29357 MITGLIED sent  23:40:02
  ///   29355 ICH      read  23:39:15   ← und hier
  ///
  /// Als gelesen markiert wurde bis dahin nur beim ÖFFNEN des Chatfensters,
  /// beim Tippen darin und beim Kanalwechsel. Die Karte ist aber ein
  /// vollwertiger Antwortweg — wer sie benutzt, öffnet das Fenster nie.
  ///
  /// ⚠️ OHNE Nachrichten-IDs, also die ganze Unterhaltung. Nur die auf der
  /// Karte sichtbaren Zeilen zu stempeln (höchstens fünf) liesse bei zwölf
  /// ungelesenen sieben stehen — und damit genau das rote Abzeichen, um das
  /// es hier geht.
  ///
  /// ⚠️ Preis dieser Entscheidung: der Server unterscheidet dabei nicht nach
  /// Kanal. Hat dieselbe Person zusätzlich eine SMS geschickt, gilt auch die
  /// als gelesen. Im Chatfenster wird bewusst anders entschieden (nur der
  /// sichtbare Kanal) — dort sieht man ja, welcher Verlauf offen ist; hier
  /// nicht.
  ///
  /// Schlägt es fehl, ist das KEIN Fehler der Antwort: die Nachricht ist
  /// heraus, nur das Abzeichen bleibt stehen. Deshalb nur ins Protokoll.
  Future<void> _alsGelesenMarkieren(int convId, String mnr) async {
    try {
      await ApiService().markMessagesRead(
        conversationId: convId,
        mitgliedernummer: mnr,
        status: 'read',
      );
    } catch (e) {
      _log.warning('Blitz: als gelesen markieren fehlgeschlagen: $e', tag: 'BLITZ');
    }
  }

  /// Legt die Karte auf den Bildschirm — oder stellt sie an, wenn gerade eine
  /// andere Unterhaltung offen ist.
  ///
  /// Gibt `false` zurück, wenn der Blitz gar nicht möglich war; dann weicht
  /// der Aufrufer auf die gewöhnliche Benachrichtigung aus.
  Future<bool> zeigen({
    required int conversationId,
    required String absender,
    String? nummer,
    required String text,
    required String kanal,
    required DateTime zeit,
  }) =>
      _nacheinander(
          () => _zeigen(conversationId, absender, nummer, text, kanal, zeit));

  Future<bool> _zeigen(int conversationId, String absender, String? nummer,
      String text, String kanal, DateTime zeit) async {
    try {
      return await _zeigenRoh(
          conversationId, absender, nummer, text, kanal, zeit);
    } catch (e) {
      // ⚠️ Nichts darf hier hinausfliegen. `melden()` ruft ohne `await`; eine
      // Ausnahme landete sonst als unbehandelter Fehler im Protokoll, und der
      // Aufrufer erführe nie, dass er auf die Benachrichtigung ausweichen
      // muss.
      _log.error('Blitz fehlgeschlagen: $e', tag: 'BLITZ');
      return false;
    }
  }

  Future<bool> _zeigenRoh(
      int conversationId, String absender, String? nummer, String text, String kanal, DateTime zeit) async {
    final vorhanden = _aktuell;

    // Dieselbe Unterhaltung liegt schon vorn: anhängen statt ersetzen.
    if (_sichtbar && vorhanden != null && vorhanden.conversationId == conversationId) {
      return _hinlegen(vorhanden.ergaenztUm(text, zeit));
    }

    final neu = BlitzNachricht(
      conversationId: conversationId,
      absender: absender,
      nummer: nummer,
      zeilen: [text],
      kanal: kanal,
      zeit: zeit,
    );

    // Eine ANDERE Unterhaltung, während vorn schon eine liegt: anstellen.
    if (_sichtbar && vorhanden != null) {
      final i = _warteschlange.indexWhere((w) => w.conversationId == conversationId);
      if (i >= 0) {
        // Schon in der Schlange — an ihre Nachricht anhängen, keine zweite
        // Wartemarke für dieselbe Person.
        _warteschlange[i] = _warteschlange[i].ergaenztUm(text, zeit);
      } else {
        _warteschlange.add(neu);
      }
      // Die vorne liegende Karte über den neuen Zähler in Kenntnis setzen.
      await _schieben(vorhanden);
      return true;
    }

    return _hinlegen(neu);
  }

  /// Karte nach vorn legen (erzeugt das Fenster beim ersten Mal).
  Future<bool> _hinlegen(BlitzNachricht n) async {
    try {
      _aktuell = n;
      if (_fenster == null) {
        _fenster = await WindowController.create(WindowConfiguration(
          hiddenAtLaunch: true,
          arguments: '$kBlitzFensterArgument:${jsonEncode({
                'nachricht': n.toJson(),
                'wartend': _warteschlange.length,
                'dunkel': F.istDunkel,
              })}',
        ));
      } else {
        await _schieben(n);
      }
      _sichtbar = true;
      return true;
    } catch (e) {
      _log.error('Blitz-Fenster konnte nicht gezeigt werden: $e', tag: 'BLITZ');
      // ⚠️ `_fenster` wird NICHT verworfen. Das Fenster wird nie geschlossen,
      // nur versteckt; es wegzuwerfen hiesse beim nächsten Mal ein zweites zu
      // erzeugen. Der Aufrufer weicht auf die Benachrichtigung aus.
      _sichtbar = false;
      _aktuell = null;
      return false;
    }
  }

  /// ⚠️ ÜBER [kBlitzKanal], NICHT über `_fenster.invokeMethod`.
  /// `WindowController.invokeMethod` spricht den paketeigenen Kanal
  /// `mixin.one/window_controller/<id>` an, auf dem hier niemand hört.
  ///
  /// ⚠️ MIT GEDULD, und das ist kein Schmuck. Das Blitz-Fenster meldet sich
  /// erst auf dem Kanal an, wenn seine Engine hochgefahren ist — das dauert
  /// rund eine Sekunde. Wer in dieser Zeit schiebt, bekommt
  /// `CHANNEL_UNREGISTERED`. Gemessen mit drei Absendern in derselben
  /// Sekunde: die zweite Nachricht warf eine unbehandelte Ausnahme und war
  /// weg — also genau der gemeldete Fehler, nur eine Ebene tiefer.
  Future<void> _schieben(BlitzNachricht n) async {
    final nutzlast =
        jsonEncode({'nachricht': n.toJson(), 'wartend': _warteschlange.length});
    for (var versuch = 0; versuch < 25; versuch++) {
      try {
        await _kanal.invokeMethod(BlitzRuf.zeigen, nutzlast);
        return;
      } on WindowChannelException {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    // Nach drei Sekunden ist etwas grundsätzlich falsch. Die Nachricht selbst
    // ist nicht verloren — sie steht in der Schlange bzw. ist `_aktuell`.
    _log.warning('Blitz-Fenster meldet sich nicht auf dem Kanal', tag: 'BLITZ');
  }

  static Map<String, dynamic> _karte(dynamic a) =>
      a is Map ? Map<String, dynamic>.from(a) : <String, dynamic>{};

  static int? _alsInt(dynamic v) =>
      v is int ? v : (v is num ? v.toInt() : int.tryParse('$v'));
}
