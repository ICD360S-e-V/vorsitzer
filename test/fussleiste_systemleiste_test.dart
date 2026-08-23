import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/legal_footer.dart';

/// Die App zeichnet randlos (`SystemUiMode.edgeToEdge`, main.dart). Als
/// `bottomNavigationBar` ist der rechtliche Fuß damit das unterste Bauteil des
/// Bildschirms — ohne eigenen Zuschlag lägen Version, Aktualisierungsknopf und
/// Weblink unter den drei Systemtasten.
///
/// Gemessen wird die Lage der Bedienelemente gegen die Gestenleiste, nicht das
/// Aussehen: ein Knopf unter der Systemleiste ist nicht antippbar, und genau
/// das soll hier auffallen.
const double _leiste = 48; // Höhe der Android-Navigationsleiste in dp
const Size _telefon = Size(360, 780);

/// Was unten stehen und erreichbar bleiben muss.
final _bedienelemente = <String, Finder>{
  'Aktualisierungsknopf': find.byIcon(Icons.refresh),
  'Weblink': find.byIcon(Icons.language),
  'Fehlerkonsole': find.text('>_'),
};

Widget _bildschirm({required EdgeInsets insets, bool inSafeArea = false}) {
  const fuss = LegalFooter(darkMode: true);
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: _telefon,
        devicePixelRatio: 3,
        viewPadding: insets,
        padding: insets,
      ),
      child: inSafeArea
          ? const Scaffold(
              body: SafeArea(
                child: Column(children: [Spacer(), fuss]),
              ),
            )
          : const Scaffold(bottomNavigationBar: fuss),
    ),
  );
}

void main() {
  testWidgets('Bedienelemente bleiben über der Navigationsleiste',
      (tester) async {
    await tester.pumpWidget(
        _bildschirm(insets: const EdgeInsets.only(bottom: _leiste)));
    await tester.pump();

    // Gegen den tatsächlich gerenderten Bildschirm messen, nicht gegen
    // `_telefon.height`: die Testfläche ist 800x600, MediaQuery.size ändert
    // daran nichts. Mit der Wunschhöhe wäre die Prüfung wirkungslos.
    final schirm = tester.getSize(find.byType(Scaffold)).height;
    final untersteKante = schirm - _leiste;
    _bedienelemente.forEach((name, finder) {
      expect(finder, findsOneWidget, reason: '$name fehlt im Fuß');
      expect(tester.getBottomRight(finder).dy, lessThanOrEqualTo(untersteKante),
          reason: '$name liegt unter der Navigationsleiste und ist dort weder '
              'lesbar noch antippbar');
    });

    await tester.pumpWidget(const SizedBox()); // Timer beenden
  });

  testWidgets('Die eingefärbte Fläche reicht bis zur Bildschirmkante durch',
      (tester) async {
    await tester.pumpWidget(
        _bildschirm(insets: const EdgeInsets.only(bottom: _leiste)));
    await tester.pump();

    // Kein SafeArea außen herum: sonst klaffte unter dem Fuß eine Lücke in der
    // Scaffold-Farbe, auf die das System seinen Schleier legt.
    expect(tester.getBottomLeft(find.byType(LegalFooter)).dy,
        closeTo(tester.getSize(find.byType(Scaffold)).height, 0.5),
        reason: 'Der Fuß muss bis zur Bildschirmkante reichen');

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Ohne Systemleiste wächst nichts (Rechner, Tastatur offen)',
      (tester) async {
    await tester.pumpWidget(_bildschirm(insets: EdgeInsets.zero));
    await tester.pump();
    final ohne = tester.getSize(find.byType(LegalFooter)).height;
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(
        _bildschirm(insets: const EdgeInsets.only(bottom: _leiste)));
    await tester.pump();
    final mit = tester.getSize(find.byType(LegalFooter)).height;
    await tester.pumpWidget(const SizedBox());

    expect(mit - ohne, closeTo(_leiste, 0.5),
        reason: 'Genau die Leistenhöhe kommt dazu, nicht mehr');
  });

  testWidgets('Innerhalb einer SafeArea wird der Zuschlag nicht verdoppelt',
      (tester) async {
    // So steht der Fuß im Login-Bildschirm. Die SafeArea hat den Wert bereits
    // verbraucht; ein zweiter Zuschlag wäre eine Lücke von 48 dp.
    await tester.pumpWidget(_bildschirm(
        insets: const EdgeInsets.only(bottom: _leiste), inSafeArea: true));
    await tester.pump();
    final inSafeArea = tester.getSize(find.byType(LegalFooter)).height;
    await tester.pumpWidget(const SizedBox());

    await tester.pumpWidget(_bildschirm(insets: EdgeInsets.zero));
    await tester.pump();
    final blank = tester.getSize(find.byType(LegalFooter)).height;
    await tester.pumpWidget(const SizedBox());

    expect(inSafeArea, closeTo(blank, 0.5),
        reason: 'Der Login-Fuß darf nicht doppelt Platz lassen');
  });
}
