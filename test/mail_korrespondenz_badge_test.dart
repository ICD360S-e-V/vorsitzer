import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_korrespondenz_badge.dart';

/// Das Badge sagt, ob eine Mail schon in einem Korrespondenz-Archiv liegt.
/// Es falsch anzuzeigen ist teurer als es wegzulassen: „nicht archiviert" bei
/// einem archivierten Schreiben führt zum doppelten Ablegen, umgekehrt hält man
/// einen Bescheid für gesichert, der nirgends liegt.
Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>>? eintraege, {
  bool compact = true,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: MailKorrespondenzBadge(eintraege: eintraege, compact: compact),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

Map<String, dynamic> _eintrag(String bereich, {int dateien = 1}) => {
      'bereich': bereich,
      'korrespondenz_id': 7,
      'datum': '2026-07-26 08:35:06',
      'dateien': dateien,
    };

void main() {
  group('MailKorrespondenzBadge', () {
    testWidgets('zeigt nichts ohne Treffer', (tester) async {
      await _pump(tester, null);
      expect(find.byType(Icon), findsNothing);

      await _pump(tester, const []);
      expect(find.byType(Icon), findsNothing);
    });

    testWidgets('kompakt: ein Haken je Archiv', (tester) async {
      await _pump(tester, [_eintrag('finanzamt')]);
      expect(find.byIcon(Icons.account_balance), findsOneWidget);
      expect(find.byIcon(Icons.code), findsNothing);
      expect(find.byIcon(Icons.check), findsOneWidget);

      await _pump(tester, [_eintrag('github')]);
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.account_balance), findsNothing);
    });

    testWidgets('kompakt: liegt die Mail in beiden Archiven, zeigt es beide',
        (tester) async {
      await _pump(tester, [_eintrag('finanzamt'), _eintrag('github')]);
      expect(find.byIcon(Icons.account_balance), findsOneWidget);
      expect(find.byIcon(Icons.code), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNWidgets(2));
    });

    testWidgets('lang: nennt Archiv, Datum und Anzahl der Dokumente',
        (tester) async {
      await _pump(tester, [_eintrag('github', dateien: 3)], compact: false);
      expect(find.text('In GitHub-Korrespondenz übernommen'), findsOneWidget);
      expect(find.textContaining('26.07.2026'), findsOneWidget);
      expect(find.textContaining('3 Dokumente archiviert'), findsOneWidget);
    });

    testWidgets('lang: Singular bei genau einem Dokument', (tester) async {
      await _pump(tester, [_eintrag('finanzamt')], compact: false);
      expect(find.textContaining('1 Dokument archiviert'), findsOneWidget);
      expect(find.textContaining('1 Dokumente'), findsNothing);
    });

    testWidgets('unbekannter Bereich verschwindet nicht, sondern wird benannt',
        (tester) async {
      // Ein serverseitig neu angelegtes Archiv darf nicht dazu führen, dass die
      // Mail wieder als „nicht archiviert" aussieht — bis der Client die Namen
      // kennt, steht der Bereich eben so da, wie er heißt.
      await _pump(tester, [_eintrag('hetzner')], compact: false);
      expect(find.text('In hetzner-Korrespondenz übernommen'), findsOneWidget);
      expect(find.byIcon(Icons.folder_outlined), findsOneWidget);
    });

    testWidgets('fehlende Felder kippen das Badge nicht', (tester) async {
      await _pump(tester, [
        {'bereich': 'github'},
      ], compact: false);
      expect(find.text('In GitHub-Korrespondenz übernommen'), findsOneWidget);
      expect(find.textContaining('0 Dokumente archiviert'), findsOneWidget);
    });
  });
}
