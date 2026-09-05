import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/models/blitz_nachricht.dart';
import 'package:icd360sev_vorsitzer/widgets/blitz_karte.dart';

BlitzNachricht _n({
  int conv = 1,
  String absender = 'Olena Musterfrau',
  List<String>? zeilen,
  String kanal = 'app',
}) =>
    BlitzNachricht(
      conversationId: conv,
      absender: absender,
      zeilen: zeilen ?? const ['Guten Tag'],
      kanal: kanal,
      zeit: DateTime(2026, 8, 26, 14, 5),
    );

Future<void> _karteBauen(
  WidgetTester tester, {
  required BlitzNachricht nachricht,
  Future<String?> Function(String)? onSenden,
  VoidCallback? onSchliessen,
  int wartend = 0,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: BlitzKarte(
        nachricht: nachricht,
        wartend: wartend,
        onSenden: onSenden ?? (_) async => null,
        onSchliessen: onSchliessen ?? () {},
      ),
    ),
  ));
}

void main() {
  group('BlitzNachricht — was zwischen zwei Engines reist', () {
    test('ergaenztUm haengt an, statt zu ersetzen', () {
      final n = _n(zeilen: ['Erste']).ergaenztUm('Zweite', DateTime(2026, 8, 26, 14, 6));
      expect(n.zeilen, ['Erste', 'Zweite']);
      expect(n.zeit.minute, 6, reason: 'die Zeit muss mitwandern');
    });

    test('mehr als fuenf Zeilen: die aeltesten fallen weg', () {
      var n = _n(zeilen: ['1']);
      for (final t in ['2', '3', '4', '5', '6', '7']) {
        n = n.ergaenztUm(t, DateTime(2026, 8, 26));
      }
      expect(n.zeilen.length, 5);
      expect(n.zeilen, ['3', '4', '5', '6', '7'],
          reason: 'gedeckelt, sonst waechst die Karte ueber den Bildschirm');
    });

    test('Rundreise durch JSON verliert nichts', () {
      final a = _n(conv: 42, zeilen: ['Eins', 'Zwei'], kanal: 'sms');
      final b = BlitzNachricht.entschluesselt(a.kodiert())!;
      expect(b.conversationId, 42);
      expect(b.absender, a.absender);
      expect(b.zeilen, ['Eins', 'Zwei']);
      expect(b.kanal, 'sms');
      expect(b.zeit, a.zeit);
    });

    test('leerer Absender wird nicht zum Anrede-Loch', () {
      final n = BlitzNachricht.fromJson({'conversation_id': 1, 'absender': '   '});
      expect(n.absender, 'Unbekannt');
    });

    test('Unsinn ergibt null statt einer Ausnahme', () {
      // Kaeme hier eine Ausnahme durch, riss sie im Blitz-Fenster den
      // Kanal-Handler ab — und danach zeigte das Fenster nie wieder etwas.
      expect(BlitzNachricht.entschluesselt('kein json'), isNull);
      expect(BlitzNachricht.entschluesselt('[1,2,3]'), isNull);
      expect(BlitzNachricht.entschluesselt(''), isNull);
      expect(BlitzNachricht.entschluesselt(null), isNull);
    });
  });

  group('BlitzKarte', () {
    testWidgets('zeigt Text und bei SMS den Kanal — aber NIE den Namen',
        (tester) async {
      // ⚠️ Hier stand einmal `expect(find.text('Olena Musterfrau'), ...)`. Die
      // Karte legt sich mitten auf den Bildschirm, auch wenn jemand
      // danebensteht; sie zeigt deshalb nur noch die Mitgliedsnummer.
      // Entscheidung des Users. Ohne Nummer steht „Mitglied" da, niemals
      // der Name — siehe [BlitzNachricht.nummer].
      await _karteBauen(tester,
          nachricht: _n(zeilen: ['Post vom Jobcenter da'], kanal: 'sms'));
      expect(find.text('Olena Musterfrau'), findsNothing);
      expect(find.text('Mitglied'), findsOneWidget);
      expect(find.text('Post vom Jobcenter da'), findsOneWidget);
      expect(find.textContaining('SMS'), findsOneWidget);
    });

    testWidgets('bei App-Chat steht kein SMS-Hinweis', (tester) async {
      await _karteBauen(tester, nachricht: _n());
      expect(find.textContaining('SMS'), findsNothing);
    });

    testWidgets('Eingabe schickt ab, Umschalt+Eingabe nicht', (tester) async {
      final gesendet = <String>[];
      await _karteBauen(tester,
          nachricht: _n(), onSenden: (t) async {
        gesendet.add(t);
        return null;
      });
      await tester.enterText(find.byType(TextField), 'Ja, gerne');
      await tester.pump();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(gesendet, isEmpty, reason: 'Umschalt+Eingabe ist eine neue Zeile');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(gesendet, ['Ja, gerne']);
    });

    testWidgets('Esc legt die Karte weg', (tester) async {
      var zu = 0;
      await _karteBauen(tester, nachricht: _n(), onSchliessen: () => zu++);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(zu, 1);
    });

    testWidgets('nach erfolgreichem Senden schliesst die Karte', (tester) async {
      var zu = 0;
      await _karteBauen(tester,
          nachricht: _n(), onSenden: (_) async => null, onSchliessen: () => zu++);
      await tester.enterText(find.byType(TextField), 'Text');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(zu, 1);
    });

    testWidgets('ein abgelehntes Senden sagt WARUM und bleibt offen',
        (tester) async {
      // Der stille Fehlschlag ist der eigentliche Feind: er sieht genauso aus
      // wie „ich habe danebengetippt". Dieselbe Lehre wie bei den Reaktionen.
      var zu = 0;
      await _karteBauen(tester,
          nachricht: _n(),
          onSenden: (_) async => 'Nicht angemeldet',
          onSchliessen: () => zu++);
      await tester.enterText(find.byType(TextField), 'Text');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(find.text('Nicht angemeldet'), findsOneWidget);
      expect(zu, 0, reason: 'der Text darf nicht verloren gehen');
      expect(find.text('Text'), findsOneWidget);
    });

    testWidgets('leerer Text wird gar nicht erst geschickt', (tester) async {
      var versuche = 0;
      await _karteBauen(tester, nachricht: _n(), onSenden: (_) async {
        versuche++;
        return null;
      });
      await tester.enterText(find.byType(TextField), '   ');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(versuche, 0);
    });

    testWidgets('zeigt an, wer noch wartet', (tester) async {
      // Der Zähler ist die Antwort darauf, dass bei zwei gleichzeitigen
      // Absendern der zweite unsichtbar blieb.
      await _karteBauen(tester, nachricht: _n(), wartend: 2);
      expect(find.text('noch 2'), findsOneWidget);
    });

    testWidgets('ohne Wartende steht kein Zaehler da', (tester) async {
      await _karteBauen(tester, nachricht: _n());
      expect(find.textContaining('noch '), findsNothing);
    });

  });
}
