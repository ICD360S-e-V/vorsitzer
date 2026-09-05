// Sucht Stellen, die sich NICHT an die Auflösung anpassen.
//
// ⚠️ Das ist eine andere Frage als „läuft etwas über". Ein Bildschirm kann
// bei jeder Breite sauber aussehen und trotzdem starr sein: eine feste
// Spaltenzahl, ein 320-dp-Panel, eine Karte mit `width: 700`. Auf dem
// Telefon wird so etwas stillschweigend gestaucht, auf dem HDMI-Monitor
// bleibt die Fläche daneben leer. `aufloesung_breit_test.dart` findet davon
// nichts — dort ist alles grün, sobald nichts überläuft.
//
// Die Prüfung: von jedem Bildschirm wird bei 448 dp und bei 2560 dp ein
// **Abdruck** genommen — die Breiten aller gerenderten Kästen über 120 dp.
// Ein Aufbau, der sich anpasst, liefert zwei verschiedene Abdrücke. Kommt
// zweimal derselbe heraus, obwohl sich die Bildschirmbreite um das Fünffache
// geändert hat, ist der Aufbau starr.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icd360sev_vorsitzer/screens/dienste_screen.dart';
import 'package:icd360sev_vorsitzer/screens/finanzverwaltung_screen.dart';
import 'package:icd360sev_vorsitzer/screens/gls_bank_screen.dart';
import 'package:icd360sev_vorsitzer/screens/jpg2pdf_screen.dart';
import 'package:icd360sev_vorsitzer/screens/netzwerk_screen.dart';
import 'package:icd360sev_vorsitzer/screens/ordnungsmassnahmen_screen.dart';
import 'package:icd360sev_vorsitzer/screens/pending_parent_consent_screen.dart';
import 'package:icd360sev_vorsitzer/screens/reiseplanung_screen.dart';

const _telefon = Size(448, 997.3);
const _monitor = Size(2560, 1440);

/// Breiten aller gerenderten Kästen über [_mindestBreite], gerundet.
///
/// Kleine Kästen (Symbole, Abstandhalter, Knöpfe) sind absichtlich fest und
/// würden den Abdruck nur verrauschen.
const double _mindestBreite = 120;

Future<List<int>> abdruck(
  WidgetTester tester,
  Size groesse,
  Widget Function() bauen,
) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.physicalSize = groesse * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final vorher = FlutterError.onError;
  FlutterError.onError = (_) {}; // Überläufe interessieren hier nicht.

  await tester.pumpWidget(MaterialApp(home: Scaffold(body: bauen())));
  await tester.pump(const Duration(milliseconds: 50));

  final breiten = <int>[];
  for (final ro in tester.allRenderObjects) {
    if (ro is RenderBox && ro.hasSize) {
      final b = ro.size.width;
      if (b >= _mindestBreite && b.isFinite) breiten.add(b.round());
    }
  }
  breiten.sort();

  FlutterError.onError = vorher;
  tester.takeException();
  return breiten;
}

void main() {
  final faelle = <String, Widget Function()>{
    'DiensteScreen': () => const DiensteScreen(),
    'NetzwerkScreen': () => const NetzwerkScreen(),
    'FinanzverwaltungScreen': () => const FinanzverwaltungScreen(),
    'GlsBankScreen': () => GlsBankScreen(onBack: () {}),
    'Jpg2PdfScreen': () => Jpg2PdfScreen(onBack: () {}),
    'ReiseplanungScreen': () => ReiseplanungScreen(onBack: () {}),
    'OrdnungsmassnahmenScreen': () =>
        OrdnungsmassnahmenScreen(users: const [], onBack: () {}),
    'PendingParentConsentScreen': () =>
        const PendingParentConsentScreen(currentMitgliedernummer: 'V10001'),
  };

  group('Der Aufbau folgt der Bildschirmbreite', () {
    faelle.forEach((name, bauen) {
      testWidgets('$name passt sich an', (tester) async {
        final eng = await abdruck(tester, _telefon, bauen);
        final weit = await abdruck(tester, _monitor, bauen);

        // ⚠️ „Die Abdrücke unterscheiden sich" ist zu milde: der äußerste
        // Kasten dehnt sich immer mit, also bestünde jeder Bildschirm die
        // Prüfung. Gezählt wird deshalb, wie viel vom Inhalt **gleich breit
        // bleibt**, obwohl fünfmal so viel Platz da ist.
        final unveraendert = <int>[];
        final rest = [...weit];
        for (final b in eng) {
          if (rest.remove(b)) unveraendert.add(b);
        }
        final anteil = eng.isEmpty ? 0.0 : unveraendert.length / eng.length;

        expect(
          anteil,
          lessThan(0.75),
          reason: '$name: ${unveraendert.length} von ${eng.length} Kästen '
              '(${(anteil * 100).round()} %) sind am 2560-dp-Monitor exakt so '
              'breit wie auf dem Telefon. Der Inhalt klebt in einer '
              'Telefonspalte, rechts daneben bleibt es leer.\n'
              'Gleich gebliebene Breiten: '
              '${unveraendert.toSet().toList()..sort()}',
        );
      });
    });
  });
}
