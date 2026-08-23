import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:icd360sev_vorsitzer/screens/login_screen.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';

/// Simuliert Android-15-Edge-to-Edge: der Login-Bildschirm (ohne AppBar) wird
/// mit Status-/Gestenleisten-Insets gerendert. Er muss ohne Overflow bauen und
/// der Inhalt darf nicht unter die obere Systemleiste rutschen (dafür die
/// SafeArea). Bestätigt, dass der randlose Modus diesen Bildschirm nicht bricht.
void main() {
  setUpAll(() {
    DeviceKeyService().setTestCredentials('TEST-KEY');
    ApiService().testClient =
        MockClient((r) async => http.Response('{"success":false}', 200));
  });
  tearDownAll(() => DeviceKeyService().setTestCredentials(null));

  testWidgets('Login überlebt Systemleisten-Insets (edge-to-edge)',
      (tester) async {
    final fehler = <FlutterErrorDetails>[];
    final vorher = FlutterError.onError;
    FlutterError.onError = (d) => fehler.add(d);

    await tester.pumpWidget(const MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(
          size: Size(360, 780),
          devicePixelRatio: 3,
          // 48 dp oben (Statusleiste) + 48 dp unten (Gestenleiste).
          viewPadding: EdgeInsets.only(top: 48, bottom: 48),
          padding: EdgeInsets.only(top: 48, bottom: 48),
        ),
        child: LoginScreen(),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(seconds: 2));
    FlutterError.onError = vorher;

    final overflow = fehler.where(
        (d) => d.exceptionAsString().toLowerCase().contains('overflow'));
    expect(overflow, isEmpty,
        reason: 'Kein RenderFlex-Overflow unter Systemleisten-Insets');

    // Das erste Eingabefeld darf nicht unter der Statusleiste (48 dp) liegen.
    final felder = find.byType(TextField);
    if (felder.evaluate().isNotEmpty) {
      final oben = tester.getTopLeft(felder.first).dy;
      expect(oben, greaterThanOrEqualTo(48.0),
          reason: 'Inhalt beginnt unterhalb der Statusleiste (SafeArea greift)');
    }
  });
}
