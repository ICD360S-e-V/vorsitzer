import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:icd360sev_vorsitzer/services/api_service.dart';
import 'package:icd360sev_vorsitzer/services/device_key_service.dart';
import 'package:icd360sev_vorsitzer/utils/visitenkarte_pdf.dart';
import 'package:icd360sev_vorsitzer/widgets/visitenkarte.dart';

/// Die Visitenkarte gegen die ECHTE Antwort des Servers.
///
/// Die Nutzdaten unten sind wörtlich das, was
/// `POST /api/auth/get_profile.php` für V27655 zurückgibt, und
/// `GET /api/admin/vereineinstellungen.php` für den Verein — beides am
/// 13.08.2026 abgefragt, nicht erfunden. Der Grund für diese Strenge steht in
/// der Speedtest-Geschichte: dort war der Bildschirm in Produktion grau, weil
/// kein einziger Test die tatsächliche Serverantwort berührt hat.
///
/// Drei Dinge kann nur ein Test wie dieser festhalten:
///   • dass `funktion` vom Server benutzt wird und nicht die alte, ungebeugte
///     Rolle („Vorsitzer" statt „1. Vorsitzender"),
///   • dass der Festnetz-Rückfall auf die Vereinsnummer greift, weil
///     `users.telefon_fix` bei allen Vorstandsmitgliedern NULL ist,
///   • dass `vorname2` NICHT stumpf angehängt wird.
class _AntwortClient extends http.BaseClient {
  final Map<String, dynamic> profil;
  final Map<String, dynamic>? verein;
  final List<String> aufgerufen = [];

  _AntwortClient({required this.profil, this.verein});

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final pfad = request.url.path;
    aufgerufen.add(pfad);

    if (pfad.endsWith('get_profile.php')) {
      return _json(profil);
    }
    if (pfad.endsWith('vereineinstellungen.php')) {
      if (verein == null) {
        // Der Fall „Vereinsdaten nicht erreichbar" — die Karte muss trotzdem
        // stehen.
        return _json({'success': false, 'message': 'Admin access required'},
            status: 403);
      }
      return _json({'success': true, 'data': verein});
    }
    return _json({'success': false}, status: 404);
  }

  http.StreamedResponse _json(Map<String, dynamic> body, {int status = 200}) =>
      http.StreamedResponse(
        Stream.value(utf8.encode(jsonEncode(body))),
        status,
        headers: {'content-type': 'application/json'},
      );
}

/// Wörtliche Serverantwort für V27655 (gekürzt auf die Felder, die die Karte
/// anfasst — die übrigen sind für sie unsichtbar).
Map<String, dynamic> _profilV27655({
  String? telefonFix,
  List<String>? languages,
  String funktion = '1. Vorsitzender',
  bool istGruender = true,
}) =>
    {
      'success': true,
      'mitgliedernummer': 'V27655',
      'email': 'icd@icd360s.de',
      'name': 'Ionut-Claudiu Duinea',
      'vorname': 'Ionut-Claudiu',
      // ⚠️ Das ist der Auslöser: vorname2 wiederholt die zweite Hälfte von
      // vorname. Stumpf angehängt stünde „Ionut-Claudiu Claudiu" auf der Karte.
      'vorname2': 'Claudiu',
      'nachname': 'Duinea',
      'geschlecht': 'M',
      'telefon_mobil': '016094482053',
      'telefon_fix': telefonFix,
      'languages': languages ?? ['de', 'ro', 'en'],
      'role': 'vorsitzer',
      'funktion': funktion,
      'ist_gruender': istGruender,
    };

const Map<String, dynamic> _vereinsdaten = {
  'vereinsname': 'ICD360S e.V.',
  // Spalte seit 13.08.2026. Wörtlich der Wert aus der Datenbank.
  'slogan': 'Integration · Chancen · Diversity · 360° Support',
  // Spalte seit 14.08.2026.
  'website': 'icd360s.de',
  'adresse': 'c/o Ionut-Claudiu Duinea\nElsa-Brandström-Straße 13\n89231 Neu-Ulm',
  'telefon_fix': '+49 731 80159736',
  'fax': '+49 731 80159737',
  // Vereins-Mobilnummer, seit 14.08.2026 in der Tabelle gefüllt.
  'mobil': '+49 160 94482053',
  'email': 'verein@icd360s.de',
  'registernummer': 'VR 201335',
  'registergericht': 'Amtsgericht Memmingen, Bayern',
  'gruendungsdatum': '01.08.2025',
};

