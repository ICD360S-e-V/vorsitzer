import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/mail_cache_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Zwei Fehler im Zwischenspeicher, die nur bei GLEICHZEITIGEN Aufrufern
/// auftreten — und die deshalb kein einzelner Ablauf je gezeigt hätte.
///
/// Beide sind auf dem üblichen Weg erreichbar, nicht in einem Sonderfall: beim
/// Öffnen des Postfachs legt `_load()` die Ordnerliste ab, und die Leseansicht
/// daneben die geöffnete Nachricht. Beide unbeaufsichtigt, beide sofort.
///
/// ⚠️ Diese Tests prüfen das WIRKLICHE Verhalten des Dienstes, nicht eine
/// nachgebaute Ablaufsteuerung. Deshalb der Aufwand mit den Kanälen: eine
/// nachgebaute Kopie hätte genau die Reihenfolge, die man selbst hineinschreibt,
/// und wäre grün, egal was der Dienst tut.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('mailcache_probe');
    SharedPreferences.setMockInitialValues({});

    // path_provider: der Dienst legt seine Datei im App-Support-Ordner ab.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tempDir.path,
    );

    // Der Schlüsselbund ist im Test nicht da. SecureStore fällt dann auf seine
    // verschlüsselte Datei zurück — genau wie unter Flatpak und bei
    // Auto-Login, also auf dem Weg, den die Anwendung ohnehin oft geht.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async => throw PlatformException(code: 'kein Schluesselbund'),
    );
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  List<Map<String, dynamic>> zeilen(int von, int bis) => [
        for (var i = von; i <= bis; i++)
          {'uid': i, 'subject': 'Nachricht $i', 'from': 'a@b.de', 'seen': false},
      ];

  test('gleichzeitiges Ablegen verliert KEINEN Eintrag', () async {
    // Genau die Reihenfolge vom ersten Öffnen des Postfachs: Ordnerliste und
    // Nachricht gehen zusammen los, keiner wartet auf den anderen.
    final c = MailCacheService.zumTesten();
    await Future.wait([
      c.ordnerAblegen('INBOX', zeilen(1, 3), gesamt: 3),
      c.nachrichtAblegen('INBOX', 1, {'uid': 1, 'text': 'Hallo'}),
      c.ordnerAblegen('Sent', zeilen(10, 11), gesamt: 2),
    ]);

    // Aus einer FRISCHEN Instanz lesen — nur so ist bewiesen, dass wirklich
    // alles auf der Platte gelandet ist und nicht bloss im Speicher stand.
    final wieder = MailCacheService.zumTesten();
    final eingang = await wieder.ordnerHolen('INBOX');
    final ausgang = await wieder.ordnerHolen('Sent');
    final nachricht = await wieder.nachrichtHolen('INBOX', 1);

    expect(eingang, isNotNull, reason: 'Eingang ging verloren');
    expect(eingang!.nachrichten.length, 3);
    expect(ausgang, isNotNull, reason: 'Ausgang ging verloren');
    expect(ausgang!.nachrichten.length, 2);
    expect(nachricht, isNotNull, reason: 'Nachrichtentext ging verloren');
    expect(nachricht!.daten['text'], 'Hallo');
  });

  test('viele gleichzeitige Schreibvorgänge hinterlassen eine LESBARE Datei',
      () async {
    // Der zweite Fehler: zwei Läufe schrieben dieselbe `.tmp` und benannten sie
    // um. Im ungünstigen Fall wird eine halb geschriebene Datei zum Bestand —
    // und der ist dann ganz weg, nicht nur der letzte Eintrag.
    final c = MailCacheService.zumTesten();
    await Future.wait([
      for (var i = 0; i < 12; i++)
        c.ordnerAblegen('INBOX', zeilen(1, 5 + i), gesamt: 5 + i),
    ]);

    // ⚠️ DAS ist die Zusage, nicht „die Datei war zufällig noch lesbar":
    // zu keinem Zeitpunkt darf mehr als EIN Schreibvorgang laufen. Auf eine
    // beschädigte Datei zu warten hiesse, den Zufall zu prüfen — zwei
    // überlappende Läufe auf dieselbe `.tmp` gehen meistens gut aus.
    expect(c.hoechststandSchreiben, 1,
        reason: '${c.hoechststandSchreiben} Schreibvorgänge liefen gleichzeitig');

    final wieder = MailCacheService.zumTesten();
    final eingang = await wieder.ordnerHolen('INBOX');
    expect(eingang, isNotNull, reason: 'Bestand ist unlesbar geworden');
    expect(eingang!.nachrichten, isNotEmpty);

    // Und genau EINE Datei, kein liegengebliebenes .tmp.
    final reste = tempDir
        .listSync()
        .whereType<File>()
        .map((f) => f.path.split('/').last)
        .where((n) => n.startsWith('mail_cache'))
        .toList();
    expect(reste.where((n) => n.endsWith('.tmp')), isEmpty,
        reason: 'ein abgebrochener Schreibvorgang blieb liegen: $reste');
  });

  test('was abgelegt wurde, steht NICHT im Klartext auf der Platte', () async {
    // Durch dieses Postfach gehen Arzt- und Behördenunterlagen. Ein
    // Zwischenspeicher, der den Betreff lesbar hinterlässt, hebt die
    // Verschlüsselung des Postfachs still auf.
    final c = MailCacheService.zumTesten();
    await c.ordnerAblegen('INBOX', [
      {'uid': 1, 'subject': 'Ihr Widerspruch gegen den Bescheid', 'seen': false}
    ], gesamt: 1);

    final datei = File('${tempDir.path}/mail_cache_v1.bin');
    expect(await datei.exists(), isTrue);
    final roh = await datei.readAsBytes();
    expect(String.fromCharCodes(roh.where((b) => b >= 32 && b < 127)),
        isNot(contains('Widerspruch')));
  });

  test('leeren entfernt die Datei und liest sie nicht wieder ein', () async {
    final c = MailCacheService.zumTesten();
    await c.ordnerAblegen('INBOX', zeilen(1, 2), gesamt: 2);
    expect(await File('${tempDir.path}/mail_cache_v1.bin').exists(), isTrue);

    await c.leeren();
    expect(await File('${tempDir.path}/mail_cache_v1.bin').exists(), isFalse);
    // ⚠️ Auch DIESELBE Instanz darf danach nichts mehr finden — sonst hätte
    // das Abmelden den Bestand nur kurz versteckt.
    expect(await c.ordnerHolen('INBOX'), isNull);
  });

  test('ein angerissener Bestand blockiert das Postfach nicht', () async {
    final c = MailCacheService.zumTesten();
    await c.ordnerAblegen('INBOX', zeilen(1, 2), gesamt: 2);
    // Datei mutwillig beschädigen.
    await File('${tempDir.path}/mail_cache_v1.bin')
        .writeAsBytes(List<int>.filled(64, 0x41));

    final wieder = MailCacheService.zumTesten();
    expect(await wieder.ordnerHolen('INBOX'), isNull);
    // Und danach lässt sich wieder normal ablegen.
    await wieder.ordnerAblegen('INBOX', zeilen(1, 2), gesamt: 2);
    expect((await MailCacheService.zumTesten().ordnerHolen('INBOX'))?.nachrichten
        .length, 2);
  });
}
