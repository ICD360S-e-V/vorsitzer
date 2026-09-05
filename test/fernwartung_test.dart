import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/remote_control_screen.dart';
import 'package:icd360sev_vorsitzer/services/chat_service.dart';
import 'package:icd360sev_vorsitzer/services/remote_control_service.dart';

/// Prueft die Fernwartungs-Reparaturen auf der Vorsitzer-Seite.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Nach einer Wiederverbindung wird der Raum erneut betreten', () {
    late HttpServer server;
    late List<WebSocket> verbindungen;
    late List<Map<String, dynamic>> empfangen;

    setUp(() async {
      verbindungen = [];
      empfangen = [];
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((anfrage) async {
        final ws = await WebSocketTransformer.upgrade(anfrage);
        verbindungen.add(ws);
        ws.listen((roh) {
          final data = jsonDecode(roh as String) as Map<String, dynamic>;
          empfangen.add(data);
          if (data['type'] == 'auth') {
            ws.add(jsonEncode({'type': 'auth_success', 'user_id': 2}));
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

    /// 🔴 Der Beitritt haengt am SOCKET. Nach einer Wiederverbindung war das
    /// Geraet in keinem Raum mehr — Anrufsignale, ICE und Fernwartung fielen
    /// stumm aus, waehrend der Bildschirm weiter „verbunden" zeigte.
    test('der gemerkte Raum wird nach dem Abriss erneut betreten', () async {
      expect(await ChatService().connect('V10001'), isTrue);
      ChatService().joinConversation(19);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      empfangen.clear();

      await verbindungen.first.close();
      await Future<void>.delayed(const Duration(seconds: 3));

      expect(ChatService().isConnected, isTrue);
      expect(
        empfangen.where((m) => m['type'] == 'join' && m['conversation_id'] == 19).length,
        1,
        reason: 'ohne erneuten Beitritt erreicht kein ICE mehr die Gegenseite',
      );
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('ein verlassener Raum wird nicht erneut betreten', () async {
      await ChatService().connect('V10001');
      ChatService().joinConversation(19);
      ChatService().leaveConversation(19);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      empfangen.clear();

      await verbindungen.first.close();
      await Future<void>.delayed(const Duration(seconds: 3));
      expect(empfangen.where((m) => m['type'] == 'join'), isEmpty);
    }, timeout: const Timeout(Duration(seconds: 30)));
  });

  group('Steuerbarkeit meldet das Mitglied, nicht der Vorsitz', () {
    test('remote_answer traegt plattform und steuerung', () {
      final e = RemoteAnswerEvent(
        conversationId: 19,
        answererId: '13',
        sdp: 'v=0',
        sdpType: 'answer',
        plattform: 'android',
        steuerung: true,
      );
      expect(e.plattform, 'android');
      expect(e.steuerung, isTrue);
    });

    /// ⚠️ Eine aeltere Mitglieds-App schickt beides nicht mit. Dann gilt
    /// „nicht steuerbar" — lieber Ansicht anzeigen und sich korrigieren, als
    /// Steuerung versprechen und Klicks ins Leere laufen lassen.
    test('ohne Angabe gilt: nicht steuerbar', () {
      final e = RemoteAnswerEvent(
        conversationId: 19,
        answererId: '13',
        sdp: 'v=0',
        sdpType: 'answer',
      );
      expect(e.steuerung, isFalse);
      expect(e.plattform, isNull);
    });
  });

  group('Rueckweg zu einer laufenden Sitzung', () {
    tearDown(FernwartungRueckkehr.vergessen);

    /// 🔴 Vorher riss `dispose()` die Sitzung ab — der Schritt zurueck in den
    /// Chat, um dem Mitglied zu schreiben, beendete die Fernwartung. Jetzt
    /// laeuft sie weiter, und genau deshalb MUSS es einen Rueckweg geben.
    test('ohne laufende Sitzung gibt es keinen Rueckweg', () {
      FernwartungRueckkehr.merken(const RemoteControlScreen(
        conversationId: 19,
        targetUserId: 'M10002',
        targetName: 'Testmitglied',
        controllerMitgliedernummer: 'V10001',
      ));
      // Der Dienst ruht — also darf der Knopf nicht „zurueck" anbieten.
      expect(RemoteControlService().state, RemoteControlState.idle);
      expect(FernwartungRueckkehr.laeuft, isFalse);
    });

    test('vergessen loescht den Rueckweg', () {
      FernwartungRueckkehr.merken(const RemoteControlScreen(
        conversationId: 19,
        targetUserId: 'M10002',
        targetName: 'Testmitglied',
        controllerMitgliedernummer: 'V10001',
      ));
      FernwartungRueckkehr.vergessen();
      expect(FernwartungRueckkehr.laeuft, isFalse);
    });
  });

  group('Systemtasten', () {
    /// Auf einem Telefon mit Gestennavigation gibt es keine Flaeche zum
    /// Anklicken. Ohne diese Rahmen kaeme der Vorsitz aus jeder geoeffneten
    /// App nicht mehr heraus.
    test('sendSystemAktion ist ohne offenen Datenkanal still', () {
      // Kein Kanal offen -> _sendInput steigt aus, kein Absturz.
      expect(() => RemoteControlService().sendSystemAktion('home'), returnsNormally);
      expect(RemoteControlService().canSendInput, isFalse);
    });
  });
}
