// Validation + rendering tests for NeuesKindDialog (form to create a
// jugendmitglied account under a vormund). The actual save-flow integration
// (API call -> server) is verified manually in app since ApiService is a
// singleton with a private constructor that's hard to stub. Validation
// is the part most prone to silent regression, so we cover it here.

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
    // shared_preferences uses a method channel even in tests — stub it.
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => null);
  });

  group('NeuesKindDialog rendering', () {
    testWidgets('all 5 form fields + info banner are visible', (tester) async {
      await _pumpDialog(tester);

      expect(find.byKey(const Key('kind-vorname')), findsOneWidget);
      expect(find.byKey(const Key('kind-nachname')), findsOneWidget);
      expect(find.byKey(const Key('kind-geburtsdatum')), findsOneWidget);
      expect(find.byKey(const Key('kind-email')), findsOneWidget);
      expect(find.byKey(const Key('kind-password')), findsOneWidget);
      expect(find.textContaining('Mitgliedernummer wird automatisch'), findsOneWidget);

      // Action buttons present
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
    testWidgets('empty submit shows error for Vorname/Nachname/Email/Password', (tester) async {
      await _pumpDialog(tester);

      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();

      // Validation messages appear
      expect(find.text('mindestens 2 Zeichen'), findsNWidgets(2), reason: 'Vorname + Nachname');
      expect(find.text('erforderlich'), findsOneWidget, reason: 'Email required');
      expect(find.text('mindestens 6 Zeichen'), findsOneWidget, reason: 'Password too short');

      // Form validation prevents save — no API call attempted (no snackbar visible)
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('1-char Vorname rejected', (tester) async {
      await _pumpDialog(tester);
      await tester.enterText(find.byKey(const Key('kind-vorname')), 'A');
      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();
      // 2 occurrences: Vorname (we wrote 'A' = too short) + Nachname (empty = too short)
      expect(find.text('mindestens 2 Zeichen'), findsNWidgets(2));
    });

    testWidgets('valid name+nachname+email but missing geburtsdatum -> Snackbar', (tester) async {
      await _pumpDialog(tester);
      await tester.enterText(find.byKey(const Key('kind-vorname')), 'Anna');
      await tester.enterText(find.byKey(const Key('kind-nachname')), 'Mueller');
      await tester.enterText(find.byKey(const Key('kind-email')), 'anna@familie.de');
      await tester.enterText(find.byKey(const Key('kind-password')), 'parola123');
      // Geburtsdatum left empty

      await tester.tap(find.text('Anlegen'));
      await tester.pump(); // surface snackbar

      expect(find.textContaining('Geburtsdatum'), findsWidgets, reason: 'snackbar mentions Geburtsdatum');
    });

    testWidgets('invalid email format rejected', (tester) async {
      await _pumpDialog(tester);
      await tester.enterText(find.byKey(const Key('kind-vorname')), 'Anna');
      await tester.enterText(find.byKey(const Key('kind-nachname')), 'Mueller');
      await tester.enterText(find.byKey(const Key('kind-email')), 'not-an-email');
      await tester.enterText(find.byKey(const Key('kind-password')), 'parola123');

      await tester.tap(find.text('Anlegen'));
      await tester.pumpAndSettle();

      expect(find.text('ungültige E-Mail'), findsOneWidget);
    });
  });
}
