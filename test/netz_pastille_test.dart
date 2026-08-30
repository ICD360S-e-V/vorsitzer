import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/netz_pastille.dart';

/// ⚠️ WAS HIER GEPRÜFT WIRD, IST EINE AUSSAGE, KEIN LAYOUT.
///
/// Der Rufnummernblock sagt, WEM er zugeteilt wurde. Seit der
/// Rufnummernmitnahme (November 2002) kann eine 0171 bei Vodafone liegen. Ein
/// Logo ohne diesen Unterschied wäre eine Behauptung mit Zuversicht — und die
/// ist bei jeder portierten Nummer falsch. Deshalb muss das Wort „Block"
/// dastehen und der Hinweis erreichbar sein.
void main() {
  // ⚠️ Vorbelegt, damit kein Test ins Netz greift. `null` heisst „versucht,
  // ging nicht" — genau der Zustand, in dem der Name statt des Bildes stehen
  // muss. Ohne das lief der erste Entwurf in ein „Invalid SVG data" aus dem
  // Testrahmen, der jede Netzanfrage mit 400 beantwortet.
  setUp(() {
    netzlogoSpeicher
      ..clear()
      ..addAll({'telekom': null, 'vodafone': null});
  });

  Future<void> zeige(WidgetTester t, Map<String, dynamic>? e,
      {bool kompakt = false}) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: NetzPastille(einordnung: e, kompakt: kompakt)),
    ));
  }

  testWidgets('Mobilfunk: „Block", nicht „Anbieter"', (t) async {
    await zeige(t, {
      'art': 'mobil',
      'art_text': 'Mobilfunk',
      'netz': 'Telekom',
      'logo': 'telekom',
      'netz_sicher': false,
      'hinweis': 'Rufnummernblock zugeteilt an Telekom Deutschland GmbH — '
          'nach einer Rufnummernmitnahme kann der Anschluss heute in einem '
          'anderen Netz liegen.',
    });
    expect(find.text('Block'), findsOneWidget);
    expect(find.text('Anbieter'), findsNothing);
    // ⚠️ Der Name steht IMMER da, mit oder ohne Logo. Vorher erschien bei den
    // vier grossen Netzen nur das Zeichen und bei allen anderen nur ein Name —
    // das las sich, als fehle mal das eine, mal das andere.
    expect(find.text('Telekom'), findsOneWidget);
  });

  testWidgets('der Hinweis ist erreichbar, nicht nur vorhanden', (t) async {
    await zeige(t, {
      'art': 'mobil', 'art_text': 'Mobilfunk', 'netz': 'Vodafone',
      'logo': 'vodafone', 'hinweis': 'kann portiert sein',
    });
    // Auf dem Telefon gibt es keinen Zeiger, der über einem Tooltip stehen
    // bleibt — also muss man ihn antippen können.
    expect(find.byType(InkWell), findsOneWidget);
    await t.tap(find.byType(InkWell));
    await t.pumpAndSettle();
    expect(find.text('kann portiert sein'), findsOneWidget);
  });

  testWidgets('Festnetz zeigt den Ort — die Auskunft, die nicht altert', (t) async {
    await zeige(t, {'art': 'festnetz', 'art_text': 'Festnetz', 'ort': 'Ulm Donau'});
    expect(find.text('Ulm Donau'), findsOneWidget);
    // Kein Netz, kein „Block": bei Festnetz gibt es diese Unsicherheit nicht.
    expect(find.text('Block'), findsNothing);
  });

  testWidgets('0900 wird als kostenpflichtig ausgewiesen', (t) async {
    await zeige(t, {
      'art': 'premium', 'art_text': 'Premium-Dienst', 'kosten': 'kostenpflichtig',
      'hinweis': 'Der Preis wird vom Nummerninhaber festgelegt.',
    });
    expect(find.textContaining('kostenpflichtig'), findsOneWidget);
  });

  testWidgets('Festnetz nennt jetzt auch den Anbieter', (t) async {
    // ⚠️ Das stand vorher nicht da: aus dem Verzeichnis der Bundesnetzagentur
    // wurden nur die 5.200 Ort-Paare gelesen und die Spalte
    // `KurznameAnbieter` weggeworfen — obwohl sie je TAUSENDERblock dasteht,
    // also genauer als im Mobilfunk.
    await zeige(t, {
      'art': 'festnetz', 'art_text': 'Festnetz', 'ort': 'Ulm Donau',
      'zuteilung': 'Netzquadrat', 'netz': null, 'logo': null,
      'hinweis': 'Rufnummernblock zugeteilt an Netzquadrat — kann portiert sein',
    });
    expect(find.text('Ulm Donau'), findsOneWidget);
    expect(find.text('Netzquadrat'), findsOneWidget);
    // Auch beim Festnetz wird portiert — innerhalb desselben Ortsnetzes.
    expect(find.text('Block'), findsOneWidget);
  });

  testWidgets('MVNO ohne Netz: der Zuteilungsinhaber statt einer Lücke', (t) async {
    // `netz` ist leer, weil in DIESEN Daten nicht steht, in wessen Netz Lycatel
    // funkt. Der Zuteilungsinhaber steht aber fest.
    await zeige(t, {
      'art': 'mobil', 'art_text': 'Mobilfunk', 'netz': null, 'logo': null,
      'zuteilung': 'Lycatel Germany GmbH',
    });
    expect(find.text('Lycatel Germany GmbH'), findsOneWidget);
  });

  testWidgets('liegt das Logo vor, wird es gezeichnet', (t) async {
    // Ein winziges, gueltiges SVG — beweist, dass der Weg „aus dem Speicher
    // zeichnen" trägt und nicht nur der Rückfall geprüft wird.
    netzlogoSpeicher['telekom'] =
        '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
        '<rect width="10" height="10"/></svg>';
    await zeige(t, {
      'art': 'mobil', 'art_text': 'Mobilfunk', 'netz': 'Telekom',
      'logo': 'telekom', 'hinweis': 'kann portiert sein',
    });
    await t.pumpAndSettle();
    expect(find.byType(SvgPicture), findsOneWidget);
    // Das Zeichen kommt DAZU, es ersetzt den Namen nicht.
    expect(find.text('Telekom'), findsOneWidget);
    expect(find.text('Block'), findsOneWidget);
  });

  testWidgets('eine amtlich aufgefallene Nummer wird gewarnt', (t) async {
    await zeige(t, {
      'art': 'mobil', 'art_text': 'Mobilfunk', 'netz': 'Telekom', 'logo': 'telekom',
      'missbrauch': 'BNetzA 2025',
    });
    expect(find.text('amtlich aufgefallen'), findsOneWidget);
  });

  testWidgets('ohne Eintrag steht KEIN grünes Gegenstück da', (t) async {
    // ⚠️ Das ist der Punkt. „Nicht auf der Liste" sagt nichts — die meisten
    // Betrugsanrufe kommen mit gefälschter Absenderkennung. Ein Häkchen dort
    // wäre eine Unbedenklichkeitsbescheinigung, die niemand ausgestellt hat.
    await zeige(t, {
      'art': 'mobil', 'art_text': 'Mobilfunk', 'netz': 'Telekom', 'logo': 'telekom',
      'missbrauch': null,
    });
    expect(find.textContaining('unbedenklich'), findsNothing);
    expect(find.textContaining('geprüft'), findsNothing);
    expect(find.text('amtlich aufgefallen'), findsNothing);
  });

  testWidgets('nichts bekannt heisst: nichts behaupten', (t) async {
    await zeige(t, null);
    expect(find.byType(Text), findsNothing);
    await zeige(t, {'art': 'unbekannt', 'art_text': 'Unbekannt'});
    expect(find.byType(Text), findsNothing);
  });
}
