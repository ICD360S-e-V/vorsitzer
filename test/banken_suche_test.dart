import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';

/// Bis zum 03.09.2026 standen acht von Hand eingetragene Ulmer Banken in der
/// Tabelle `banken`, und der Client holte sie beim Öffnen des Reiters am Stück
/// (`action=list`) und filterte im Dialog lokal. Seither stehen dort rund
/// 3.500 Institute aus dem amtlichen Verzeichnis der Deutschen Bundesbank.
///
/// ⚠️ Der alte Weg wäre damit **830 kB je Öffnen** geworden — auf einem vhost
/// ohne gzip (nachgemessen) und auf derselben Mobilfunkleitung, deren
/// Einbrüche unter 2 Mbit/s wir gegenüber der Telekom protokollieren. Gesucht
/// wird deshalb auf dem Server.
///
/// ⚠️ Das PHP liegt in keinem Repo. Diese Datei ist die einzige Stelle im
/// Baum, an der auffallen kann, wenn der Client wieder anfängt, das ganze
/// Verzeichnis zu holen oder lokal zu filtern — beides scheitert nicht, es
/// zeigt nur stillschweigend zu wenig Banken an.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('banken_suche');
    for (final kanal in [
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/path_provider_linux',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              MethodChannel(kanal), (call) async => tempDir.path);
    }
    DeviceKeyService().setTestCredentials('GERAETESCHLUESSEL');
  });

  tearDown(() async {
    await ApiService().clearTokens();
    DeviceKeyService().setTestCredentials(null);
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  /// Fängt die aufgerufene Adresse ab und antwortet mit [rumpf].
  List<Uri> lauschen(String rumpf, {int status = 200}) {
    final gesehen = <Uri>[];
    ApiService().testClient = MockClient((anfrage) async {
      gesehen.add(anfrage.url);
      return http.Response(rumpf, status,
          headers: {'content-type': 'application/json'});
    });
    return gesehen;
  }

  group('sucheBanken', () {
    test('fragt den Server, statt eine Liste durchzusehen', () async {
      final urls = lauschen(jsonEncode({
        'success': true,
        'banken': [
          {'id': 3004, 'name': 'Sparkasse Neu-Ulm-Illertissen',
           'bic': 'BYLADEM1NUL', 'blz': '73050000', 'plz_ort': '89231 Neu-Ulm'},
        ],
        'gesamt': 1,
        'gekuerzt': false,
      }));

      final r = await ApiService().sucheBanken('Illertissen');

      expect(urls, hasLength(1));
      expect(urls.single.queryParameters['action'], 'search',
          reason: 'action=list holt das ganze Verzeichnis — 830 kB');
      expect(urls.single.queryParameters['q'], 'Illertissen');
      expect((r['banken'] as List).single['bic'], 'BYLADEM1NUL');
    });

    test('reicht gesamt und gekuerzt durch', () async {
      // ⚠️ Ohne diese beiden sieht eine Liste mit 50 Einträgen neben 459
      // Treffern vollständig aus, und der Suchende hört auf zu tippen,
      // obwohl seine Bank noch gar nicht dabei ist.
      lauschen(jsonEncode({
        'success': true,
        'banken': List.generate(50, (i) => {'id': i, 'name': 'Sparkasse $i'}),
        'gesamt': 459,
        'gekuerzt': true,
      }));

      final r = await ApiService().sucheBanken('sparkasse');

      expect((r['banken'] as List), hasLength(50));
      expect(r['gesamt'], 459);
      expect(r['gekuerzt'], isTrue);
    });

    test('das Limit geht mit', () async {
      final urls = lauschen(jsonEncode({'success': true, 'banken': <dynamic>[]}));
      await ApiService().sucheBanken('x', limit: 200);
      expect(urls.single.queryParameters['limit'], '200');
    });

    test('ein Netzfehler ist NICHT „keine Treffer"', () async {
      // Zwei verschiedene Aussagen, und nur eine davon darf als „diese Bank
      // gibt es nicht" auf dem Schirm landen.
      ApiService().testClient =
          MockClient((_) async => throw const SocketException('weg'));

      final r = await ApiService().sucheBanken('Sparkasse Ulm');

      expect(r['fehler'], isTrue);
      expect((r['banken'] as List), isEmpty);
    });

    test('eine kaputte Antwort meldet sich ebenfalls', () async {
      lauschen('<html>Gateway Timeout</html>', status: 504);
      final r = await ApiService().sucheBanken('Ulm');
      expect(r['fehler'], isTrue);
    });
  });

  group('getBank', () {
    test('holt eine einzelne Bank über action=get', () async {
      final urls = lauschen(jsonEncode({
        'success': true,
        'bank': {'id': 3004, 'name': 'Sparkasse Neu-Ulm-Illertissen'},
      }));

      final b = await ApiService().getBank(3004);

      expect(urls.single.queryParameters['action'], 'get');
      expect(urls.single.queryParameters['id'], '3004');
      expect(b?['name'], 'Sparkasse Neu-Ulm-Illertissen');
    });

    test('nicht gefunden gibt null, nicht eine leere Karte', () async {
      lauschen(jsonEncode({'success': false, 'message': 'Bank nicht gefunden'}),
          status: 404);
      expect(await ApiService().getBank(999999), isNull);
    });
  });

  group('getBanken (Hausbanken)', () {
    test('bleibt auf action=list', () async {
      final urls = lauschen(jsonEncode({'success': true, 'banken': <dynamic>[]}));
      await ApiService().getBanken();
      expect(urls.single.queryParameters['action'], 'list');
    });
  });

  group('Der Auswahldialog darf nicht wieder lokal filtern', () {
    // ⚠️ Diese Prüfung läuft über den QUELLTEXT, wie
    // test/sipgate_lebenszeichen_test.dart, und aus demselben Grund: ein
    // Rückfall auf lokales Filtern scheitert nirgends. Er zeigt nur die
    // sieben Hausbanken statt 3.500 Institute — und sieht dabei aus wie ein
    // vollständiges Ergebnis.
    final quelle = File('lib/widgets/finanzen_bank.dart').readAsStringSync();

    test('der Dialog ruft sucheBanken', () {
      expect(quelle, contains('sucheBanken('),
          reason: 'ohne Serversuche findet man nur die Hausbanken');
    });

    test('es wird nicht mehr über bankenDb gefiltert', () {
      expect(quelle.contains('bankenDb.where('), isFalse,
          reason: 'lokales Filtern über die Hausbanken-Liste ist der alte Weg');
    });

    test('eine gespeicherte Bank wird notfalls einzeln nachgeholt', () {
      // Wer eine der amtlichen Banken gewählt hat, steht nicht in bankenDb.
      // Ohne den Nachschlag stünde bei ihm „keine Bank hinterlegt".
      expect(quelle, contains('_bankNachladen('));
      expect(quelle, contains('getBank('));
    });
  });
}
