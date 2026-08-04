// Smoke-Test: die App lässt sich bauen und zeigt ihren ersten Frame.
//
// Vorher prüfte dieser Test die Texte des alten Login-Screens („ICD360S e.V",
// „Vorsitzer Panel", „Anmelden"). `main.dart` zeigt seit dem Umstieg auf die
// Geräteaktivierung `LoginWithCodeScreen`; diese Texte gibt es nirgends mehr,
// der Test war also rot, ohne dass irgendetwas kaputt gewesen wäre.
//
// Warum er beim Ladezustand aufhört: `_checkExistingActivation()` liest den
// Device-Key aus dem Keyring und ruft bei fehlenden lokalen Zugangsdaten
// `recoverDeviceKey` am Server. Beides gibt es im Test nicht — der Bildschirm
// bliebe im Ladezustand hängen. Weiter zu kommen hieße, `DeviceKeyService` und
// `ApiService` injizierbar zu machen; das ist ein Umbau, kein Testfix.
//
// Was der Test damit trotzdem leistet: er fängt jeden Fehler ab, der beim
// Aufbau von `VorsitzerApp` selbst geworfen wird — Theme, Localizations,
// Navigator-Key, der Konstruktor des Startbildschirms.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icd360sev_vorsitzer/main.dart';

void main() {
  testWidgets('App baut und zeigt den Startbildschirm', (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(const VorsitzerApp());

    // Kein Aufbaufehler …
    expect(tester.takeException(), isNull);
    // … und der Startbildschirm hängt unter einem MaterialApp.
    expect(find.byType(MaterialApp), findsOneWidget);
    // Erster Frame: der Auto-Login-Check läuft noch.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
