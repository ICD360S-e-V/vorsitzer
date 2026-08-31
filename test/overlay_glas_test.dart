import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/notification_service.dart';
import 'package:icd360sev_vorsitzer/services/qualitaets_sonde.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';
import 'package:icd360sev_vorsitzer/utils/gespraechsqualitaet.dart';
import 'package:icd360sev_vorsitzer/widgets/guete_anzeige.dart';
import 'package:icd360sev_vorsitzer/widgets/sekunden_takt.dart';
import 'package:icd360sev_vorsitzer/widgets/sipgate_anruf_overlay.dart';

/// Die Glaskarte — und vor allem das, was an ihr NICHT nachgibt.
///
/// 🔴 WARUM ES DIESE DATEI GIBT
/// Die Karte lief bis zum 31.08.2026 an jeder Schriftgrösse über: gemessen
/// 11 px bei 1,0 · 58 px bei 1,3 · 106 px bei 1,6. Der gelb-schwarze
/// Überlaufbalken lag quer über der Güte-Anzeige, und niemandem ist es
/// aufgefallen, weil kein Test die Karte je bei vergrösserter Schrift gebaut
/// hat. Genau das tut dieser hier.
void main() {
  final dienst = SipgateService();

  QualitaetsProbe probe(double mos) => QualitaetsProbe(
        zeit: DateTime(2026, 8, 31),
        bewertung: Gespraechsqualitaet(
            r: mos * 20, mos: mos, verlustProzent: 1, rttMs: 90, pufferMs: 40),
        verlustProzent: 1,
        jitterMs: 8,
        pufferMs: 40,
        paketeEmpfangen: 500,
        paketeVerloren: 5,
      );

  SipgateGespraech gespraech(SipgateGespraechStand stand, {String? name}) =>
      SipgateGespraech(
        nummer: '+4973180159736',
        name: name,
        eingehend: stand == SipgateGespraechStand.klingelt,
        stand: stand,
        verbundenSeit: stand == SipgateGespraechStand.verbunden
            ? DateTime.now().subtract(const Duration(seconds: 134))
            : null,
      );

  Widget app(double skala) => MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(skala)),
        child: MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          home: const Scaffold(body: SizedBox.expand()),
        ),
      );

  /// Baut die Karte und gibt zurück, wie viele Überlauf-Meldungen dabei kamen.
  Future<int> bauen(
    WidgetTester t, {
    required double skala,
    required SipgateGespraechStand stand,
    QualitaetsProbe? guete,
    String? name,
    SipgateGespraech? zweites,
  }) async {
    final gefunden = <String>[];
    final alt = FlutterError.onError;
    FlutterError.onError = (d) {
      if (d.exceptionAsString().contains('overflow')) {
        gefunden.add(d.exceptionAsString());
      }
    };
    await t.pumpWidget(app(skala));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(stand, name: name), zweites: zweites);
    dienst.guete.value = guete;
    await t.pump();
    FlutterError.onError = alt;
    return gefunden.length;
  }

  tearDown(() {
    dienst.zustand.value = const SipgateZustand();
    dienst.guete.value = null;
    SipgateAnrufOverlay().unterdruecken(false);
  });

  // ── Überlauf ───────────────────────────────────────────────────────────
  for (final skala in [1.0, 1.3, 1.6]) {
    for (final f in [
      (4.3, 'gut'),
      (3.6, 'brauchbar'),
      (3.0, 'schlecht'),
      (2.0, 'kaum verständlich'),
    ]) {
      testWidgets('kein Überlauf bei Skala $skala und „${f.$2}"', (t) async {
        expect(
          await bauen(t,
              skala: skala,
              stand: SipgateGespraechStand.verbunden,
              guete: probe(f.$1)),
          0,
        );
      });
    }
  }

  testWidgets('kein Überlauf, wenn ein Name UND die Güte anliegen', (t) async {
    // Der engste Fall: dann steht in der Uhrzeile auch noch die Rufnummer.
    expect(
      await bauen(t,
          skala: 1.6,
          stand: SipgateGespraechStand.verbunden,
          guete: probe(2.0),
          name: 'Landratsamt Neu-Ulm'),
      0,
    );
  });

  for (final stand in [
    SipgateGespraechStand.klingelt,
    SipgateGespraechStand.waehlt,
  ]) {
    testWidgets('kein Überlauf bei $stand und grosser Schrift', (t) async {
      expect(await bauen(t, skala: 1.6, stand: stand), 0);
    });
  }

  // ── Die Scheibe ────────────────────────────────────────────────────────
  testWidgets('die Karte ist eine Scheibe, kein Farbblock', (t) async {
    await bauen(t, skala: 1.0, stand: SipgateGespraechStand.verbunden);
    // ⚠️ Auf `BackdropFilter` prüfen und nicht auf eine Farbe: die Unschärfe
    // IST die Gestaltung. Fällt sie beim Umbauen heraus, bleibt eine dunkle
    // Fläche zurück, die aussieht wie Absicht.
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  // ── Das Wort ───────────────────────────────────────────────────────────
  testWidgets('das Güte-Wort steht in Weiss, nicht in der Güte-Farbe',
      (t) async {
    await bauen(t,
        skala: 1.0,
        stand: SipgateGespraechStand.verbunden,
        guete: probe(2.0));
    final wort = t.widget<Text>(find.text('kaum verständlich'));
    // 🔴 Gemessen: Rot auf der Scheibe über einer weissen Fläche kommt auf
    // 2,09:1, Weiss auf 11,36:1. Wer das Wort einfärbt, macht es unlesbar —
    // und es sähe dabei besser aus.
    expect(wort.style?.color, Colors.white);
  });

  testWidgets('das Wort bekommt den ganzen Rest der Zeile, die Uhr den Vorrang',
      (t) async {
    await bauen(t,
        skala: 1.0,
        stand: SipgateGespraechStand.verbunden,
        guete: probe(2.0));

    // 🔴 WARUM HIER NICHT AUF „WIRD ABGESCHNITTEN" GEPRÜFT WIRD
    // Genau das war meine erste Fassung — `didExceedMaxLines` am
    // RenderParagraph. Sie schlug fehl, obwohl die Karte auf einer Randerung
    // mit echten Schriften alle vier Wörter vollständig zeigt: in der
    // Testumgebung gibt es die Schrift des Geräts nicht, es wird eine
    // Ersatzschrift gemalt, in der jedes Zeichen ein Quadrat ist. Gemessen:
    // „brauchbar" will dort 105,8 dp statt der 58,5 dp in Noto. Ein Test über
    // Textbreiten misst hier also eine Schrift, die auf dem Tablet nie
    // vorkommt — er wäre grün oder rot aus dem falschen Grund.
    //
    // Geprüft wird darum die REGEL, die den Platz schafft, und nicht ihr
    // Ergebnis: die Uhr nimmt sich, was sie braucht (gedeckelt), das Wort
    // bekommt mit `Expanded` den ganzen Rest. Mit zwei `Flexible` — der
    // ersten Fassung — bekäme das Wort eine starre Hälfte, und daneben stünde
    // „brauc…". Ob es am Ende passt, sagt nur eine Randerung mit echten
    // Schriften; die Zahlen dazu stehen im Quelltext der Karte.
    // ⚠️ Nicht „irgendein Expanded über dem Wort": die ganze Textspalte steckt
    // schon in einem. Diese Prüfung fand deshalb auch dann noch etwas, wenn das
    // Wort selbst nur ein `Flexible` bekam — die Gegenprobe blieb grün und der
    // Test prüfte nichts. Gefragt wird jetzt nach dem Expanded, dessen Kind
    // GENAU dieses Wort ist.
    final wort = find.text('kaum verständlich');
    final huellen =
        t.widgetList<Expanded>(find.ancestor(of: wort, matching: find.byType(Expanded)));
    expect(
      huellen.any((e) {
        final k = e.child;
        return k is Text && k.data == 'kaum verständlich';
      }),
      isTrue,
      reason: 'Das Güte-Wort selbst steht nicht in einem Expanded',
    );
    // Und die Uhr sitzt im Deckel — sonst frässe eine lange Uhrzeile
    // („In der Warteschleife · …", gemessen 166 dp von 177) alles auf.
    expect(
      find.ancestor(
          of: find.byType(SekundenTakt), matching: find.byType(ConstrainedBox)),
      findsWidgets,
      reason: 'Die Uhr steht nicht im 62-%-Deckel',
    );
  });

  testWidgets('ohne Messung steht KEIN Güte-Wort da', (t) async {
    await bauen(t, skala: 1.0, stand: SipgateGespraechStand.verbunden);
    // ⚠️ „noch nicht gemessen" darf nicht wie „unbrauchbar" aussehen. Eine
    // flache graue Welle wäre von der flachen roten nicht zu unterscheiden.
    for (final w in ['gut', 'brauchbar', 'schlecht', 'kaum verständlich']) {
      expect(find.text(w), findsNothing);
    }
    expect(find.byType(Welle), findsNothing);
  });

  // ── Die Welle trägt die Stufe auch ohne Farbe ──────────────────────────
  test('der Ausschlag der Welle fällt mit der Stufe', () {
    // 🔴 WCAG 1.4.1: die Farbe darf die Aussage nicht allein tragen. Wenn alle
    // Stufen gleich weit ausschlagen, bleibt nur die Farbe — und für zwei von
    // hundert Menschen ist Rot neben Grün dann dasselbe.
    final a = [
      QualitaetsStufe.gut,
      QualitaetsStufe.brauchbar,
      QualitaetsStufe.schlecht,
      QualitaetsStufe.unbrauchbar,
    ].map(Welle.ausschlag).toList();
    for (var i = 1; i < a.length; i++) {
      expect(a[i], lessThan(a[i - 1]),
          reason: 'Stufe $i schlägt nicht weniger aus als die davor');
    }
  });

  testWidgets('die Welle zeigt die Stufe des Messwerts', (t) async {
    await bauen(t,
        skala: 1.0,
        stand: SipgateGespraechStand.verbunden,
        guete: probe(3.0));
    expect(t.widget<Welle>(find.byType(Welle)).stufe, QualitaetsStufe.schlecht);
  });
}
