import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/blitz_nachricht.dart';
import 'package:icd360sev_vorsitzer/widgets/blitz_karte.dart';

/// Der Text auf der Blitz-Karte deckt sich nach kurzem Lesen selbst zu —
/// die Karte liegt mitten auf dem Bildschirm, auch wenn jemand dazukommt.
void main() {
  BlitzNachricht n(List<String> zeilen) => BlitzNachricht(
        conversationId: 1,
        absender: 'Ionela Padurean',
        nummer: 'M51060',
        zeilen: zeilen,
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

  const kurz = ['Bună ziua'];
  const lang = [
    'Bună ziua, am primit scrisoarea de la Landratsamt și nu înțeleg',
    'ce trebuie să fac mai departe cu documentele astea',
    'mă puteți ajuta vă rog',
  ];

  testWidgets('am Anfang steht der Text da', (t) async {
    await zeigen(t, n(kurz));
    expect(find.text('Bună ziua'), findsOneWidget);
  });

  testWidgets('nach Ablauf ist er zugedeckt', (t) async {
    await zeigen(t, n(kurz));
    await t.pump(const Duration(seconds: 20));
    expect(find.text('Bună ziua'), findsNothing);
    // Die Wortform bleibt: gleiche Länge, Leerzeichen an derselben Stelle.
    expect(find.text('•••• ••••'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('ein langer Text bleibt länger offen als ein kurzer',
      (t) async {
    // ⚠️ Der eigentliche Punkt der Rechnung: fünf Sekunden reichen für zwei
    // Zeilen und für fünf nicht.
    await zeigen(t, n(kurz));
    await t.pump(const Duration(seconds: 5));
    final kurzZu = find.text('Bună ziua').evaluate().isEmpty;
    await t.pump(const Duration(seconds: 20));

    await zeigen(t, n(lang));
    await t.pump(const Duration(seconds: 5));
    final langOffen = find.text(lang.first).evaluate().isNotEmpty;
    expect(kurzZu, isTrue, reason: 'kurz ist nach 5 s zu');
    expect(langOffen, isTrue, reason: 'lang ist nach 5 s noch offen');
    await t.pump(const Duration(seconds: 20));
  });

  testWidgets('die Rückwärtszählung ist von Anfang an sichtbar', (t) async {
    // Ein Text, der ohne Vorwarnung verschwindet, fühlt sich wie ein Fehler an.
    await zeigen(t, n(kurz));
    expect(find.text('4'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    expect(find.text('2'), findsOneWidget);
    await t.pump(const Duration(seconds: 20));
  });

  testWidgets('„Wieder anzeigen" holt ihn zurück und deckt erneut zu',
      (t) async {
    await zeigen(t, n(kurz));
    await t.pump(const Duration(seconds: 20));
    expect(find.text('Bună ziua'), findsNothing);

    await t.tap(find.text('Wieder anzeigen'));
    await t.pump();
    expect(find.text('Bună ziua'), findsOneWidget);

    // ⚠️ Und danach wieder zu — die Sicherung bleibt immer scharf.
    await t.pump(const Duration(seconds: 20));
    expect(find.text('Bună ziua'), findsNothing);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('eine neue Zeile deckt alles wieder auf', (t) async {
    await zeigen(t, n(kurz));
    await t.pump(const Duration(seconds: 20));
    expect(find.text('Bună ziua'), findsNothing);

    // Dieselbe Karte bekommt eine zweite Zeile.
    await zeigen(t, n([...kurz, 'am o întrebare']));
    await t.pump();
    expect(find.text('Bună ziua'), findsOneWidget,
        reason: 'der Nachsatz ohne den ersten Satz wäre sinnlos');
    expect(find.text('am o întrebare'), findsOneWidget);
    await t.pump(const Duration(seconds: 20));
  });

  testWidgets('Nummer und Uhrzeit bleiben immer sichtbar', (t) async {
    await zeigen(t, n(kurz));
    await t.pump(const Duration(seconds: 20));
    expect(find.text('M51060'), findsOneWidget);
    expect(find.text('09:42'), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('antworten geht auch bei zugedecktem Text', (t) async {
    final gesendet = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BlitzKarte(
          nachricht: n(kurz),
          onSenden: (s) async {
            gesendet.add(s);
            return null;
          },
          onSchliessen: () {},
        ),
      ),
    ));
    await t.pump(const Duration(seconds: 20));
    await t.enterText(find.byType(TextField), 'Bine, mulțumesc');
    await t.pump();
    await t.tap(find.byIcon(Icons.send));
    await t.pump();
    expect(gesendet, ['Bine, mulțumesc']);
    await t.pump(const Duration(seconds: 1));
  });
}