Future<void> _zeigeKarte(WidgetTester tester, _AntwortClient client) async {
  ApiService().testClient = client;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 900,
        height: 700,
        child: Visitenkarte(
          mitgliedernummer: 'V27655',
          apiService: ApiService(),
        ),
      ),
    ),
  ));
  // Zwei Durchläufe: einer für die beiden Netzantworten, einer für den
  // AnimatedSwitcher.
  await tester.pumpAndSettle();
}

void main() {
  // Ohne Device-Key wirft `_headers`, bevor ein Request überhaupt losgeht —
  // jeder Test wäre dann grün, ohne den Client je erreicht zu haben. Deshalb
  // prüfen die Tests unten zusätzlich, was tatsächlich aufgerufen wurde.
  setUp(() {
    DeviceKeyService().setTestCredentials('TESTKEY');
  });

  group('Vorderseite', () {
    testWidgets('zeigt Vereinsname und Slogan aus der Datenbank',
        (tester) async {
      final c = _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten);
      await _zeigeKarte(tester, c);

      expect(c.aufgerufen.where((p) => p.endsWith('get_profile.php')).length, 1);
      expect(find.text('ICD360S e.V.'), findsOneWidget);
      expect(find.text(_vereinsdaten['slogan'] as String), findsOneWidget);
    });

    testWidgets('der Slogan kommt aus der Spalte, nicht aus der Konstante',
        (tester) async {
      // Die Quelle ist `vereineinstellungen.slogan`. Stünde dort etwas
      // anderes, müsste das auf der Karte stehen — sonst wäre die Spalte
      // schmückendes Beiwerk und die Karte zeigte für immer den Code-Stand.
      final v = Map<String, dynamic>.from(_vereinsdaten)
        ..['slogan'] = 'Ein ganz anderer Satz';

      await _zeigeKarte(
          tester, _AntwortClient(profil: _profilV27655(), verein: v));

      expect(find.text('Ein ganz anderer Satz'), findsOneWidget);
      expect(find.text(kVisitenkarteSlogan), findsNothing);
    });

    testWidgets('leere Slogan-Spalte lässt die Zeile nicht verschwinden',
        (tester) async {
      final v = Map<String, dynamic>.from(_vereinsdaten)..['slogan'] = '';

      await _zeigeKarte(
          tester, _AntwortClient(profil: _profilV27655(), verein: v));

      expect(find.text(kVisitenkarteSlogan), findsOneWidget);
    });

    testWidgets('das Gradzeichen ist U+00B0, nicht das Wort und nicht U+00BA',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      // U+00BA (º, spanischer Ordnungsindikator) sieht in vielen Schriften
      // fast gleich aus und wäre nur im Bytevergleich zu erkennen.
      expect(kVisitenkarteSlogan, contains('360°'));
      expect(kVisitenkarteSlogan, isNot(contains('º')));
      expect(kVisitenkarteSlogan, isNot(contains('Grad')));
      expect(find.textContaining('360°'), findsOneWidget);
    });

    testWidgets('setzt den Namen auf EINE Zeile, ohne vorname2 zu doppeln',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      // ⚠️ `findRichText: true` ist Pflicht: die Namenszeile ist ein
      // `Text.rich`, weil der Nachname auf derselben Zeile halbfett steht.
      // Ohne das Flag findet der Sucher den Text nicht und der Test wäre
      // grün, ohne je etwas geprüft zu haben.
      expect(find.text('Ionut-Claudiu Duinea', findRichText: true),
          findsOneWidget);
      // Der Fehler, der behoben wurde: vorname2 stumpf angehängt.
      expect(find.text('Ionut-Claudiu Claudiu Duinea', findRichText: true),
          findsNothing);
      // Und Vor- und Nachname stehen NICHT mehr getrennt untereinander.
      expect(find.text('Duinea'), findsNothing);
    });

    testWidgets('behält einen mehrteiligen Vornamen vollständig',
        (tester) async {
      // K91719: der alte Leerzeichen-Split machte hieraus Vorname „Andreea"
      // und Nachname „Denisa Camelia Raduica".
      final p = _profilV27655()
        ..['vorname'] = 'Andreea Denisa Camelia'
        ..['vorname2'] = null
        ..['nachname'] = 'Raduica'
        ..['name'] = 'Andreea Denisa Camelia Raduica';

      await _zeigeKarte(
          tester, _AntwortClient(profil: p, verein: _vereinsdaten));

      expect(find.text('Andreea Denisa Camelia Raduica', findRichText: true),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('nimmt das gebeugte Amt vom Server, nicht die rohe Rolle',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      // ⚠️ Amt und „Gründer" stehen seit der minimalistischen Fassung in
      // EINER Zeile, nicht mehr in zwei Pillen — eine Pille kostete Farbfläche
      // und brachte nichts dazu.
      expect(find.text('1. Vorsitzender  ·  Gründer'), findsOneWidget);
      expect(find.textContaining('Vorsitzer '), findsNothing);
    });

    testWidgets('zeigt die zweite Vorsitzende weiblich und ohne Gründer-Pille',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(
          profil: _profilV27655(funktion: '2. Vorsitzende', istGruender: false),
          verein: _vereinsdaten,
        ),
      );

      expect(find.text('2. Vorsitzende'), findsOneWidget);
      expect(find.textContaining('Gründer'), findsNothing);
    });

    testWidgets('zeigt die Anschlüsse des VEREINS, nicht die der Person',
        (tester) async {
      // ⚠️ Entscheidung des Users vom 14.08.2026. Eine Visitenkarte wird
      // weitergegeben und liegt danach in fremden Ablagen — wer sie in fünf
      // Jahren hervorholt, soll den Verein erreichen, auch wenn die Person
      // längst nicht mehr im Vorstand ist. Private Anschlüsse würden mit der
      // Karte weiterwandern und blieben erreichbar, lange nachdem sie es
      // sollten.
      await _zeigeKarte(
        tester,
        _AntwortClient(
          // Diese Person HAT eine eigene Durchwahl und eine eigene Mobilnummer.
          profil: _profilV27655(telefonFix: '+49 731 111111'),
          verein: _vereinsdaten,
        ),
      );

      expect(find.text('+49 731 80159736'), findsOneWidget); // Verein
      expect(find.text('+49 160 94482053'), findsOneWidget); // Verein
      expect(find.text('+49 731 111111'), findsNothing);     // privat
      expect(find.text('016094482053'), findsNothing);       // privat
    });

    testWidgets('das Fax steht unter dem Festnetz', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      expect(find.text('+49 731 80159737'), findsOneWidget);
      // ⚠️ Die Reihenfolge ist nicht beliebig: Anschluss und Fax sind
      // `…36` und `…37`, dieselbe Leitung. Untereinander liest man sie als
      // Paar, auseinandergerissen als zwei Zufälle.
      final tel = tester.getCenter(find.text('+49 731 80159736'));
      final fax = tester.getCenter(find.text('+49 731 80159737'));
      final mob = tester.getCenter(find.text('+49 160 94482053'));
      expect(fax.dy, greaterThan(tel.dy));
      expect(mob.dy, greaterThan(fax.dy));
    });

    testWidgets('die E-Mail kommt weiter aus users.email', (tester) async {
      // Duinea hat icd@icd360s.de, Weber mcw@icd360s.de — Vereinsadressen, die
      // schon in der Tabelle stehen. Es braucht also keine abgeleitete
      // Adresse aus der Mitgliedsnummer.
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );
      expect(find.text('icd@icd360s.de'), findsOneWidget);
    });

    testWidgets('zeigt je Sprache nur die Fahne, ohne Kürzel darunter',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      // ⚠️ Die Kürzel „DE · RO · EN" standen bis zum 14.08.2026 unter den
      // Fahnen und sind auf Entscheidung des Users entfallen. Wer sie wieder
      // einbaut, bricht hier — das ist der Zweck dieser drei Zeilen.
      expect(find.text('DE'), findsNothing);
      expect(find.text('RO'), findsNothing);
      expect(find.text('EN'), findsNothing);

      // Drei Fahnen, in der Reihenfolge der Sprachen.
      for (final pfad in const [
        'assets/flaggen/de.png',
        'assets/flaggen/ro.png',
        'assets/flaggen/en.png',
      ]) {
        expect(
            find.byWidgetPredicate((w) =>
                w is Image &&
                w.image is AssetImage &&
                (w.image as AssetImage).assetName == pfad),
            findsOneWidget,
            reason: 'Fahne fehlt: $pfad');
      }

      // ⚠️ Ohne Kürzel trägt allein die Beschriftung die Sprache für
      // Vorleseprogramme — eine Fahne ist für sie ein stummes Bild. Sie nennt
      // die Sprache ausgeschrieben, also mehr als das Kürzel je sagte.
      expect(find.bySemanticsLabel('Sprache: Deutsch'), findsOneWidget);
      expect(find.bySemanticsLabel('Sprache: Rumänisch'), findsOneWidget);
      expect(find.bySemanticsLabel('Sprache: Englisch'), findsOneWidget);

      // Das Rollstuhlzeichen steht über den Sprachen — als Bilddatei, damit
      // Karte und Ausdruck dasselbe zeigen (siehe kIkonen).
      expect(
          find.byWidgetPredicate((w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'assets/ikonen/accessible.png'),
          findsOneWidget);
    });

    testWidgets('trägt den Webauftritt unten rechts', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      expect(find.text(kVisitenkarteWeb), findsOneWidget);
      expect(find.byIcon(Icons.language), findsOneWidget);

      // ⚠️ Die Benutzernummer steht wieder unten links — auf Entscheidung des
      // Users (13.08.2026), nachdem sie kurz entfernt war. Sie ist zugleich
      // der Anmeldename; dass sie hier steht, ist gewollt und kein Versehen.
      expect(find.text('V27655'), findsOneWidget);

      // Der Globus gehört in die rechte untere Ecke, die Nummer nach links.
      final globus = tester.getCenter(find.byIcon(Icons.language));
      final nummer = tester.getCenter(find.text('V27655'));
      final karte = tester.getRect(find.byKey(const ValueKey('front')));
      expect(globus.dx, greaterThan(nummer.dx));
      expect(globus.dy, greaterThan(karte.center.dy));
    });

    testWidgets('zeigt zu jeder Sprache eine Fahne als Bilddatei',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      // ⚠️ Bilddatei, nicht Emoji. Auf Windows bildet Segoe UI Emoji die
      // Regional-Indicator-Paare nicht ab; dort stand vorher nur der Code.
      final bilder = tester
          .widgetList<Image>(find.byType(Image))
          .map((b) => (b.image as AssetImage).assetName)
          .toList();
      expect(bilder, containsAll(<String>[
        'assets/flaggen/de.png',
        'assets/flaggen/ro.png',
        'assets/flaggen/en.png',
      ]));
    });

    testWidgets('die Web-Adresse kommt aus der Spalte, nicht aus dem Code',
        (tester) async {
      // ⚠️ Vorher stand sie nur als Konstante im Code. Stünde in der Spalte
      // etwas anderes, müsste das auf der Karte stehen — sonst wäre die
      // Spalte Zierde und die Karte zeigte für immer den Code-Stand.
      final v = Map<String, dynamic>.from(_vereinsdaten)
        ..['website'] = 'beispiel.test';

      await _zeigeKarte(
          tester, _AntwortClient(profil: _profilV27655(), verein: v));

      expect(find.text('beispiel.test'), findsOneWidget);
      expect(find.text(kVisitenkarteWeb), findsNothing);
    });

    testWidgets('leere Spalte lässt die Fußzeile nicht leer', (tester) async {
      final v = Map<String, dynamic>.from(_vereinsdaten)..['website'] = '';
      await _zeigeKarte(
          tester, _AntwortClient(profil: _profilV27655(), verein: v));
      expect(find.text(kVisitenkarteWeb), findsOneWidget);
    });

    testWidgets('bietet den Druckbogen an', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      // Die Zahl im Knopf kommt aus der Bogen-Geometrie, nicht aus dem Text —
      // wer das Raster ändert, ändert die Beschriftung mit.
      expect(find.text('$kKartenProBogen Karten als PDF'), findsOneWidget);
      expect(kKartenProBogen, 10);
    });

    testWidgets('bleibt ohne hinterlegte Sprachen vollständig', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(
          profil: _profilV27655(languages: const []),
          verein: _vereinsdaten,
        ),
      );

      expect(find.text('DE'), findsNothing);
      // Name, Amt und Symbol stehen trotzdem.
      expect(find.textContaining('1. Vorsitzender'), findsOneWidget);
      expect(
          find.byWidgetPredicate((w) =>
              w is Image &&
              w.image is AssetImage &&
              (w.image as AssetImage).assetName ==
                  'assets/ikonen/accessible.png'),
          findsOneWidget);
    });

    testWidgets('steht auch ohne erreichbare Vereinsdaten', (tester) async {
      // vereineinstellungen.php verlangt eine Admin-Rolle. Schlägt es fehl,
      // dürfen Name, Amt und E-Mail nicht mit verschwinden.
      final c = _AntwortClient(profil: _profilV27655(), verein: null);
      await _zeigeKarte(tester, c);

      expect(find.textContaining('1. Vorsitzender'), findsOneWidget);
      expect(find.text('icd@icd360s.de'), findsOneWidget);
      // Rückfall auf den eingebauten Namen, statt einer leeren Kopfzeile.
      expect(find.text('ICD360S e.V.'), findsOneWidget);
      // ⚠️ Beide Rufnummern entfallen ersatzlos — sie stehen NUR in den
      // Vereinsdaten. Lieber eine Karte ohne Nummer als eine mit erfundener.
      expect(find.text('+49 731 80159736'), findsNothing);
      expect(find.text('+49 160 94482053'), findsNothing);
    });
  });

  group('Rückseite', () {
    Future<void> umdrehen(WidgetTester tester) async {
      await tester.tap(find.text('Rückseite'));
      await tester.pumpAndSettle();
    }

    testWidgets('zeigt die Schlagwörter aus der Satzung', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );
      await umdrehen(tester);

      expect(find.text('Was wir tun'), findsOneWidget);
      // ⚠️ Schlagwörter statt Sätze: die alten sechs Zeilen brachen auf 85 mm
      // um und mussten dafür auf 5,8 pt herunter — unter das Druckminimum von
      // 7 pt. Jedes Wort steht wörtlich in der Satzung, siehe
      // kVisitenkarteSchlagworte.
      for (final w in kVisitenkarteSchlagworte) {
        expect(find.textContaining(w, findRichText: true), findsWidgets,
            reason: 'Schlagwort fehlt: $w');
      }
      // Der alte Platzhalter ist weg.
      expect(find.textContaining('kommt bald'), findsNothing);
    });

    testWidgets('trägt den Leitsatz und die Abgrenzung nach § 3 Abs. 4',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );
      await umdrehen(tester);

      expect(find.text(kVisitenkarteLeitsatz), findsOneWidget);
      // Ohne diesen Satz kann eine weitergereichte Karte den Verein wie eine
      // Rechtsberatungsstelle aussehen lassen.
      expect(find.text(kVisitenkarteAbgrenzung), findsOneWidget);
    });

    testWidgets('lässt die c/o-Zeile in der Anschrift weg', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );
      await umdrehen(tester);

      expect(
        find.text('Elsa-Brandström-Straße 13 · 89231 Neu-Ulm'),
        findsOneWidget,
      );
      expect(find.textContaining('c/o'), findsNothing);
      expect(find.textContaining('VR 201335'), findsOneWidget);
    });

    testWidgets('lässt sich wieder auf die Vorderseite drehen', (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );
      await umdrehen(tester);
      expect(find.textContaining('1. Vorsitzender'), findsNothing);

      await tester.tap(find.text('Vorderseite'));
      await tester.pumpAndSettle();
      expect(find.textContaining('1. Vorsitzender'), findsOneWidget);
    });
  });

  group('Format', () {
    testWidgets('ist so breit wie eine Visitenkarte und mindestens so hoch',
        (tester) async {
      await _zeigeKarte(
        tester,
        _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten),
      );

      final karte = tester.getSize(find.byKey(const ValueKey('front')));
      expect(karte.width, 480);
      // Die Mindesthöhe ist 480 / 1,545 = 310,6. Vorher war die Karte
      // 902 × 280, also 3,2 : 1 — ein Banner, kein Kartenformat.
      expect(karte.height, greaterThanOrEqualTo(310));
      expect(tester.takeException(), isNull);

      // ⚠️ Das EXAKTE Verhältnis wird hier bewusst NICHT geprüft. Der
      // Testbaukasten rendert ohne echte Schrift; die Ersatzmetrik macht jede
      // Zeile höher, und die Karte kam auf 480 × 356 statt 480 × 310,6. Mit
      // geladener Noto Sans stimmen die 1,545 auf drei Stellen — das ist die
      // Golden-Prüfmappe (test/_ansicht_visitenkarte.dart), nicht dieser Test.
      // Eine schriftabhängige Zahl hier wäre in der CI zufällig rot oder grün.
    });

    testWidgets('wird auf einem schmalen Schirm schmaler statt abgeschnitten',
        (tester) async {
      ApiService().testClient =
          _AntwortClient(profil: _profilV27655(), verein: _vereinsdaten);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 360, // Pixel-Telefon
            height: 700,
            child: Visitenkarte(
              mitgliedernummer: 'V27655',
              apiService: ApiService(),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final karte = tester.getSize(find.byKey(const ValueKey('front')));
      expect(karte.width, lessThanOrEqualTo(360 - 48)); // abzüglich Polster
      expect(tester.takeException(), isNull);
    });
  });
}
