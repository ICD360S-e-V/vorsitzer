/// Schickt den Ton der Gegenstelle an unseren Erkenner und holt den Text.
///
/// WOZU. Auf dem Tablet läuft `vosk-model-small-de-0.15` (45 MB). Am
/// Telefonband gemessen — 300–3400 Hz, µ-law hin und zurück, also genau die
/// Bedingung eines Anrufs — liegt es bei **17,6 % Wortfehlern**; das grosse
/// `vosk-model-de-0.21` bei **0,0 %**. Es braucht aber 4,4 GB Arbeitsspeicher
/// und ist auf einem Tablet nicht zu betreiben; auf unserem Server sind es
/// 10 % des freien Speichers und 12 % eines Kerns.
///
/// ⚠️ DER TON VERLÄSST DAMIT DAS GERÄT — und das ist eine bewusste
/// Entscheidung des Users. Sie ist kleiner, als sie klingt: das Gespräch ist
/// VoIP und läuft ohnehin über die Server von sipgate, einer fremden Firma.
/// Hier geht eine Kopie an den eigenen Rechner des Vereins.
///
/// ⚠️ GESPEICHERT WIRD NICHTS — weder hier, noch unterwegs, noch dort. Der Ton
/// geht durch den Erkenner und ist weg; der Text steht auf dem Schirm und ist
/// mit dem Gespräch weg. Dieselbe Zusage wie beim Erkennen auf dem Gerät.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'api_service.dart';
import 'logger_service.dart';
import '../utils/mitschrift_sprachen.dart';

final _log = LoggerService();

/// Wie lange auf den Aufbau gewartet wird, bevor auf das Gerät zurückgefallen
/// wird.
///
/// ⚠️ Kurz, und das mit Absicht: unsere eigenen Speedtest-Messungen zeigen auf
/// dieser Leitung Latenzspitzen bis 7.402 ms und Tage unter 2 Mbit/s. Wer
/// zwanzig Sekunden auf den Server wartet, hat in dieser Zeit gar keine
/// Mitschrift — schlechter Text ist besser als keiner.
const Duration kStromAufbauFrist = Duration(seconds: 6);

class UntertitelStrom {
  UntertitelStrom({
    required this.aufText,
    required this.aufAbbruch,
    this.sprache = kMitschriftStandard,
  });

  /// Welches Modell der Server nehmen soll — `de`, `en` oder `ro`.
  ///
  /// ⚠️ Ein SCHLÜSSEL, kein Pfad. Der Server schlägt ihn in einer eigenen
  /// Tabelle nach; kennt er ihn nicht, weist er die Verbindung ab. Der
  /// Vorgänger dieses Servers (aus dem vosk-server-Projekt) nahm vom Client
  /// stattdessen `{"model": "<pfad>"}` entgegen — dann bestimmt der Client,
  /// was geladen wird.
  final String sprache;

  /// `art` ist `teil` (im Satz) oder `satz` (fertig) — dieselben Namen wie
  /// beim Erkennen auf dem Gerät, damit die Anzeige nichts unterscheiden muss.
  final void Function(String art, String text) aufText;

  /// Wird gerufen, wenn die Strecke abreisst. Der Aufrufer schaltet dann auf
  /// das Modell im Gerät um.
  final void Function(String grund) aufAbbruch;

  // Der Draht lebt so lange wie das Gespräch und wird in [beenden]
  // geschlossen; die Prüfung sieht nur den Aufbau in `starten`.
  // ignore: close_sinks
  WebSocket? _draht;
  bool _offen = false;
  int _gesendet = 0;

  bool get laeuft => _offen;

  /// Baut die Strecke auf. Gibt den Grund zurück, wenn es nicht ging.
  Future<String?> starten() async {
    try {
      // ⚠️ Erst der Einmal-Schlüssel, dann die Verbindung. Der Erkenner prüft
      // keine Kopfzeilen — ein Dart-WebSocket kann sich beim Verbinden nicht
      // darauf verlassen, dass sie ankommen —, deshalb wird die Anmeldung
      // vorher über die normale API gemacht und nur ein kurzlebiger Nachweis
      // weitergereicht.
      final a = await ApiService().asrToken();
      if (a['success'] != true) {
        return 'Erkennung nicht verfügbar (${a['message'] ?? 'kein Schlüssel'})';
      }
      final token = '${a['token'] ?? ''}';
      final pfad = '${a['pfad'] ?? '/asr/'}';
      if (token.isEmpty) return 'Kein Schlüssel erhalten';

      final url = ApiService.baseUrl
              .replaceFirst(RegExp(r'^https', caseSensitive: false), 'wss')
              .replaceFirst(RegExp(r'/api/?$'), '') +
          pfad;

      _draht = await WebSocket.connect(url).timeout(kStromAufbauFrist);
      _draht!.add(jsonEncode({'token': token, 'sprache': sprache}));
      _offen = true;
      _gesendet = 0;

      _draht!.listen(
        (nachricht) {
          if (nachricht is! String) return;
          try {
            final m = jsonDecode(nachricht) as Map<String, dynamic>;
            final art = '${m['art'] ?? ''}';
            final text = '${m['text'] ?? ''}';
            if (text.isNotEmpty && (art == 'teil' || art == 'satz')) {
              aufText(art, text);
            }
          } catch (_) {
            // Eine unlesbare Zeile ist kein Grund, das Gespräch zu stören.
          }
        },
        onDone: () {
          final war = _offen;
          _offen = false;
          if (!war) return;
          // ⚠️ 1003 ist die EINE Absage, die einen eigenen Satz verdient: der
          // Server hat kein Modell für diese Sprache. Ohne die Unterscheidung
          // stünde dort „Verbindung beendet", und man suchte den Fehler im
          // Netz statt in der Sprachwahl.
          aufAbbruch(_draht?.closeCode == 1003
              ? 'Für diese Sprache gibt es kein Modell auf dem Server.'
              : 'Verbindung zum Erkenner beendet');
        },
        onError: (Object e) {
          final war = _offen;
          _offen = false;
          if (war) aufAbbruch('$e');
        },
        cancelOnError: true,
      );
      _log.info('Untertitel: Erkennung auf dem Server verbunden',
          tag: 'UNTERTITEL');
      return null;
    } on TimeoutException {
      await beenden();
      return 'Der Erkenner antwortet nicht.';
    } catch (e) {
      await beenden();
      return '$e';
    }
  }

  /// Ein Stück Ton — 16-bit-PCM, 16 kHz, mono.
  void ton(List<int> pcm) {
    final d = _draht;
    if (!_offen || d == null || pcm.isEmpty) return;
    try {
      d.add(pcm);
      _gesendet += pcm.length;
    } catch (e) {
      _offen = false;
      aufAbbruch('$e');
    }
  }

  Future<void> beenden() async {
    final d = _draht;
    _draht = null;
    if (!_offen) {
      try {
        await d?.close();
      } catch (_) {}
      return;
    }
    _offen = false;
    try {
      // ⚠️ Erst das Ende ansagen, dann schliessen: sonst geht der letzte,
      // noch nicht abgeschlossene Satz verloren — und das ist meistens der,
      // den man gerade lesen wollte.
      d?.add('{"eof":1}');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      await d?.close();
    } catch (_) {}
    _log.info('Untertitel: Erkennung auf dem Server beendet '
        '(${(_gesendet / 1024).round()} kB Ton)', tag: 'UNTERTITEL');
  }
}
