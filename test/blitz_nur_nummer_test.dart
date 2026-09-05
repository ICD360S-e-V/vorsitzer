import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/blitz_nachricht.dart';
import 'package:icd360sev_vorsitzer/widgets/blitz_karte.dart';

/// Die Blitz-Karte legt sich mitten auf den Bildschirm, auch wenn gerade
/// jemand danebensteht. Sie zeigt deshalb die Mitgliedsnummer und nie den
/// Namen — Entscheidung des Users.
void main() {
  BlitzNachricht n({String absender = 'Ionela Gradinar', String? nummer}) =>
      BlitzNachricht(
        conversationId: 1,
        absender: absender,
        nummer: nummer,
        zeilen: const ['Bună ziua'],
        zeit: DateTime(2026, 8, 31, 9, 42),
      );

  Future<void> zeigen(WidgetTester t, BlitzNachricht m) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlitzKarte(
          nachricht: m,
          onSenden: (_) async => null,
          onSchliessen: () {},
        ),
      ),
    ));
    await t.pump();
  }

  testWidgets('zeigt die Nummer, nicht den Namen', (t) async {
    await zeigen(t, n(nummer: 'M10001'));
    expect(find.text('M10001'), findsOneWidget);
    expect(find.text('Ionela Gradinar'), findsNothing);
  });

  testWidgets('ohne Nummer steht „Mitglied" — NICHT der Name', (t) async {
    // ⚠️ Der wichtigste Fall: fällt die Nummer aus (alte Nachricht, anderer
    // Weg, Fehler), darf der Name nicht als Rückfallebene erscheinen. Sonst
    // stünde er ausgerechnet in dem Fall da, den niemand vorhergesehen hat.
    await zeigen(t, n());
    expect(find.text('Mitglied'), findsOneWidget);
    expect(find.text('Ionela Gradinar'), findsNothing);
  });

  testWidgets('anonyme Besucher heißen „Anonim"', (t) async {
    await zeigen(t, n(absender: 'Anonim · Maria', nummer: 'Anonim'));
    expect(find.text('Anonim'), findsOneWidget);
    expect(find.textContaining('Maria'), findsNothing);
  });

  testWidgets('auch der Kreis verrät den Namen nicht', (t) async {
    // Die Initiale des Namens wäre der halbe Name.
    await zeigen(t, n(nummer: 'M10001'));
    expect(find.text('M'), findsOneWidget);
    expect(find.text('I'), findsNothing);
  });

  testWidgets('der Nachrichtentext bleibt sichtbar', (t) async {
    // So entschieden: verdeckt wird nur, WER schreibt, nicht WAS.
    await zeigen(t, n(nummer: 'M10001'));
    expect(find.text('Bună ziua'), findsOneWidget);
  });

  group('durch die JSON-Grenze zwischen den Fenstern', () {
    // Unter Linux läuft die Karte in einer eigenen Engine — alles, was sie
    // anzeigt, muss als JSON durchpassen.
    test('die Nummer übersteht die Reise', () {
      final zurueck = BlitzNachricht.entschluesselt(n(nummer: 'M10001').kodiert());
      expect(zurueck?.nummer, 'M10001');
      expect(zurueck?.anzeige, 'M10001');
    });

    test('eine fehlende Nummer bleibt fehlend', () {
      final zurueck = BlitzNachricht.entschluesselt(n().kodiert());
      expect(zurueck?.nummer, isNull);
      expect(zurueck?.anzeige, 'Mitglied');
    });

    test('beim Anhängen einer zweiten Zeile bleibt sie erhalten', () {
      final erste = n(nummer: 'M10001');
      final zweite = erste.ergaenztUm('a doua linie', DateTime(2026, 8, 31));
      expect(zweite.nummer, 'M10001');
      expect(zweite.zeilen.length, 2);
    });
  });
}
