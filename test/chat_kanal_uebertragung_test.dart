import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/chat_service.dart';
import 'package:icd360sev_vorsitzer/utils/chat_message_merge.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_header.dart';

/// ⚠️ `chat_kanal_tabs_test.dart` prüft, ob eine Nachricht **mit** Kanal
/// richtig einsortiert wird. Genau das war nie das Problem. Das Problem war,
/// dass der Kanal auf dem Weg vom Server zur Blase **verloren ging** — und ein
/// Test, der sich seine Eingabe selbst baut, kann das prinzipiell nicht sehen.
///
/// Drei Stellen ließen ihn fallen, jede für sich ausreichend, um jede SMS im
/// App-Chat landen zu lassen:
///
/// 1. `api/chat/messages.php` las `m.channel` in der Abfrage mit, schrieb ihn
///    aber nicht ins Antwort-Array. Jede **neu geladene** Nachricht kam
///    kanallos an. Sichtbar wurde das erst beim zweiten Öffnen des Dialogs:
///    frisch verschickt stimmte es, nach dem Neuladen sprang der gesamte
///    SMS-Verlauf in den App-Chat.
/// 2. [ChatMessage] hatte kein Feld `channel`. `sms_inbox.php` schickt den
///    Schlüssel im WebSocket-Rundruf seit jeher mit — gelesen hat ihn niemand.
///    Die Antwort des Mitglieds erschien also live im App-Chat.
/// 3. Der Rundruf des eigenen Sendens trug ihn nicht weiter, also sah das
///    zweite Vorsitzer-Gerät dieselbe SMS im falschen Verlauf.
///
/// Die Fälle hier hängen deshalb an den **echten Nutzlasten** der drei Wege,
/// nicht an selbst erfundenen Maps.
void main() {
  group('WebSocket-Rundruf', () {
    // Wortlaut aus api/chat/sms_inbox.php: die SMS, die ein Mitglied an die
    // SIM des Vereins-Tablets geschickt hat.
    Map<String, dynamic> eingehendeSms() => {
          'type': 'new_message',
          'message_id': 28401,
          'conversation_id': 35,
          'sender_id': 72,
          'sender_role': 'member',
          'is_admin': false,
          'message': 'Buna ziua, am primit mesajul',
          'channel': 'sms',
          'created_at': '2026-08-24 19:02:11',
        };

    test('eine eingegangene SMS behält ihren Kanal', () {
      final m = ChatMessage.fromJson(eingehendeSms());
      expect(m.channel, 'sms');
      // Und sie muss auch die Strecke bis zur Einsortierung überstehen — das
      // ist der Schritt, den der Dialog geht.
      expect(chatKanalVon({'id': m.id, 'channel': m.channel}), ChatChannel.sms);
    });

    test('eine gewöhnliche App-Nachricht bleibt App', () {
      final json = eingehendeSms()..['channel'] = 'app';
      expect(ChatMessage.fromJson(json).channel, 'app');
    });

    test('fehlender Schlüssel heißt App, nicht SMS', () {
      // Der gesamte Verlauf von vor der Kanaltrennung und jeder ältere
      // Rundruf kommen ohne den Schlüssel. Als SMS gewertet stünden sie im
      // SMS-Tab, wo nie ein Segment bezahlt wurde.
      final json = eingehendeSms()..remove('channel');
      expect(ChatMessage.fromJson(json).channel, 'app');
    });

    test('unbekannte Werte gelten als App', () {
      for (final wert in ['SMS', 'whatsapp', '', 'sms ']) {
        final json = eingehendeSms()..['channel'] = wert;
        expect(ChatMessage.fromJson(json).channel, 'app',
            reason: 'channel="$wert" darf nicht als SMS durchgehen');
      }
    });
  });

  group('Antwort von messages.php', () {
    /// Nachgebaut nach dem Ausgabe-Array von `api/chat/messages.php` — samt
    /// der Felder, die dort tatsächlich stehen. Genau diese Form kommt beim
    /// Neuladen an, und genau hier fehlte `channel`.
    Map<String, dynamic> serverZeile({required String channel}) => {
          'id': 28400,
          'message': 'Guten Abend, wir brauchen Ihre E-Mail-Adresse',
          'original_message': null,
          'is_translated': false,
          'sender_id': 2,
          'sender_name': 'I. Duinea',
          'sender_role': 'vorsitzer',
          'is_own': true,
          'is_read': false,
          'status': 'sent',
          'delivered_at': null,
          'read_at': null,
          'expires_at': null,
          'deleted_at': null,
          'created_at': '2026-08-24 18:55:57',
          'reaction': null,
          'channel': channel,
          'attachments': const [],
        };

    test('eine gespeicherte SMS kommt als SMS zurück', () {
      expect(chatKanalVon(serverZeile(channel: 'sms')), ChatChannel.sms);
    });

    test('das Neuladen wirft eine SMS nicht mehr in den App-Chat', () {
      // Der Ablauf, an dem es scheiterte: verschickt (optimistisch, mit
      // Kanal), danach neu geladen. Fehlte `channel` in der Serverantwort,
      // blieb die Zeile zwar erhalten — aber jede Zeile, die der Client noch
      // nicht kannte, kam kanallos und landete im App-Chat.
      final vorhanden = <Map<String, dynamic>>[
        {'id': 28400, 'message': '…', 'channel': 'sms', 'is_own': true},
      ];
      final vomServer = <Map<String, dynamic>>[
        serverZeile(channel: 'sms'),
        // Die Antwort des Mitglieds, die der Client noch nie gesehen hat.
        {...serverZeile(channel: 'sms'), 'id': 28401, 'is_own': false},
      ];

      final zusammen = chatNachrichtenZusammenfuehren(vorhanden, vomServer);

      expect(zusammen, hasLength(2));
      expect(zusammen.every((m) => chatKanalVon(m) == ChatChannel.sms), isTrue,
          reason: 'beide Zeilen gehören in den SMS-Verlauf');
    });

    test('der Server gewinnt, wenn er den Kanal kennt', () {
      // Vor der Reparatur war `channel` ein rein lokales Feld, das der Server
      // nie überschrieb. Jetzt ist er die Quelle — sonst bliebe eine falsch
      // geratene lokale Zuordnung für immer stehen.
      final vorhanden = <Map<String, dynamic>>[
        {'id': 28400, 'channel': 'app'},
      ];
      final zusammen = chatNachrichtenZusammenfuehren(
          vorhanden, [serverZeile(channel: 'sms')]);

      expect(chatKanalVon(zusammen.single), ChatChannel.sms);
    });
  });
}
