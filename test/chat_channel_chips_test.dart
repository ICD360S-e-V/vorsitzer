import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/chat_header.dart';

/// Der Kanalschalter über der Konversation entscheidet, ob eine Nachricht in
/// der App landet oder über die SIM des Vereins-Tablets rausgeht.
///
/// 19 der 42 Mitglieder haben in Verifizierung Stufe 1 gar keine Rufnummer.
/// Für sie MUSS „SMS nicht verfügbar" sichtbar dastehen: ein still fehlender
/// Knopf sähe wie ein Fehler aus, und ein stilles Ausweichen auf die App wäre
/// schlimmer — der Vorsitzer glaubte dann, eine SMS verschickt zu haben.
void main() {
  Future<void> zeige(
    WidgetTester tester,
    Map<String, dynamic> conversation, {
    ChatChannel channel = ChatChannel.app,
    ValueChanged<ChatChannel>? onChanged,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConversationHeader(
          conversation: conversation,
          canCall: false,
          isOpen: true,
          onCall: () {},
          onClose: () {},
          onMuteToggle: () {},
          channel: channel,
          onChannelChanged: onChanged ?? (_) {},
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

  group('Kanalschalter App | SMS', () {
    testWidgets('mit Mobilnummer stehen beide Wege zur Wahl', (tester) async {
      await zeige(tester, mitglied(telefon: '0176 1234567'));

      expect(find.text('App'), findsOneWidget);
      expect(find.text('SMS'), findsOneWidget);
      expect(find.text('SMS nicht verfügbar'), findsNothing);
    });

    testWidgets('ohne Rufnummer wird SMS ausdrücklich als nicht verfügbar '
        'angezeigt, nicht weggelassen', (tester) async {
      await zeige(tester, mitglied(telefon: null));

      expect(find.text('App'), findsOneWidget);
      expect(find.text('SMS nicht verfügbar'), findsOneWidget);
      expect(find.text('SMS'), findsNothing);
    });

    testWidgets('Festnetz zählt wie keine Nummer — dorthin kommt seit 2023 '
        'keine SMS mehr an', (tester) async {
      await zeige(tester, mitglied(telefon: '0711 123456'));

      expect(find.text('SMS nicht verfügbar'), findsOneWidget);
    });

    testWidgets('der gesperrte SMS-Knopf schaltet nicht um', (tester) async {
      ChatChannel? gewaehlt;
      await zeige(tester, mitglied(telefon: null),
          onChanged: (c) => gewaehlt = c);

      await tester.tap(find.text('SMS nicht verfügbar'));
      await tester.pump();

      expect(gewaehlt, isNull);
    });

    testWidgets('mit Nummer schaltet der SMS-Knopf um', (tester) async {
      ChatChannel? gewaehlt;
      await zeige(tester, mitglied(telefon: '+491761234567'),
          onChanged: (c) => gewaehlt = c);

      await tester.tap(find.text('SMS'));
      await tester.pump();

      expect(gewaehlt, ChatChannel.sms);
    });

    testWidgets('liefert der Server das Feld noch gar nicht, bleibt die '
        'Auswahl aus — statt „keine Nummer" zu behaupten', (tester) async {
      // Ältere api/chat/conversations.php ohne m.telefon_mobil im SELECT.
      await zeige(tester, {
        'id': 7,
        'mitgliedernummer': 'M12345',
        'member_id': 7,
        'status': 'open',
      });

      expect(find.text('App'), findsNothing);
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

      expect(find.text('App'), findsNothing);
      expect(find.text('SMS'), findsNothing);
    });
  });
}
