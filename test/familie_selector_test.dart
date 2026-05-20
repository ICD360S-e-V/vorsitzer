// Tests for FamilieSelectorDialog — the popup that appears when an admin
// clicks on a member who has family connections (vormund + kinder).
//
// We test the WIDGET in isolation (no API), so we can drive the inputs
// directly and verify what the user actually sees.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/user.dart';
import 'package:icd360sev_vorsitzer/utils/familie_selector_dialog.dart';

User _makeUser({
  required int id,
  required String mnr,
  required String role,
  String? vorname,
  String? nachname,
  String? geburtsdatum,
}) {
  return User.fromJson({
    'id': id,
    'mitgliedernummer': mnr,
    'email': '$mnr@test.de',
    'name': '${vorname ?? ''} ${nachname ?? ''}'.trim(),
    'vorname': vorname,
    'nachname': nachname,
    'role': role,
    'status': 'active',
    'geburtsdatum': geburtsdatum,
  });
}

Future<void> _pumpSelector(
  WidgetTester tester, {
  required User activeUser,
  Map<String, dynamic>? vormund,
  required List<Map<String, dynamic>> kinder,
  void Function(User)? onSelected,
  VoidCallback? onAddKind,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FamilieSelectorDialog(
        activeUser: activeUser,
        vormund: vormund,
        kinder: kinder,
        onProfileSelected: onSelected ?? (_) {},
        onAddKind: onAddKind,
      ),
    ),
  ));
}

