import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';
import 'package:icd360sev_vorsitzer/widgets/konferenz_dialog.dart';

/// Der Konferenz-Ablauf: Nummer eingeben, erste Person wartet, zusammenschalten.
///
/// 🔴 Vorher lagen die drei Schritte an drei Orten, und der Konferenzknopf
/// erschien erst, wenn schon ein zweiter Teilnehmer dazugewählt WAR — also
/// erst nach dem Schritt, zu dem er hinführen sollte. Gemeldet wurde das als
/// „der Knopf ist weg".
void main() {
  final dienst = SipgateService();

  const nummerVoll = '+4973180159736';
  // ⚠️ Von Hand geschrieben, also nachgezählt: `+4973180159736` hat DREIZEHN
  // Ziffern, sichtbar bleiben fünf, es stehen dort also genau acht Punkte.
  // Beim letzten Mal hatte ich einen zu wenig, und der Test schlug fehl,
  // obwohl der Code stimmte.
  const nummerVerdeckt = '+49········736';

  SipgateGespraech g(String nr,
          {bool gehalten = false,
          SipgateGespraechStand st = SipgateGespraechStand.verbunden}) =>
      SipgateGespraech(
        nummer: nr,
        eingehend: false,
        stand: st,
        gehalten: gehalten,
        verbundenSeit: DateTime.now().subtract(const Duration(seconds: 91)),
      );

  Future<void> oeffnen(WidgetTester t, {double skala = 1.0}) async {
    await t.pumpWidget(MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(skala)),
      child: MaterialApp(
        home: Builder(
          builder: (ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => konferenzAblauf(ctx),
                child: const Text('auf'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('auf'));
    await t.pumpAndSettle();
  }

  tearDown(() => dienst.zustand.value = const SipgateZustand());

  testWidgets('Schritt 1 fragt nach der Nummer und zeigt, wer schon dran ist',
      (t) async {
    dienst.zustand.value = SipgateZustand(gespraech: g(nummerVoll));
    await oeffnen(t);
    expect(find.text('Wen dazuholen?'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Anwählen'), findsOneWidget);
    // Und es steht da, was mit der ersten Person passiert.
    expect(find.textContaining('sie wartet'), findsOneWidget);
  });

  testWidgets('die Rufnummer steht auch hier verdeckt', (t) async {
    // ⚠️ Derselbe Grund wie auf der schwebenden Karte: der Dialog geht im
    // Gespräch auf, oft in der Öffentlichkeit.
    dienst.zustand.value = SipgateZustand(gespraech: g(nummerVoll));
    await oeffnen(t);
    expect(find.text(nummerVerdeckt), findsOneWidget);
    expect(find.textContaining(nummerVoll), findsNothing);
  });

  testWidgets('mit zweitem Teilnehmer wird daraus der Zusammenschalten-Schritt',
      (t) async {
    dienst.zustand.value = SipgateZustand(
      gespraech: g(nummerVoll, gehalten: true),
      zweites: g('+498912345678', st: SipgateGespraechStand.waehlt),
    );
    await oeffnen(t);
    expect(find.text('Beide zusammenschalten'), findsOneWidget);
    expect(find.text('Zusammenschalten'), findsOneWidget);
    expect(find.text('Wechseln'), findsOneWidget);
    // Die erste Person wartet — das muss dastehen, sonst wundert man sich
    // über die Stille auf der anderen Seite.
    expect(find.text('wartet'), findsOneWidget);
    expect(find.text('wird angewählt'), findsOneWidget);
  });

  testWidgets('der Hinweis „erst wenn abgehoben" steht im zweiten Schritt',
      (t) async {
    // 🔴 Der wichtigste Satz im Dialog. Für den zweiten Teilnehmer gibt es
    // KEIN Signal, wenn er abhebt — er kommt über die Anlage, nicht als
    // eigener SIP-Dialog. Wer zu früh drückt, schaltet ins Leere.
    dienst.zustand.value = SipgateZustand(
      gespraech: g(nummerVoll, gehalten: true),
      zweites: g('+498912345678', st: SipgateGespraechStand.waehlt),
    );
    await oeffnen(t);
    expect(find.textContaining('kann die App nicht erkennen'), findsOneWidget);
  });

  for (final skala in [1.0, 1.3, 1.6]) {
    testWidgets('kein Überlauf bei Textskala $skala', (t) async {
      final ueber = <String>[];
      final alt = FlutterError.onError;
      FlutterError.onError = (d) {
        if (d.exceptionAsString().contains('overflow')) ueber.add('x');
      };
      dienst.zustand.value = SipgateZustand(
        gespraech: g(nummerVoll, gehalten: true),
        zweites: g('+498912345678', st: SipgateGespraechStand.waehlt),
      );
      await oeffnen(t, skala: skala);
      FlutterError.onError = alt;
      expect(ueber, isEmpty);
    });
  }

  group('wann welcher Knopf gilt', () {
    test('starten geht, sobald ein Gespräch verbunden ist', () {
      dienst.zustand.value = SipgateZustand(gespraech: g(nummerVoll));
      expect(dienst.kannKonferenzStarten, isTrue);
      // ⚠️ Und `kannKonferenz` ist dabei FALSCH — es gibt ja noch keinen
      // zweiten. Genau diese Verwechslung war der gemeldete Fehler: als
      // Bedingung für den Einstiegsknopf war sie ein Kreis.
      expect(dienst.kannKonferenz, isFalse);
    });

    test('zusammenschalten geht erst mit einem zweiten Teilnehmer', () {
      dienst.zustand.value = SipgateZustand(
        gespraech: g(nummerVoll, gehalten: true),
        zweites: g('+498912345678', st: SipgateGespraechStand.waehlt),
      );
      expect(dienst.kannKonferenz, isTrue);
    });

    test('ohne Gespräch geht keines von beiden', () {
      dienst.zustand.value = const SipgateZustand();
      expect(dienst.kannKonferenzStarten, isFalse);
      expect(dienst.kannKonferenz, isFalse);
    });

    test('während es noch klingelt geht der Einstieg nicht', () {
      // ⚠️ Eine zweite Nummer zu einem klingelnden Anruf zu wählen ergibt
      // nichts — die Anlage hat noch kein Gespräch, in das sie sie stecken
      // könnte.
      dienst.zustand.value = SipgateZustand(
          gespraech: g(nummerVoll, st: SipgateGespraechStand.klingelt));
      expect(dienst.kannKonferenzStarten, isFalse);
    });
  });

  group('der Knopf im Vollbild', () {
    // Geprüft am Quelltext: der Zweig hängt am laufenden Gespräch eines
    // echten SIP-Stacks.
    final schirm =
        File('lib/screens/sipgate_screen.dart').readAsStringSync();

    test('hängt am EINSTIEG, nicht am Zusammenschalten', () {
      // 🔴 Der gemeldete Fehler. `kannKonferenz` ist erst wahr, wenn schon ein
      // zweiter dazugewählt IST — als Bedingung für den Einstiegsknopf ein
      // Kreis: man kam nie zum zweiten Teilnehmer, weil der Knopf erst
      // erschien, wenn es ihn schon gab.
      expect(schirm, contains('if (_dienst.kannKonferenzStarten)'));
    });

    test('und öffnet den Ablauf statt gleich *5 zu schicken', () {
      expect(schirm, contains('onPressed: () => konferenzAblauf(context)'));
    });
  });
}
