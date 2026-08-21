// Hell / Dunkel / System.
//
// Der wichtigste Test hier ist der letzte: er nagelt die Kopplung zwischen
// `MaterialApp.builder` und `F.istDunkel` fest. Fällt der Builder weg, werden
// die Material-Widgets weiterhin dunkel — die 17.000 umgestellten Farben aber
// bleiben hell. Das Ergebnis wäre heller Text auf hellen Karten in einer
// dunklen Anwendung, und kein einziger anderer Test würde etwas melden.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:icd360sev_vorsitzer/services/theme_service.dart';
import 'package:icd360sev_vorsitzer/utils/app_farben.dart';
import 'package:icd360sev_vorsitzer/utils/app_theme.dart';

/// ⚠️ `Color.r/g/b` liefern in dieser Flutter-Fassung Werte von 0 bis 1,
/// nicht 0 bis 255. Ohne die Umrechnung stehen alle Schwellen unten auf der
/// falschen Skala und der Test ist nur scheinbar streng.
double _helligkeit(Color c) =>
    (0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b) * 255;

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ThemeService.instance.modus.value = ThemeMode.system;
    F.istDunkel = false;
  });

  group('ThemeService', () {
    test('Voreinstellung ist System', () {
      expect(ThemeService.instance.modus.value, ThemeMode.system);
    });

    test('die Wahl übersteht einen Neustart', () async {
      await ThemeService.instance.setzen(ThemeMode.dark);
      ThemeService.instance.modus.value = ThemeMode.system; // „Neustart"
      await ThemeService.instance.laden();
      expect(ThemeService.instance.modus.value, ThemeMode.dark);
    });

    test('ein unlesbarer Eintrag fällt auf System zurück, nicht auf Hell',
        () async {
      SharedPreferences.setMockInitialValues({'app_theme_mode': 'kraut'});
      await ThemeService.instance.laden();
      expect(ThemeService.instance.modus.value, ThemeMode.system);
    });

    // ⚠️ Der erste Druck muss etwas BEWIRKEN. Ginge es von System stur nach
    // Hell, während das Gerät ohnehin hell steht, passierte sichtbar nichts
    // und der Knopf wirkte kaputt.
    test('aus System heraus wird auf das Gegenteil des Sichtbaren geschaltet',
        () async {
      await ThemeService.instance.weiterschalten(Brightness.light);
      expect(ThemeService.instance.modus.value, ThemeMode.dark);

      ThemeService.instance.modus.value = ThemeMode.system;
      await ThemeService.instance.weiterschalten(Brightness.dark);
      expect(ThemeService.instance.modus.value, ThemeMode.light);
    });

    test('danach läuft es rundum und erreicht System wieder', () async {
      await ThemeService.instance.weiterschalten(Brightness.light); // → dunkel
      await ThemeService.instance.weiterschalten(Brightness.dark); // → system
      expect(ThemeService.instance.modus.value, ThemeMode.system);
    });
  });

  group('Farbtokens', () {
    test('Flächen kippen, und zwar in die richtige Richtung', () {
      F.istDunkel = false;
      final hellFlaeche = F.flaeche;
      final hellText = F.textStark;
      F.istDunkel = true;

      expect(_helligkeit(hellFlaeche) > 200, isTrue,
          reason: 'im Hellmodus ist die Kartenfläche fast weiss');
      expect(_helligkeit(F.flaeche) < 60, isTrue,
          reason: 'im Dunkelmodus ist sie dunkel');
      // Schrift und Fläche müssen sich GEGENLÄUFIG bewegen — sonst steht am
      // Ende dunkle Schrift auf dunklem Grund.
      expect(_helligkeit(hellText) < 80, isTrue);
      expect(_helligkeit(F.textStark) > 200, isTrue);
    });

    test('blasse Tönungen werden dunkel, gesättigte Stufen bleiben Farbe', () {
      F.istDunkel = true;
      // shade50 war der Fehler, den erst eine Aufnahme gezeigt hat: ein
      // getöntes Weiss mitten in einer dunklen Fläche.
      expect(_helligkeit(F.h(Colors.red, 50)) < 70, isTrue);
      expect(_helligkeit(F.h(Colors.teal, 100)) < 80, isTrue);
      // Schrift in einer Farbe muss dagegen HELLER werden.
      expect(_helligkeit(F.h(Colors.red, 800)) >
              _helligkeit(Colors.red.shade800), isTrue);
    });

    test('im Hellmodus liefert h() unverändert die Material-Stufe', () {
      F.istDunkel = false;
      for (final stufe in [50, 100, 200, 300, 600, 700, 800, 900]) {
        expect(F.h(Colors.indigo, stufe), Colors.indigo[stufe]);
      }
    });

    // ⚠️ Die Regel, an der diese Umstellung zuerst gescheitert ist.
    //
    // Der erste Anlauf hat die Grautöne auf wenige sinngebende Tokens
    // zusammengefasst — im Dunkeln richtig, im Hellen aber wurde damit aus
    // `Colors.grey.shade600` (#757575) ein `#5A5F6B`. Ein Bildvergleich gegen
    // `origin/main` zeigte auf vier von fünf Bildschirmen 85–100 % abweichende
    // Bildpunkte: eine stille Umgestaltung des Hellmodus, die niemand verlangt
    // hatte. Seitdem steht in jeder Ersetzung links die ursprüngliche Farbe.
    test('im Hellmodus gibt JEDES Token exakt den alten Wert zurück', () {
      F.istDunkel = false;
      expect(F.flaeche, Colors.white);
      expect(F.textStark, Colors.black87);
      expect(F.hd(Colors.black54, Colors.white), Colors.black54);
      expect(F.hd(Colors.black12, Colors.white), Colors.black12);
      for (final stufe in [50, 100, 200, 300, 400, 500, 600, 700, 800, 900]) {
        expect(F.h(Colors.grey, stufe), Colors.grey[stufe],
            reason: 'grey.shade$stufe darf sich im Hellmodus nicht bewegen');
      }
      // `Colors.grey` ohne Stufe IST shade500 — die Umstellung schreibt dafür
      // `F.h(Colors.grey, 500)`, was im Hellen denselben Wert ergeben muss.
      // ⚠️ Gegen `.shade500` prüfen, nicht gegen `Colors.grey`: letzteres ist
      // eine MaterialColor, und `==` vergleicht auch den Laufzeittyp — der
      // Test wäre rot, obwohl beide denselben Farbwert tragen.
      expect(F.h(Colors.grey, 500), Colors.grey.shade500);
      expect(Colors.grey.shade500.toARGB32(), Colors.grey.toARGB32());
    });

    // Und das Gegenstück: das alte Thema bleibt im Hellmodus unangetastet.
    test('AppTheme.hell setzt keine Flächen — sonst kippt der ganze Untergrund',
        () {
      final alt = ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.saat, brightness: Brightness.light),
        useMaterial3: true,
      );
      expect(AppTheme.hell.scaffoldBackgroundColor,
          alt.scaffoldBackgroundColor,
          reason: 'genau hier wurde aus (248,249,255) ein (245,245,245)');
      expect(AppTheme.hell.canvasColor, alt.canvasColor);
      expect(AppTheme.hell.dividerColor, alt.dividerColor);
      expect(AppTheme.hell.cardTheme.color, alt.cardTheme.color);
      expect(AppTheme.hell.inputDecorationTheme.filled,
          alt.inputDecorationTheme.filled);
    });
  });

  // ⚠️ Das Bauen eines Themas darf den globalen Schalter NICHT verstellen.
  // `MaterialApp` wertet in jedem Aufbau beide Themen aus; als `_bauen` den
  // Wert noch stehen liess, gewann immer das zuletzt gebaute `darkTheme` und
  // `istDunkel` stand auch im Hellmodus auf `true`.
  test('AppTheme.hell/dunkel lassen F.istDunkel unberührt', () {
    F.istDunkel = false;
    AppTheme.dunkel;
    expect(F.istDunkel, isFalse);

    F.istDunkel = true;
    AppTheme.hell;
    expect(F.istDunkel, isTrue);
  });

  // ⚠️ DER Test dieser Datei.
  //
  // Die Tokens sind keine InheritedWidgets — ohne den erzwungenen Neuaufbau
  // in `F.uebernehmen` bleibt jede Fläche, die nur `F` liest, beim Umschalten
  // auf ihrer alten Farbe stehen. Genau so war es zuerst: `istDunkel` sprang
  // korrekt um, die Fläche blieb weiss. Auffällig wurde das erst in einem
  // Versuch mit einem echten Umschaltvorgang; Standbilder zeigen es nie, weil
  // die jeweils frisch gebaut werden.
  testWidgets('Umschalten im Betrieb färbt auch Flächen um, die nur F lesen',
      (tester) async {
    var modus = ThemeMode.light;
    late StateSetter setzeModus;

    await tester.pumpWidget(StatefulBuilder(builder: (ctx, setzen) {
      setzeModus = setzen;
      return MaterialApp(
        theme: AppTheme.hell,
        darkTheme: AppTheme.dunkel,
        themeMode: modus,
        builder: (c, child) {
          F.uebernehmen(c, Theme.of(c).brightness == Brightness.dark);
          return child ?? const SizedBox.shrink();
        },
        home: Scaffold(
          body: Builder(
            builder: (_) => Container(
                key: const Key('flaeche'), width: 40, height: 40,
                color: F.flaeche),
          ),
        ),
      );
    }));
    await tester.pumpAndSettle();

    Color gemalt() =>
        tester.widget<Container>(find.byKey(const Key('flaeche'))).color!;

    expect(_helligkeit(gemalt()) > 200, isTrue, reason: 'hell zu Beginn');

    setzeModus(() => modus = ThemeMode.dark);
    await tester.pumpAndSettle();

    expect(F.istDunkel, isTrue);
    expect(_helligkeit(gemalt()) < 60, isTrue,
        reason: 'die Fläche muss mitgekippt sein, nicht nur der Schalter');

    setzeModus(() => modus = ThemeMode.light);
    await tester.pumpAndSettle();
    expect(_helligkeit(gemalt()) > 200, isTrue, reason: 'und wieder zurück');
  });

  testWidgets('das dunkle Thema färbt auch, was niemand von Hand angefasst hat',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.hell,
      darkTheme: AppTheme.dunkel,
      themeMode: ThemeMode.dark,
      home: const Scaffold(body: Card(child: Text('x'))),
    ));
    await tester.pump();

    final thema = Theme.of(tester.element(find.byType(Card)));
    expect(thema.brightness, Brightness.dark);
    // Ohne gesetztes cardTheme bliebe die Karte in der M3-Vorgabe hell.
    expect(_helligkeit(thema.cardTheme.color!) < 60, isTrue);
    expect(_helligkeit(thema.scaffoldBackgroundColor) < 60, isTrue);
  });
}
