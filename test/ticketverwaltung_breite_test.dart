// Zeigt die Ticketverwaltung ihre Tickets auch auf einem Telefon?
//
// ⚠️ Der Anlass war kein Serverfehler. `api/tickets/admin_list.php` lieferte
// nachgemessen 528 Tickets in 36 ms, fehlerfrei geparst — und der Bildschirm
// blieb trotzdem leer. Die Wochenansicht legte sieben Tagesspalten
// nebeneinander: auf 448 dp bleiben je 57 dp, und ein Überlauf in Flutter
// schneidet ab, er schrumpft nicht. Die Tickets *waren* da, nur außerhalb
// des sichtbaren Bereichs.
//
// Deshalb prüft dieser Test beides und nicht nur das eine: **keine**
// Layoutfehler UND mindestens eine sichtbare Ticketkarte. Ein Test, der nur
// auf Überläufe schaut, wäre bei einer leeren Fläche zufrieden gewesen.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:icd360sev_vorsitzer/screens/ticketverwaltung_screen.dart';
import 'package:icd360sev_vorsitzer/services/ticket_service.dart';

const _groessen = <String, ({Size groesse, double schrift})>{
  'Pixel 8 Pro (448 dp)': (groesse: Size(448, 997.3), schrift: 1.0),
  'Pixel 8 Pro, Schrift 2,0': (groesse: Size(448, 997.3), schrift: 2.0),
  'Tab A11 (800 dp)': (groesse: Size(800, 1280), schrift: 1.0),
  'Desktop (1440 dp)': (groesse: Size(1440, 900), schrift: 1.0),
};

/// Tickets auf **heute**, damit sie sowohl in der Wochen- als auch in der
/// Tagesansicht auftauchen — beide filtern über `scheduled_date`.
List<Ticket> _tickets() {
  final jetzt = DateTime.now();
  final tag = DateTime(jetzt.year, jetzt.month, jetzt.day);
  return List.generate(6, (i) {
    return Ticket(
      id: 800 + i,
      // Bewusst ein echter, langer Betreff aus der Produktion: ein kurzer
      // Platzhalter läuft nirgends über und würde nichts beweisen.
      subject: 'AU-Erneuerung – Krankmeldung läuft ab am 31.08.2026',
      message: 'Sehr geehrtes Mitglied, Ihre Krankmeldung läuft ab.',
      status: i.isEven ? 'open' : 'waiting_authority',
      priority: 'medium',
      memberName: 'Alexandra Katharina Musterfrau-Schmidt',
      memberNummer: 'M10002',
      createdAt: tag.add(Duration(hours: 8 + i)),
      scheduledDate: tag.add(Duration(hours: 8 + i)),
      totalTimeSeconds: 3600 + i,
    );
  });
}

Widget _bildschirm() => TicketverwaltungScreen(
      tickets: _tickets(),
      ticketStats: TicketStats(
        total: 528,
        open: 259,
        inProgress: 2,
        waitingMember: 0,
        waitingStaff: 0,
        waitingAuthority: 0,
        done: 267,
      ),
      isLoading: false,
      ticketFilter: 'all',
      mitgliedernummer: 'V10001',
      users: const [],
      onRefresh: () {},
      onFilterChanged: (_) {},
      onTicketAction: (_, __, {String? scheduledDate}) {},
    );

void main() {
  setUpAll(() => initializeDateFormatting('de_DE'));

  for (final fall in _groessen.entries) {
    testWidgets('Ticketverwaltung bei ${fall.key}', (tester) async {
      tester.view.physicalSize = fall.value.groesse * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final fehler = <String>[];
      final vorher = FlutterError.onError;
      FlutterError.onError = (details) {
        final text = details.exceptionAsString();
        if (!text.contains('overflowed') && !text.contains('RenderFlex')) return;
        final ort = RegExp(r'lib/[\w/]+\.dart:\d+:\d+')
                .firstMatch(details.toString())
                ?.group(0) ??
            'Ort unbekannt';
        final zeile = '${text.split('\n').first}  ← $ort';
        if (!fehler.contains(zeile)) fehler.add(zeile);
      };

      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: fall.value.groesse,
            devicePixelRatio: 3,
            textScaler: TextScaler.linear(fall.value.schrift),
          ),
          child: Scaffold(body: _bildschirm()),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));

      final inWoche = find.textContaining('#80').evaluate().length;

      // Auch die Tagesansicht zeichnen — sie ist der zweite Modus und wurde
      // bisher von keinem Test berührt.
      final umschalter = find.text('Heute');
      if (umschalter.evaluate().isNotEmpty) {
        await tester.tap(umschalter.last, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 300));
      }
      final inTag = find.textContaining('#80').evaluate().length;

      FlutterError.onError = vorher;
      tester.takeException();

      expect(fehler, isEmpty,
          reason: 'Layoutfehler bei ${fall.key}:\n${fehler.join('\n')}');
      expect(inWoche, greaterThan(0),
          reason: 'Wochenansicht zeigt bei ${fall.key} keine einzige '
              'Ticketkarte, obwohl sechs Tickets für heute vorliegen.');
      expect(inTag, greaterThan(0),
          reason: 'Tagesansicht zeigt bei ${fall.key} keine einzige '
              'Ticketkarte, obwohl sechs Tickets für heute vorliegen.');
    });
  }
}
