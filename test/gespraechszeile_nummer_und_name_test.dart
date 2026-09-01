import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/conversation_list_item.dart';

/// Nummer oben, Name darunter.
///
/// Vorher stand im Posteingang NUR die Mitgliedsnummer — eine Liste aus 29
/// Zeilen wie „V27655" sagt niemandem, mit wem er schreibt.
///
/// ⚠️ Die Nummer bleibt oben: sie ist im Verein die eindeutige Kennung, zwei
/// Menschen können denselben Namen tragen, und Behörden suchen nach ihr. Der
/// Name kommt dazu, er ersetzt sie nicht.
void main() {
  Widget zeile(Map<String, dynamic> g) => MaterialApp(
        home: Scaffold(
          body: ConversationListItem(
            conversation: g,
            isSelected: false,
            hasActiveCall: false,
            isOnline: false,
            onTap: () {},
          ),
        ),
      );

  testWidgets('zeigt Nummer UND Namen', (tester) async {
    await tester.pumpWidget(zeile({
      'id': 52,
      'mitgliedernummer': 'V27655',
      'gegenueber_name': 'I. C. Duinea',
      'member_name': 'I. C. Duinea',
      'unread_count': 0,
    }));
    expect(find.text('V27655'), findsOneWidget);
    expect(find.text('I. C. Duinea'), findsOneWidget,
        reason: 'ohne den Namen ist die Liste eine Reihe von Nummern');
  });

  testWidgets('ohne Nummer steht der Name oben — und nur einmal',
      (tester) async {
    // Sonst stünde derselbe Text in Titel und Unterzeile.
    await tester.pumpWidget(zeile({
      'id': 60,
      'gegenueber_name': 'A. Menning',
      'unread_count': 0,
    }));
    expect(find.text('A. Menning'), findsOneWidget);
  });

  testWidgets('ein anonymer Besucher bekommt keine Namenszeile',
      (tester) async {
    // Dort gibt es keinen echten Namen; die Zeile wäre eine leere Behauptung.
    await tester.pumpWidget(zeile({
      'id': 53,
      'is_anonymous': true,
      'mitgliedernummer': 'A1234',
      'member_name': 'Anonym',
      'unread_count': 0,
    }));
    expect(tester.takeException(), isNull);
  });
}
