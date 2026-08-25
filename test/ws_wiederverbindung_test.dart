import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/chat_service.dart';

/// 🔴 Der Befund vom 25.08.2026: im Kopf des Live-Chats stand „Offline", und
/// Anruf- und Videoknopf fehlten ganz — beide haengen an derselben Fahne.
///
/// Die Ursache war die abgewiesene Verbindung selbst (siehe
/// `wss_pinning_test.dart`), aber schlimmer war, was DANACH nicht geschah:
/// misslang der Handschlag, stiess niemand einen zweiten Versuch an. `onError`
/// und `onDone` schweigen naemlich, wenn gar nichts erst zustande kommt oder
/// wenn der Server den offenen Draht behaelt und nur die Anmeldung ablehnt.
/// Der Zustand blieb, bis ein Mensch den Dialog neu oeffnete.
///
/// ⚠️ Geprueft wird gegen einen WebSocket-Server auf `localhost`, nicht gegen
/// das Netz. Ein Test, der ohne Leitung rot wird, sagt am Ende nichts mehr.
void main() {
  late HttpServer server;
  late List<WebSocket> verbindungen;
  late List<Map<String, dynamic>> empfangen;

  /// Wie oft der Server die Anmeldung noch ablehnen soll, bevor er sie annimmt.
  late int nochAblehnen;

  setUp(() async {
    verbindungen = [];
    empfangen = [];
    nochAblehnen = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((anfrage) async {
      final ws = await WebSocketTransformer.upgrade(anfrage);
      verbindungen.add(ws);
      ws.listen((roh) {
        final data = jsonDecode(roh as String) as Map<String, dynamic>;
        empfangen.add(data);
        if (data['type'] != 'auth') return;
        if (nochAblehnen > 0) {
          nochAblehnen--;
          // Genau der Fall aus dem Betrieb: der Draht bleibt offen, nur die
          // Anmeldung faellt durch. Der Server schliesst NICHT.
          ws.add(jsonEncode(
              {'type': 'auth_error', 'error': 'Authentication required'}));
        } else {
          ws.add(jsonEncode({
            'type': 'auth_success',
            'user_id': 2,
            'name': 'I. C. Duinea',
            'role': 'vorsitzer',
            'is_admin': true,
          }));
        }
      }, onError: (_) {}, cancelOnError: true);
    });
    ChatService.testWsUrl = 'ws://127.0.0.1:${server.port}/';
  });

  tearDown(() async {
    ChatService().disconnect();
    ChatService.testWsUrl = null;
    for (final ws in verbindungen) {
      await ws.close().catchError((_) => null);
    }
    await server.close(force: true);
  });

  test('eine abgelehnte Anmeldung stoesst einen neuen Versuch an', () async {
    nochAblehnen = 99; // nimmt sie nie an
    final ergebnis = await ChatService().connect('V27655');

    expect(ergebnis, isFalse, reason: 'die Anmeldung wurde abgelehnt');
    // Der Kern des Befunds: vorher wartete hier NICHTS, und der Kopf blieb
    // bis zum naechsten Oeffnen des Dialogs auf „Offline".
    expect(ChatService().wiederverbindungWartet, isTrue);
    expect(ChatService().versucheBisher, 1,
        reason: 'eine Stoerung darf genau einen der zehn Versuche kosten');
  });

  test('der abgelehnte Draht bleibt nicht offen liegen', () async {
    nochAblehnen = 99;
    await ChatService().connect('V27655');
    // Bis zu einer Sekunde Luft: das Schliessen laeuft ueber die Leitung.
    for (var i = 0; i < 20 && verbindungen.first.closeCode == null; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    expect(verbindungen.first.closeCode, isNotNull,
        reason: 'sonst sammelt jeder misslungene Versuch einen toten Socket an');
  });

  test('der naechste Versuch heilt die Verbindung von allein', () async {
    // Einmal ablehnen, danach annehmen — wie ein abgelaufenes Token, das vor
    // dem zweiten Anlauf erneuert wird.
    nochAblehnen = 1;
    final ersterVersuch = await ChatService().connect('V27655');
    expect(ersterVersuch, isFalse);

    final verbunden = Completer<bool>();
    final horcher = ChatService().connectionStream.listen((an) {
      if (an && !verbunden.isCompleted) verbunden.complete(true);
    });
    // Der erste Abstand betraegt zwei Sekunden.
    await expectLater(
      verbunden.future.timeout(const Duration(seconds: 12)),
      completion(isTrue),
    );
    await horcher.cancel();
    expect(ChatService().versucheBisher, 0, reason: 'nach Erfolg zurueckgesetzt');
    expect(empfangen.where((e) => e['type'] == 'auth').length, 2,
        reason: 'genau zwei Anmeldungen: die abgelehnte und die geglueckte');
  }, timeout: const Timeout(Duration(seconds: 30)));

  test('ein Aufruf von aussen laeuft den Zaehler nicht voll', () async {
    // Nach zehn verbuchten Versuchen gibt `_scheduleReconnect` endgueltig auf
    // und setzt `_shouldReconnect` auf falsch — der Chat waere dann bis zum
    // Neustart der Anwendung offline. Ein Aufruf von aussen heisst „jemand
    // will JETZT verbunden sein" und faengt darum von vorn an.
    nochAblehnen = 99;
    await ChatService().connect('V27655');
    expect(ChatService().versucheBisher, 1);

    for (var i = 0; i < 5; i++) {
      await ChatService().connect('V27655');
    }
    // Nicht 6: jeder Aufruf setzt zurueck, und ein bereits wartender Versuch
    // wird nicht doppelt verbucht.
    expect(ChatService().versucheBisher, lessThanOrEqualTo(1),
        reason: 'sonst waere die Grenze von zehn nach fuenf Klicks erreicht');
    expect(ChatService().wiederverbindungWartet, isTrue,
        reason: 'und es wartet weiterhin einer');
  });

  test('disconnect laesst keinen wartenden Versuch zurueck', () async {
    nochAblehnen = 99;
    await ChatService().connect('V27655');
    expect(ChatService().wiederverbindungWartet, isTrue);
    ChatService().disconnect();
    expect(ChatService().wiederverbindungWartet, isFalse,
        reason: 'ein liegengebliebener Zeitgeber weckt eine geschlossene App');
  });
}
