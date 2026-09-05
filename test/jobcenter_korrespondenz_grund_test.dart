// Mitgliederverwaltung → Behörde → Jobcenter → Arbeitsvermittler →
// Korrespondenz: ein bestehender Eintrag darf sich nicht wie ein offenes
// Formular anfühlen. Er öffnet als Lese-Ansicht, und das Stift-Symbol
// entsperrt ihn erst gegen einen getippten Änderungsgrund — der Grund wandert
// als `aenderungsgrund` mit dem Update in die Spur auf dem Server.
//
// ⚠️ Vorher war der Eintrag zwar technisch gesperrt (readOnly + grau), sah
// aber weiter aus wie ein Formular. Genau daran ist die alte Fassung
// gescheitert; deshalb prüft der erste Test auf die AbwesenheIT von
// Eingabefeldern, nicht bloß auf `enabled == false`.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_jobcenter.dart';

Map<String, dynamic> _eintrag({int aenderungen = 0}) => {
      'id': 42,
      'richtung': 'ausgang',
      'kontaktart': 'email',
      'datum': '2026-08-12',
      'betreff': 'Meldeversäumnis',
      'text': 'Sehr geehrte Frau Muster, …',
      'aenderungen_count': aenderungen,
      'letzter_grund': aenderungen > 0 ? 'Datum war falsch erfasst' : null,
      'letzter_grund_von': aenderungen > 0 ? 'V10001' : null,
      'letzter_grund_am': aenderungen > 0 ? '2026-08-16 10:12:00' : null,
    };

Widget _huelle({Map<String, dynamic>? existing}) => MaterialApp(
      home: Scaffold(
        body: JcAvKorrespondenzDialog(
          apiService: ApiService(),
          userId: 2,
          userAvId: 5,
          existing: existing,
        ),
      ),
    );

void main() {
  group('bestehender Eintrag', () {
    testWidgets('öffnet als Lese-Ansicht, ohne Eingabefelder', (t) async {
      await t.pumpWidget(_huelle(existing: _eintrag()));
      await t.pump();

      expect(find.text('Korrespondenz erfasst'), findsOneWidget);
      // Der Inhalt steht als Text da — nicht in Feldern, die zum Tippen einladen.
      expect(find.text('Meldeversäumnis'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(SegmentedButton<String>), findsNothing);
      // Speichern gibt es erst, wenn wirklich bearbeitet wird.
      expect(find.text('Speichern'), findsNothing);
      expect(find.widgetWithText(TextButton, 'Bearbeiten'), findsOneWidget);
    });

    testWidgets('Stift ohne Grund entsperrt nicht', (t) async {
      await t.pumpWidget(_huelle(existing: _eintrag()));
      await t.pump();

      await t.tap(find.widgetWithText(TextButton, 'Bearbeiten'));
      await t.pumpAndSettle();

      expect(find.text('Warum wird dieser Eintrag nachträglich geändert?'), findsOneWidget);
      // Solange nichts getippt ist, ist „Entsperren" tot.
      final knopf = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Entsperren'));
      expect(knopf.onPressed, isNull);

      // Abbrechen lässt den Eintrag gesperrt zurück.
      await t.tap(find.widgetWithText(TextButton, 'Abbrechen'));
      await t.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Korrespondenz erfasst'), findsOneWidget);
    });

    testWidgets('mit Grund entsperrt und zeigt den Grund weiter an', (t) async {
      await t.pumpWidget(_huelle(existing: _eintrag()));
      await t.pump();

      await t.tap(find.widgetWithText(TextButton, 'Bearbeiten'));
      await t.pumpAndSettle();

      await t.enterText(find.byType(TextField).first, 'Datum war falsch erfasst');
      await t.pump();
      final knopf = t.widget<ElevatedButton>(find.widgetWithText(ElevatedButton, 'Entsperren'));
      expect(knopf.onPressed, isNotNull);

      await t.tap(find.widgetWithText(ElevatedButton, 'Entsperren'));
      await t.pumpAndSettle();

      // Jetzt ist es ein Formular — und der Grund bleibt sichtbar, damit am Ende
      // niemand raten muss, was da gleich protokolliert wird.
      expect(find.byType(SegmentedButton<String>), findsOneWidget);
      expect(find.text('Änderungsgrund: Datum war falsch erfasst'), findsOneWidget);
      expect(find.text('Speichern'), findsOneWidget);
    });

    testWidgets('Abbrechen im Formular holt den gespeicherten Stand zurück', (t) async {
      await t.pumpWidget(_huelle(existing: _eintrag()));
      await t.pump();
      await t.tap(find.widgetWithText(TextButton, 'Bearbeiten'));
      await t.pumpAndSettle();
      await t.enterText(find.byType(TextField).first, 'Tippfehler');
      await t.pump();
      await t.tap(find.widgetWithText(ElevatedButton, 'Entsperren'));
      await t.pumpAndSettle();

      await t.enterText(find.widgetWithText(TextField, 'Meldeversäumnis'), 'Verworfener Text');
      await t.pump();
      await t.tap(find.widgetWithText(TextButton, 'Abbrechen'));
      await t.pumpAndSettle();

      // Eine halb getippte Änderung darf nicht in der Lese-Ansicht stehen bleiben.
      expect(find.text('Meldeversäumnis'), findsOneWidget);
      expect(find.text('Verworfener Text'), findsNothing);
    });

    testWidgets('frühere Änderungen werden ausgewiesen', (t) async {
      await t.pumpWidget(_huelle(existing: _eintrag(aenderungen: 2)));
      await t.pump();

      expect(find.text('2 nachträgliche Änderungen'), findsOneWidget);
      expect(find.text('Zuletzt: Datum war falsch erfasst'), findsOneWidget);
      expect(find.text('Verlauf'), findsOneWidget);
    });

    testWidgets('eine einzelne Änderung steht im Singular', (t) async {
      await t.pumpWidget(_huelle(existing: _eintrag(aenderungen: 1)));
      await t.pump();
      expect(find.text('1 nachträgliche Änderung'), findsOneWidget);
    });
  });

  testWidgets('neuer Eintrag fragt keinen Grund ab', (t) async {
    // Ein Grund für das Anlegen wäre sinnlos — protokolliert werden nur
    // nachträgliche Änderungen an bereits erfassten Einträgen.
    await t.pumpWidget(_huelle());
    await t.pump();

    expect(find.text('Neue Korrespondenz'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    expect(find.text('Speichern'), findsOneWidget);
    expect(find.text('Korrespondenz erfasst'), findsNothing);
  });
}
