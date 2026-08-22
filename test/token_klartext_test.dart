import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bis zum 22.08.2026 schrieb `saveTokens` die Token bei jedem Fehlschlag des
/// Schlüsselbunds im KLARTEXT nach SharedPreferences — während der
/// Kopfkommentar von `loadTokens` versprach, genau das nie zu tun. Von dort
/// gingen sie in jede Gerätesicherung.
///
/// OWASP dazu: „Never park long-lived secrets in SharedPreferences" — auch
/// nicht als Rückfall.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('tok_test');
    for (final kanal in [
      'plugins.flutter.io/path_provider',
      'plugins.flutter.io/path_provider_linux',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
              MethodChannel(kanal), (call) async => tempDir.path);
    }
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('Speichern legt NICHTS im Klartext ab', () async {
    SharedPreferences.setMockInitialValues({});
    await ApiService().saveTokens('geheimes-token', 'geheimer-refresh');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull,
        reason: 'im Klartext darf nichts liegen');
    expect(prefs.getString('refresh_token'), isNull);
    // Und die Werte dürfen auch sonst nirgends in den Einstellungen auftauchen.
    for (final k in prefs.getKeys()) {
      expect(prefs.get(k).toString(), isNot(contains('geheimes-token')),
          reason: 'gefunden unter „$k"');
      expect(prefs.get(k).toString(), isNot(contains('geheimer-refresh')),
          reason: 'gefunden unter „$k"');
    }
    await ApiService().clearTokens();
  });

  test('alter Klartext wird übernommen UND weggeräumt', () async {
    // Der Fall beim Update: das Token liegt noch offen da. Wer es einfach
    // ignoriert, meldet jeden Benutzer ohne Grund ab; wer es liegen lässt,
    // hat nichts repariert.
    SharedPreferences.setMockInitialValues({
      'access_token': 'alt-token',
      'refresh_token': 'alt-refresh',
    });
    await ApiService().clearTokens();
    SharedPreferences.setMockInitialValues({
      'access_token': 'alt-token',
      'refresh_token': 'alt-refresh',
    });

    await ApiService().loadTokens();
    expect(ApiService().token, 'alt-token', reason: 'niemand wird abgemeldet');
    expect(ApiService().refreshToken, 'alt-refresh');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull,
        reason: 'der Klartext geht weg, nachdem er verschoben wurde');
    expect(prefs.getString('refresh_token'), isNull);
    await ApiService().clearTokens();
  });

  test('nach dem Verschieben liegt es im sicheren Speicher', () async {
    // Kein nachgestellter Neustart — dafuer gaebe es keine Naht, und eine nur
    // fuer den Test zu bauen waere die falsche Richtung. Geprueft wird direkt,
    // wo der Wert gelandet ist.
    SharedPreferences.setMockInitialValues({
      'access_token': 'wander-token',
      'refresh_token': 'wander-refresh',
    });
    await ApiService().loadTokens();

    const sicher = FlutterSecureStorage();
    expect(await sicher.read(key: 'access_token'), 'wander-token',
        reason: 'verschoben, nicht nur gelesen');
    expect(await sicher.read(key: 'refresh_token'), 'wander-refresh');
    await ApiService().clearTokens();
  });

  test('Abmelden räumt auch alten Klartext weg', () async {
    SharedPreferences.setMockInitialValues({
      'access_token': 'weg-damit',
      'refresh_token': 'weg-damit-2',
    });
    await ApiService().clearTokens();
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('access_token'), isNull);
    expect(prefs.getString('refresh_token'), isNull);
  });
}
