import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/mail_models.dart';
import 'package:icd360sev_vorsitzer/utils/mail_delivery_report.dart';
import 'package:icd360sev_vorsitzer/widgets/mail_delivery_report_card.dart';

const _zugestellt = MailDelivery(
  state: MailDeliveryState.sent,
  smtpResponse: '250 2.0.0 Ok: queued as 4X1',
  relay: 'mx01.jobcenter.example[10.0.0.7]:25',
  queueId: '4bTn2Q1r3z',
  deliveredAt: '26.07.2026 09:14:31',
  recipients: ['post@jobcenter.example', 'kopie@jobcenter.example'],
);

void main() {
  group('Zeilen des Sendeberichts', () {
    test('zugestellt: Status, Zeitpunkt, Empfänger, Relay, Antwort, Queue-ID',
        () {
      final rows = deliveryReportRows(_zugestellt);

      expect(rows.map((r) => r.first), [
        'Status',
        'Angenommen',
        'Empfänger',
        'Zielserver',
        'Antwort',
        'Queue-ID',
      ]);
      expect(rows.first.last, contains('Zugestellt'));
      expect(rows[1].last, '26.07.2026 09:14:31');
      expect(rows[2].last, 'post@jobcenter.example, kopie@jobcenter.example');
      expect(rows[4].last, '250 2.0.0 Ok: queued as 4X1');
    });

    /// Der gefährlichste Fall: ohne Log-Eintrag darf weder Blatt noch Karte so
    /// aussehen, als sei die Nachricht angekommen.
    test('ohne Log-Eintrag steht das ausgeschrieben da, nicht leer', () {
      final rows = deliveryReportRows(const MailDelivery());
      expect(rows.length, 1);
      expect(rows.single.last, 'Kein Eintrag im Sendeprotokoll gefunden');
      expect(rows.single.last.toLowerCase(), isNot(contains('zugestellt')));
    });

    test('gescheiterte Zustellung wird als solche benannt', () {
      expect(
          deliveryStatusText(
              const MailDelivery(state: MailDeliveryState.bounced)),
          contains('Abgelehnt'));
      expect(
          deliveryStatusText(
              const MailDelivery(state: MailDeliveryState.expired)),
          contains('Aufgegeben'));
      expect(
          deliveryStatusText(
              const MailDelivery(state: MailDeliveryState.deferred)),
          contains('Erneuter Versuch'));
      expect(
          deliveryStatusText(
              const MailDelivery(state: MailDeliveryState.queued)),
          contains('Warteschlange'));
    });

    test('Lesebestätigung: offen und bestätigt sind unterscheidbar', () {
      final offen = deliveryReportRows(const MailDelivery(
          state: MailDeliveryState.sent, receiptRequested: true));
      expect(offen.last.first, 'Lesebestätigung');
      expect(offen.last.last, contains('noch nicht bestätigt'));

      final gelesen = deliveryReportRows(const MailDelivery(
        state: MailDeliveryState.sent,
        receiptRequested: true,
        receiptAt: '27.07.2026 11:02',
      ));
      expect(gelesen.last.last, 'Gelesen am 27.07.2026 11:02');

      // Nicht angefordert: die Zeile fehlt ganz, statt „nein" zu behaupten.
      final ohne =
          deliveryReportRows(const MailDelivery(state: MailDeliveryState.sent));
      expect(ohne.map((r) => r.first), isNot(contains('Lesebestätigung')));
    });
  });

  group('Karte am Bildschirm', () {
    Future<void> pump(WidgetTester tester, MailDelivery d) => tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: MailDeliveryReportCard(delivery: d),
              ),
            ),
          ),
        );

    /// Der Grund für die Änderung: Empfänger, Zielserver und Queue-ID hingen
    /// vorher nur im Tooltip des Symbols — auf einem Tablet unerreichbar.
    testWidgets('zeigt alle Felder, nicht nur Status und Antwort',
        (tester) async {
      await pump(tester, _zugestellt);

      expect(find.text('Sendebericht'), findsOneWidget);
      for (final label in const [
        'Status',
        'Angenommen',
        'Empfänger',
        'Zielserver',
        'Antwort',
        'Queue-ID',
      ]) {
        expect(find.text(label), findsOneWidget, reason: 'Zeile $label fehlt');
      }
      expect(find.text('4bTn2Q1r3z'), findsOneWidget);
      expect(find.text('mx01.jobcenter.example[10.0.0.7]:25'), findsOneWidget);
      expect(find.textContaining('Zugestellt'), findsOneWidget);
    });

    testWidgets('Werte lassen sich markieren und kopieren', (tester) async {
      await pump(tester, _zugestellt);
      // Jede Wertspalte ist auswählbar — sechs Zeilen, sechs Werte.
      expect(find.byType(SelectableText), findsNWidgets(6));
    });

    testWidgets('ohne Log-Eintrag bleibt es bei einer ehrlichen Zeile',
        (tester) async {
      await pump(tester, const MailDelivery());

      expect(find.text('Sendebericht'), findsOneWidget);
      expect(
          find.text('Kein Eintrag im Sendeprotokoll gefunden'), findsOneWidget);
      expect(find.text('Queue-ID'), findsNothing);
      expect(find.textContaining('Zugestellt'), findsNothing);
    });

    testWidgets('abgelehnt zeigt die Ablehnung und den Grund', (tester) async {
      await pump(
        tester,
        const MailDelivery(
          state: MailDeliveryState.bounced,
          smtpResponse: '550 5.1.1 Recipient address rejected: User unknown',
          recipients: ['kein.postfach@example.invalid'],
        ),
      );

      expect(find.textContaining('Abgelehnt'), findsOneWidget);
      expect(find.textContaining('User unknown'), findsOneWidget);
      // „Angenommen" darf hier nicht stehen — es gibt keine Annahme.
      expect(find.text('Angenommen'), findsNothing);
    });
  });
}
