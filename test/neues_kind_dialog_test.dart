// Validation + rendering tests for NeuesKindDialog (form to create a
// jugendmitglied account under a vormund). The actual save-flow integration
// (API call -> server) is verified manually since ApiService is a singleton
// with a private constructor that's hard to stub.
//
// Children are managed-only accounts: email + password are NOT collected in
// the UI — the server auto-generates internal placeholders.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/utils/familie_selector_dialog.dart';

Future<void> _pumpDialog(WidgetTester tester) async {
  await tester.pumpWidget(MaterialApp(
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('de'), Locale('en')],
    home: Scaffold(
      body: NeuesKindDialog(
        apiService: ApiService(),
        vormundUserId: 1,
      ),
    ),
  ));
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  group('NeuesKindDialog rendering', () {
    testWidgets('only 3 form fields (Vorname/Nachname/Geburtsdatum) + info banner', (tester) async {
      await _pumpDialog(tester);

      expect(find.byKey(const Key('kind-vorname')), findsOneWidget);
      expect(find.byKey(const Key('kind-nachname')), findsOneWidget);
      expect(find.byKey(const Key('kind-geburtsdatum')), findsOneWidget);

      // Email + password fields are GONE (auto-generated server-side)
      expect(find.byKey(const Key('kind-email')), findsNothing,
          reason: 'children have no own email — auto-generated internal placeholder');
      expect(find.byKey(const Key('kind-password')), findsNothing,
          reason: 'children have no login — server auto-generates random password');

      expect(find.textContaining('Mitgliedernummer'), findsOneWidget);
      expect(find.textContaining('verwaltet'), findsOneWidget, reason: 'info banner explains managed-only nature');

      expect(find.text('Abbrechen'), findsOneWidget);
      expect(find.text('Anlegen'), findsOneWidget);
    });

    testWidgets('Abbrechen pops with false', (tester) async {
      bool? popResult;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('de'), Locale('en')],
        home: Scaffold(
          body: Builder(builder: (ctx) {
            return ElevatedButton(
              onPressed: () async {
                popResult = await showDialog<bool>(
                  context: ctx,
                  builder: (_) => NeuesKindDialog(apiService: ApiService(), vormundUserId: 1),
                );
              },
              child: const Text('open'),
            );
          }),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();

      expect(popResult, isFalse);
    });
  });

  group('NeuesKindDialog validation', () {
    testWidgets('empty submit shows errors only for Vorname + Nachname', (tester) async {
      await _pumpDialog(tester);

      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();

      // Only Vorname + Nachname have validators now
      expect(find.text('mindestens 2 Zeichen'), findsNWidgets(2));

      // No email/password validation messages anymore
      expect(find.text('erforderlich'), findsNothing);
      expect(find.text('mindestens 6 Zeichen'), findsNothing);
    });

    testWidgets('1-char Vorname rejected', (tester) async {
      await _pumpDialog(tester);
      await tester.enterText(find.byKey(const Key('kind-vorname')), 'A');
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      expect(find.text('mindestens 2 Zeichen'), findsNWidgets(2),
          reason: 'Vorname (1 char) + Nachname (empty) both fail');
    });

    testWidgets('valid name+nachname but missing geburtsdatum -> Snackbar', (tester) async {
      await _pumpDialog(tester);
      await tester.enterText(find.byKey(const Key('kind-vorname')), 'Anna');
      await tester.enterText(find.byKey(const Key('kind-nachname')), 'Mueller');
      // Geburtsdatum still required (left empty)

      await tester.tap(find.text('Anlegen'));
      await tester.pump();

      expect(find.textContaining('Geburtsdatum'), findsWidgets);
    });
  });
}
