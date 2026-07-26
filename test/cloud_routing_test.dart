import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/global_chat_service.dart';
import 'package:icd360sev_vorsitzer/utils/cloud_picker_helper.dart';

/// Welcher der beiden Speicher zuständig ist, entscheidet über den ganzen
/// weiteren Weg: der 1-GB-Cloud des Mitglieds wird serverseitig kopiert, der
/// verschlüsselte 50-GB-Speicher muss lokal entschlüsselt werden. Greift die
/// Weiche daneben, öffnet sich stillschweigend die falsche — meist leere —
/// Liste, ohne dass irgendetwas nach einem Fehler aussieht.
void main() {
  final g = GlobalChatService();

  setUp(() {
    g.currentMitgliedernummer = null;
    g.currentAdminUserId = null;
  });

  tearDown(() {
    g.currentMitgliedernummer = null;
    g.currentAdminUserId = null;
  });

  group('CloudPickerHelper.adminCloudFuer', () {
    test('eigene Akte des angemeldeten Vorsitzenden -> verschlüsselter Cloud', () {
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = 2;
      expect(CloudPickerHelper.adminCloudFuer(2), 'V27655');
      expect(CloudPickerHelper.istVerschluesselt(2), isTrue);
    });

    test('fremde Akte -> Mitglieder-Cloud, nicht der eigene 50-GB-Speicher', () {
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = 2;
      expect(CloudPickerHelper.adminCloudFuer(17), isNull);
      expect(CloudPickerHelper.istVerschluesselt(17), isFalse);
    });

    test('ohne aufgelöste Admin-Kennung bleibt es beim Mitglieder-Cloud', () {
      // Tritt vor dem ersten Laden der Mitgliederliste auf. Lieber der
      // Mitglieder-Speicher als ein falsch geöffneter Vorsitzenden-Cloud.
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = null;
      expect(CloudPickerHelper.adminCloudFuer(2), isNull);
    });

    test('ohne Mitgliedsnummer bleibt es beim Mitglieder-Cloud', () {
      g.currentMitgliedernummer = null;
      g.currentAdminUserId = 2;
      expect(CloudPickerHelper.adminCloudFuer(2), isNull);
    });

    test('leere Mitgliedsnummer zählt wie keine', () {
      g.currentMitgliedernummer = '';
      g.currentAdminUserId = 2;
      expect(CloudPickerHelper.adminCloudFuer(2), isNull);
    });

    test('zweiter Vorsitzender bekommt seinen eigenen Speicher', () {
      // Echte Kennungen: V27655 ist id 2, V75715 ist id 23. Beide haben
      // serverseitig je 50 GB, streng getrennt — der eine darf die Akte des
      // anderen nicht als "eigene" sehen.
      g.currentMitgliedernummer = 'V75715';
      g.currentAdminUserId = 23;
      expect(CloudPickerHelper.adminCloudFuer(23), 'V75715');
      expect(CloudPickerHelper.adminCloudFuer(2), isNull);
    });
  });

  // Der Knopf ist das, was der Nutzer tatsächlich sieht und drückt. Dass die
  // Weiche stimmt, nützt nichts, wenn der Knopf sie nicht abbildet: Schloss
  // für den verschlüsselten 50-GB-Speicher, Wolke für den 1-GB-Cloud.
  group('CloudPickButton zeigt den zuständigen Speicher', () {
    Future<void> zeige(WidgetTester t, int memberId) => t.pumpWidget(MaterialApp(
          home: Scaffold(
            body: CloudPickButton(
              memberId: memberId,
              apiService: ApiService(),
              onPicked: (_) {},
            ),
          ),
        ));

    testWidgets('eigene Akte des Vorsitzenden -> Schloss, 50 GB im Hinweis',
        (t) async {
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = 2;
      await zeige(t, 2);

      expect(find.byIcon(Icons.lock), findsOneWidget);
      expect(find.byIcon(Icons.cloud_download), findsNothing);
      final tip = t.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('50-GB'));
      expect(tip.message, contains('verschlüsselt'));
    });

    testWidgets('Akte eines Mitglieds -> Wolke, 1 GB im Hinweis', (t) async {
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = 2;
      await zeige(t, 17);

      expect(find.byIcon(Icons.cloud_download), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
      final tip = t.widget<Tooltip>(find.byType(Tooltip));
      expect(tip.message, contains('1-GB'));
      expect(tip.message, contains('Mitglied'));
    });

    testWidgets('zweiter Vorsitzender sieht in FREMDER Akte den Mitglieder-Cloud',
        (t) async {
      // Sonst würde ein Vorsitzender beim Bearbeiten eines Mitglieds in
      // seinem eigenen Speicher wühlen.
      g.currentMitgliedernummer = 'V75715';
      g.currentAdminUserId = 23;
      await zeige(t, 2);

      expect(find.byIcon(Icons.cloud_download), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('ohne aufgelöste Admin-Kennung -> Mitglieder-Cloud', (t) async {
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = null;
      await zeige(t, 2);

      expect(find.byIcon(Icons.cloud_download), findsOneWidget);
      expect(find.byIcon(Icons.lock), findsNothing);
    });

    testWidgets('abgeschaltet, solange ein Upload läuft', (t) async {
      g.currentMitgliedernummer = 'V27655';
      g.currentAdminUserId = 2;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: CloudPickButton(
            memberId: 2,
            apiService: ApiService(),
            enabled: false,
            onPicked: (_) {},
          ),
        ),
      ));
      expect(
          t.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed, isNull);
    });
  });
}