void main() {
  group('FamilieSelectorDialog rendering', () {
    testWidgets('parent with 2 children shows 3 entries (self + 2 kids)', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');

      await _pumpSelector(
        tester,
        activeUser: maria,
        vormund: null,
        kinder: [
          {'id': 2, 'mitgliedernummer': 'J12346', 'vorname': 'Anna', 'nachname': 'Mueller', 'role': 'jugendmitglied', 'status': 'active', 'geburtsdatum': '2014-03-15'},
          {'id': 3, 'mitgliedernummer': 'J12347', 'vorname': 'Tim', 'nachname': 'Mueller', 'role': 'jugendmitglied', 'status': 'active', 'geburtsdatum': '2017-09-20'},
        ],
      );

      expect(find.text('Maria Mueller'), findsOneWidget, reason: 'parent self entry');
      expect(find.text('Anna Mueller'), findsOneWidget, reason: 'first kid');
      expect(find.text('Tim Mueller'), findsOneWidget, reason: 'second kid');
      expect(find.text('V12345'), findsOneWidget);
      expect(find.text('J12346'), findsOneWidget);
      expect(find.text('J12347'), findsOneWidget);

      // Kid icon present for jugendmitglied entries
      expect(find.byIcon(Icons.child_care), findsNWidgets(2));
    });

    testWidgets('child with vormund shows vormund at top with Vormund badge', (tester) async {
      final anna = _makeUser(id: 2, mnr: 'J12346', role: 'jugendmitglied', vorname: 'Anna', nachname: 'Mueller', geburtsdatum: '2014-03-15');

      await _pumpSelector(
        tester,
        activeUser: anna,
        vormund: {'id': 1, 'mitgliedernummer': 'V12345', 'vorname': 'Maria', 'nachname': 'Mueller'},
        kinder: [],
      );

      expect(find.text('Maria Mueller'), findsOneWidget);
      expect(find.text('Anna Mueller'), findsOneWidget);
      expect(find.text('Vormund'), findsOneWidget, reason: 'Vormund badge shown on parent entry');
      expect(find.byIcon(Icons.supervisor_account), findsOneWidget, reason: 'Vormund icon');
      expect(find.byIcon(Icons.child_care), findsOneWidget, reason: 'Active child icon');
    });

    testWidgets('tapping a child invokes onProfileSelected with that child', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');
      User? picked;

      await _pumpSelector(
        tester,
        activeUser: maria,
        vormund: null,
        kinder: [
          {'id': 2, 'mitgliedernummer': 'J12346', 'vorname': 'Anna', 'nachname': 'Mueller', 'role': 'jugendmitglied', 'status': 'active', 'geburtsdatum': '2014-03-15'},
        ],
        onSelected: (u) => picked = u,
      );

      await tester.tap(find.text('Anna Mueller'));
      await tester.pump();

      expect(picked, isNotNull);
      expect(picked!.id, 2);
      expect(picked!.mitgliedernummer, 'J12346');
      expect(picked!.role, 'jugendmitglied');
    });

    testWidgets('tapping the active member invokes onProfileSelected with the original User', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');
      User? picked;

      await _pumpSelector(
        tester,
        activeUser: maria,
        vormund: null,
        kinder: [
          {'id': 2, 'mitgliedernummer': 'J12346', 'vorname': 'Anna', 'nachname': 'Mueller', 'role': 'jugendmitglied', 'status': 'active'},
        ],
        onSelected: (u) => picked = u,
      );

      await tester.tap(find.text('Maria Mueller'));
      await tester.pump();

      expect(picked, isNotNull);
      expect(picked!.id, 1);
      // Returned User must be the original instance (fallback shortcut)
      expect(identical(picked, maria), isTrue, reason: 'active-user tap returns original User instance, not a re-parsed copy');
    });

    testWidgets('age shown for child with geburtsdatum', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');
      final tenYearsAgo = DateTime.now().subtract(const Duration(days: 10 * 365 + 3));
      final iso = '${tenYearsAgo.year}-${tenYearsAgo.month.toString().padLeft(2, '0')}-${tenYearsAgo.day.toString().padLeft(2, '0')}';

      await _pumpSelector(
        tester,
        activeUser: maria,
        vormund: null,
        kinder: [
          {'id': 2, 'mitgliedernummer': 'J12346', 'vorname': 'Anna', 'nachname': 'Mueller', 'role': 'jugendmitglied', 'status': 'active', 'geburtsdatum': iso},
        ],
      );

      // Age "10 J." should appear (or "9 J." right before birthday — accept both)
      final ageFinder = find.textContaining(RegExp(r'· (9|10) J\.'));
      expect(ageFinder, findsOneWidget);
    });

    testWidgets('member without family still sees self entry + add-kind button', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');
      bool addClicked = false;

      await _pumpSelector(
        tester,
        activeUser: maria,
        vormund: null,
        kinder: [],
        onAddKind: () => addClicked = true,
      );

      // Self entry IS visible even with no family
      expect(find.text('Maria Mueller'), findsOneWidget);
      expect(find.text('V12345'), findsOneWidget);

      // Add-kind button visible
      expect(find.byKey(const Key('add-kind-tile')), findsOneWidget);
      expect(find.text('Neues Kind hinzufuegen'), findsOneWidget);

      // Tap add-kind -> callback fires
      await tester.tap(find.byKey(const Key('add-kind-tile')));
      await tester.pump();
      expect(addClicked, isTrue);
    });

    testWidgets('add-kind button is hidden when onAddKind is null', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');

      await _pumpSelector(
        tester,
        activeUser: maria,
        vormund: null,
        kinder: [],
        // onAddKind intentionally not provided
      );

      expect(find.byKey(const Key('add-kind-tile')), findsNothing);
    });

    testWidgets('shows close button and dismisses', (tester) async {
      final maria = _makeUser(id: 1, mnr: 'V12345', role: 'vorsitzer', vorname: 'Maria', nachname: 'Mueller');

      late BuildContext dialogCtx;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Builder(builder: (ctx) {
            return ElevatedButton(
              onPressed: () {
                showDialog(
                  context: ctx,
                  builder: (selCtx) {
                    dialogCtx = selCtx;
                    return FamilieSelectorDialog(
                      activeUser: maria,
                      vormund: null,
                      kinder: const [
                        {'id': 2, 'mitgliedernummer': 'J12346', 'vorname': 'Anna', 'nachname': 'Mueller', 'role': 'jugendmitglied', 'status': 'active'},
                      ],
                      onProfileSelected: (_) {},
                    );
                  },
                );
              },
              child: const Text('open'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byType(FamilieSelectorDialog), findsOneWidget);

      // Tap close icon -> dialog gone
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      expect(find.byType(FamilieSelectorDialog), findsNothing);
      expect(dialogCtx, isNotNull);
    });
  });
}
