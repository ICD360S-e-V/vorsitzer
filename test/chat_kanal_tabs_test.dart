import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_header.dart';

/// Die Leiste über der Konversation trennt zwei Unterhaltungen: was in der App
/// steht und was über die SIM ging. Vorher war das ein Schalter für die
/// *nächste* Nachricht, und beide Verläufe standen vermischt untereinander —
/// man sah einer Nachricht nicht an, auf welchem Weg sie gekommen war.
///
/// 19 der 42 Mitglieder haben in Verifizierung Stufe 1 gar keine Rufnummer.
/// Für sie MUSS „SMS nicht verfügbar" sichtbar dastehen: ein still fehlender
/// Tab sähe wie ein Fehler aus, und ein stilles Ausweichen auf die App wäre
/// schlimmer — der Vorsitzer glaubte dann, eine SMS verschickt zu haben.
void main() {
  Future<void> zeige(
    WidgetTester tester,
    Map<String, dynamic> conversation, {
    ChatChannel channel = ChatChannel.app,
    ValueChanged<ChatChannel>? onChanged,
    int ungeleseneApp = 0,
    int ungeleseneSms = 0,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ChatKanalTabs(
          conversation: conversation,
          channel: channel,
          onChanged: onChanged ?? (_) {},
          ungeleseneApp: ungeleseneApp,
          ungeleseneSms: ungeleseneSms,
        ),
      ),
    ));
  }

  Map<String, dynamic> mitglied({String? telefon}) => {
        'id': 7,
        'mitgliedernummer': 'M12345',
        'member_id': 7,
        'status': 'open',
        'telefon_mobil': telefon,
      };

  group('Kanaltabs App-Chat | SMS', () {
    testWidgets('mit Mobilnummer stehen beide Verläufe zur Wahl', (tester) async {
      await zeige(tester, mitglied(telefon: '0176 1234567'));

      expect(find.text('App-Chat'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
      expect(find.text('SMS nicht verfügbar'), findsNothing);
    });

    testWidgets('ohne Rufnummer wird SMS ausdrücklich als nicht verfügbar '
        'angezeigt, nicht weggelassen', (tester) async {
      await zeige(tester, mitglied(telefon: null));

      expect(find.text('App-Chat'), findsOneWidget);
      expect(find.text('SMS nicht verfügbar'), findsOneWidget);
      expect(find.text('SMS'), findsNothing);
    });

    testWidgets('Festnetz zählt wie keine Nummer — dorthin kommt seit 2023 '
        'keine SMS mehr an', (tester) async {
      await zeige(tester, mitglied(telefon: '0711 123456'));

      expect(find.text('SMS nicht verfügbar'), findsOneWidget);
    });

    testWidgets('der gesperrte SMS-Tab schaltet nicht um', (tester) async {
      ChatChannel? gewaehlt;
      await zeige(tester, mitglied(telefon: null),
          onChanged: (c) => gewaehlt = c);

      await tester.tap(find.text('SMS nicht verfügbar'));
      await tester.pump();

      expect(gewaehlt, isNull);
    });

    testWidgets('mit Nummer schaltet der SMS-Tab um', (tester) async {
      ChatChannel? gewaehlt;
      await zeige(tester, mitglied(telefon: '+491761234567'),
          onChanged: (c) => gewaehlt = c);

      await tester.tap(find.text('SMS'));
      await tester.pump();

      expect(gewaehlt, ChatChannel.sms);
    });

    testWidgets('liefert der Server das Feld noch gar nicht, bleibt die '
        'Leiste aus — statt „keine Nummer" zu behaupten', (tester) async {
      // Ältere api/chat/conversations.php ohne m.telefon_mobil im SELECT.
      await zeige(tester, {
        'id': 7,
        'mitgliedernummer': 'M12345',
        'member_id': 7,
        'status': 'open',
      });

      expect(find.text('App-Chat'), findsNothing);
      expect(find.text('SMS'), findsNothing);
      expect(find.text('SMS nicht verfügbar'), findsNothing);
    });

    testWidgets('anonyme Besucher haben keinen Datensatz und damit keine Wahl',
        (tester) async {
      await zeige(tester, {
        'id': 8,
        'mitgliedernummer': 'ANON_9F3A2',
        'member_id': 8,
        'status': 'open',
        'is_anonymous': 1,
        'telefon_mobil': '0176 1234567',
      });

      expect(find.text('App-Chat'), findsNothing);
      expect(find.text('SMS'), findsNothing);
    });
  });

  group('Regelband im SMS-Verlauf', () {
    // Die Einschränkungen stehen dort, BEVOR jemand gegen sie läuft — nicht
    // erst als Fehlermeldung, wenn die Datei schon ausgewählt ist.
    testWidgets('nennt Nummer und Einschränkungen, sobald SMS offen ist',
        (tester) async {
      await zeige(tester, mitglied(telefon: '0176 1234567'),
          channel: ChatChannel.sms);

      expect(
        find.textContaining('nur Text — keine Anhänge, keine Lesebestätigung'),
        findsOneWidget,
      );
      // Eine SMS geht an ein Telefon, nicht an ein Konto: wer die Nummer hier
      // liest, merkt eine veraltete sofort.
      expect(find.textContaining('+491761234567'), findsOneWidget);
    });

    testWidgets('steht nicht im App-Verlauf', (tester) async {
      await zeige(tester, mitglied(telefon: '0176 1234567'));

      expect(find.textContaining('nur Text'), findsNothing);
    });

    testWidgets('erscheint nicht, wenn SMS gar nicht möglich ist — auch wenn '
        'der Kanal auf SMS stünde', (tester) async {
      await zeige(tester, mitglied(telefon: null), channel: ChatChannel.sms);

      expect(find.textContaining('nur Text'), findsNothing);
    });
  });

  group('Zuordnung einer Nachricht zum Verlauf', () {
    test('leere oder fehlende Spalte heißt App — wie DEFAULT auf dem Server',
        () {
      // Der gesamte Verlauf von vor der Kanaltrennung hat kein `channel`.
      // Würde er als SMS gelten, stünde er im SMS-Tab, wo nie eine SMS war.
      expect(chatKanalVon({'id': 1}), ChatChannel.app);
      expect(chatKanalVon({'id': 1, 'channel': null}), ChatChannel.app);
      expect(chatKanalVon({'id': 1, 'channel': 'app'}), ChatChannel.app);
    });

    test('nur der ausdrückliche Wert sms zählt als SMS', () {
      expect(chatKanalVon({'id': 1, 'channel': 'sms'}), ChatChannel.sms);
      // Unbekannte Werte gehören nicht in den SMS-Verlauf: dort steht sonst
      // eine Nachricht, für die nie ein Segment bezahlt wurde.
      expect(chatKanalVon({'id': 1, 'channel': 'SMS'}), ChatChannel.app);
      expect(chatKanalVon({'id': 1, 'channel': 'whatsapp'}), ChatChannel.app);
    });
  });

  group('Ungelesen-Abzeichen', () {
    // Ohne sie müsste man in den anderen Tab wechseln, um überhaupt zu merken,
    // dass dort etwas liegt — bei getrennten Verläufen ist das der einzige
    // Hinweis auf den nicht geöffneten.
    testWidgets('zeigt je Verlauf die eigene Zahl', (tester) async {
      await zeige(tester, mitglied(telefon: '0176 1234567'),
          ungeleseneApp: 3, ungeleseneSms: 2);

      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('bei null bleibt der Tab sauber', (tester) async {
      await zeige(tester, mitglied(telefon: '0176 1234567'));

      expect(find.text('0'), findsNothing);
    });
  });
}
