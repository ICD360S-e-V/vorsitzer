import 'package:flutter_test/flutter_test.dart';
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
      g.currentMitgliedernummer = 'V75715';
      g.currentAdminUserId = 9;
      expect(CloudPickerHelper.adminCloudFuer(9), 'V75715');
      expect(CloudPickerHelper.adminCloudFuer(2), isNull);
    });
  });
}
