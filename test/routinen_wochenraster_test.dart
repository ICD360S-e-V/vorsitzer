import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:icd360sev_vorsitzer/screens/routinenaufgaben_screen.dart';

/// Der Wochenraster blieb von #197 (09.08.2026) bis heute LEER: die Tagesspalte
/// wurde in einen SingleChildScrollView gesteckt, das `Expanded` um die
/// Kartenliste blieb aber stehen. Unbegrenzte Höhe + Expanded =
/// "RenderFlex children have non-zero flex but incoming height constraints are
/// unbounded", also wird die Spalte gar nicht gelegt. Im Debug-Bau rot, im
/// Release-Bau schlicht nichts — genau so wurde es gemeldet.
///
/// Der Test prüft NICHT den Quelltext, sondern legt den Bildschirm wirklich aus.
/// Ohne Netz liefert der Dienst leere Listen, der Raster wird trotzdem gebaut —
/// und genau das Legen ist die Stelle, die vorher geworfen hat.
void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  testWidgets('Wochenraster legt sich ohne Layout-Ausnahme aus', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: RoutinenaufgabenScreen(
          users: [],
          currentMitgliedernummer: 'V10001',
        ),
      ),
    ));

    // Ladephase abwarten, ohne pumpAndSettle (der Spinner dreht endlos, wenn
    // der Dienst hängt) — mehrere feste Takte reichen.
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(tester.takeException(), isNull,
        reason: 'Der Wochenraster darf keine Layout-Ausnahme werfen');
    expect(find.text('Montag'), findsOneWidget);
    expect(find.text('Sonntag'), findsOneWidget);
  });
}
