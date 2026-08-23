import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/sicher_clipboard.dart';

/// Auf dem Test-Host (nicht Android) fällt SicherClipboard auf
/// Clipboard.setData zurück. Geprüft: der Wert wird kopiert, nach der TTL
/// automatisch geleert, und leere() leert sofort.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final gesetzt = <String?>[];

  setUp(() {
    gesetzt.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        gesetzt.add((call.arguments as Map)['text'] as String?);
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('kopiert den Wert und leert nach der TTL', () async {
    await SicherClipboard.kopiere('geheim123',
        ttl: const Duration(milliseconds: 50));
    expect(gesetzt, contains('geheim123'));
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(gesetzt.last, '', reason: 'Zwischenablage muss nach der TTL leer sein');
  });

  test('leere() leert sofort', () async {
    await SicherClipboard.kopiere('x', ttl: const Duration(seconds: 30));
    await SicherClipboard.leere();
    expect(gesetzt.last, '');
  });
}
