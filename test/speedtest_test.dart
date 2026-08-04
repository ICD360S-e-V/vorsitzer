import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/speedtest_screen.dart';
import 'package:icd360sev_vorsitzer/services/speedtest_service.dart';

/// Der Speedtest misst gegen den eigenen Server und soll belegen, ob Telekom
/// auf Business Mobil L liefert, was der Vertrag verspricht. Die Messreihe ist
/// damit ein Beweismittel — Fehler darin dürfen nicht nach „unruhige Leitung"
/// aussehen, sondern müssen auffallen.
void main() {
  group('Diagrammreihen je Gerät', () {
    // Der Server liefert bei „Alle Geräte" nach ZEIT sortiert, also zwischen
    // den Geräten verschränkt. Genau so sieht die Liste hier aus.
    final verschraenkt = <Map<String, dynamic>>[
      {'t': '2026-08-04 08:00:00', 'geraet': 'tablet', 'down': 140.0},
      {'t': '2026-08-04 08:01:00', 'geraet': 'desktop', 'down': 900.0},
      {'t': '2026-08-04 08:30:00', 'geraet': 'tablet', 'down': 45.0},
      {'t': '2026-08-04 08:31:00', 'geraet': 'desktop', 'down': 910.0},
    ];

    test('verschränkte Punkte werden nach Gerät getrennt, Reihenfolge bleibt', () {
      final gruppen = gruppiereNachGeraet(verschraenkt);

      expect(gruppen.keys, containsAll(<String>['tablet', 'desktop']));
      expect(gruppen['tablet'], [0, 2]);
      expect(gruppen['desktop'], [1, 3]);
    });

    test('ein einzelnes Gerät ergibt genau eine Reihe', () {
      final gruppen = gruppiereNachGeraet([
        {'t': '2026-08-04 08:00:00', 'geraet': 'tablet', 'down': 140.0},
        {'t': '2026-08-04 08:30:00', 'geraet': 'tablet', 'down': 45.0},
      ]);

      expect(gruppen, hasLength(1));
      expect(gruppen['tablet'], [0, 1]);
    });

    test('leere Reihe kippt nicht um', () {
      expect(gruppiereNachGeraet(const []), isEmpty);
    });

    test('Punkte ohne Gerätefeld landen in einem eigenen Topf statt verloren '
        'zu gehen', () {
      final gruppen = gruppiereNachGeraet([
        {'t': '2026-08-04 08:00:00', 'down': 140.0},
        {'t': '2026-08-04 08:30:00', 'geraet': 'tablet', 'down': 45.0},
      ]);

      expect(gruppen, hasLength(2));
      expect(gruppen[''], [0]);
    });
  });

  group('Messergebnis', () {
    SpeedtestErgebnis ergebnis({
      double download = 140,
      Map<String, dynamic>? netz,
      String? fehler,
      double downloadFenster = 1.0,
    }) =>
        SpeedtestErgebnis(
          gemessenAm: DateTime(2026, 8, 4, 8, 30),
          dauerSekunden: 12,
          downloadMbps: download,
          uploadMbps: 42,
          pingMinMs: 18,
          pingAvgMs: 24,
          jitterMs: 3,
          downloadBytes: 26214400,
          uploadBytes: 10485760,
          downloadFensterSekunden: downloadFenster,
          uploadFensterSekunden: 0.9,
          streams: 4,
          netz: netz,
          fehler: fehler,
        );

    test('was das Netz zu können behauptet, kommt in Mbit/s an', () {
      // NetworkCapabilities liefert kbit/s. Ungerechnet stünde im Vergleich
      // „150000 gemeldet gegen 140 gemessen" — der Vergleich, auf den es
      // ankommt, wäre um Faktor 1000 daneben.
      final e = ergebnis(netz: {'gemeldet_down_kbps': 150000});
      expect(e.gemeldetDownMbps, 150);
    });

    test('ohne Netzangabe gibt es keine erfundene Zahl', () {
      expect(ergebnis(netz: null).gemeldetDownMbps, isNull);
      expect(ergebnis(netz: {'transport': 'cellular'}).gemeldetDownMbps, isNull);
    });

    test('die Mobilfunkgeneration wird durchgereicht, nicht aus dem Transport '
        'geraten', () {
      // 5G-NSA meldet sich bei getDataNetworkType() als LTE. Steht die
      // Generation im Datensatz, hat sie Vorrang vor allem anderen.
      expect(
        ergebnis(netz: {'transport': 'cellular', 'netz_generation': '5G-NSA'}).generation,
        '5G-NSA',
      );
      // Ohne Generation bleibt nur der Transport — und das ist auch alles,
      // was dann behauptet werden darf.
      expect(ergebnis(netz: {'transport': 'wifi'}).generation, 'wifi');
      expect(ergebnis(netz: null).generation, 'unbekannt');
    });

    test('ein Fehlversuch bleibt ein Datensatz und wird als solcher gemeldet', () {
      // Eine Lücke in der Reihe wäre schlimmer als ein Fehlerpunkt: gerade der
      // Ausfall ist das, was belegt werden soll.
      final e = ergebnis(fehler: 'timeout');
      expect(e.erfolgreich, isFalse);
      expect(e.toJson()['fehler'], 'timeout');
    });

    test('das Messfenster steht im Datensatz, damit weiche Werte erkennbar '
        'bleiben', () {
      // Deutlich unter einer Sekunde heißt: die Übertragung war zu kurz, um
      // den TCP-Slow-Start hinter sich zu lassen, der Wert ist eher zu
      // niedrig. Das gehört in die Daten, nicht nur in die Anzeige.
      final j = ergebnis(downloadFenster: 0.12).toJson();
      expect(j['download_fenster_s'], 0.12);
    });
  });

  group('Drei Geräte am selben Konto', () {
    // Der Verein ist gleichzeitig von Tablet, MacBook und Desktop angemeldet.
    // Messen zwei davon zusammen, teilen sie sich die Leitung; am selben WLAN
    // misst dann jedes die Hälfte. Ein solcher Einbruch ist hausgemacht und
    // darf nicht als Beleg gegen Telekom durchgehen.

    test('ein ausgelassener Lauf ist kein Fehler und keine Nullmessung', () {
      final e = SpeedtestErgebnis.uebersprungen(DateTime(2026, 8, 4, 8, 30));

      expect(e.uebersprungen, isTrue);
      // Nicht „erfolgreich" — sonst ginge er als 0 Mbit/s in den Schnitt ein.
      expect(e.erfolgreich, isFalse);
      // Aber auch kein Fehler — sonst verfälschte er die Fehlerquote mit
      // etwas, das das Netz nicht zu verantworten hat.
      expect(e.fehler, isNull);
    });

    test('eine Messung neben einem anderen Gerät wird als solche markiert', () {
      final e = SpeedtestErgebnis(
        gemessenAm: DateTime(2026, 8, 4, 8, 30),
        dauerSekunden: 12, downloadMbps: 70, uploadMbps: 20,
        pingMinMs: 18, pingAvgMs: 24, jitterMs: 3,
        downloadBytes: 26214400, uploadBytes: 10485760,
        downloadFensterSekunden: 1, uploadFensterSekunden: 1,
        streams: 4, netz: null, fehler: null,
        alleine: false,
      );

      expect(e.alleine, isFalse);
      // Der Vermerk muss bis in die Datenbank durchschlagen, nicht nur in die
      // Anzeige — beim Auswerten in zwei Jahren sieht niemand mehr den Screen.
      expect(e.toJson()['alleine'], isFalse);
    });

    test('im Normalfall gilt eine Messung als allein und koordiniert', () {
      final e = SpeedtestErgebnis(
        gemessenAm: DateTime(2026, 8, 4, 8, 30),
        dauerSekunden: 12, downloadMbps: 140, uploadMbps: 42,
        pingMinMs: 18, pingAvgMs: 24, jitterMs: 3,
        downloadBytes: 26214400, uploadBytes: 10485760,
        downloadFensterSekunden: 1, uploadFensterSekunden: 1,
        streams: 4, netz: null, fehler: null,
      );

      expect(e.alleine, isTrue);
      expect(e.koordiniert, isTrue);
      expect(e.erfolgreich, isTrue);
    });
  });

  group('Ehrlichkeit der Messwerte', () {
    SpeedtestErgebnis mit({
      int timeouts = 0,
      int httpFehler = 0,
      int proben = 12,
      double? lastDownMax,
      int lastDownProben = 0,
      double? lastUpMax,
      int lastUpProben = 0,
    }) =>
        SpeedtestErgebnis(
          gemessenAm: DateTime(2026, 8, 4, 8, 30),
          dauerSekunden: 12, downloadMbps: 140, uploadMbps: 42,
          pingMinMs: 18, pingAvgMs: 24, jitterMs: 3,
          downloadBytes: 26214400, uploadBytes: 10485760,
          downloadFensterSekunden: 1, uploadFensterSekunden: 1,
          streams: 4, netz: null, fehler: null,
          anfragenTimeout: timeouts,
          anfragenHttpFehler: httpFehler,
          latenzProben: proben,
          lastlatenzDownMaxMs: lastDownMax,
          lastlatenzDownProben: lastDownProben,
          lastlatenzUpMaxMs: lastUpMax,
          lastlatenzUpProben: lastUpProben,
        );

    test('es gibt kein Feld mehr, das Paketverlust behauptet', () {
      // Über TCP verschwindet echter Verlust in Retransmits — 3 % Verlust
      // ergäben zuverlässig 0,0 %. Eine nie gemessene Größe als gemessen
      // auszuweisen ist der Punkt, an dem die Gegenseite nicht einen Wert,
      // sondern die Methode angreift.
      final j = mit(timeouts: 2).toJson();
      expect(j.containsKey('paketverlust_prozent'), isFalse);
      expect(j['anfragen_timeout'], 2);
      expect(j['latenz_proben'], 12);
    });

    test('Serverfehler werden von Netzfehlern getrennt gezählt', () {
      // Bei einer JWT-Rotation liefern alle Proben 401. Ohne die Trennung
      // stünde in der Beweisreihe „100 % Paketverlust" — obwohl es unser
      // eigener Server war.
      final j = mit(httpFehler: 12, proben: 12).toJson();
      expect(j['anfragen_http_fehler'], 12);
      expect(j['anfragen_timeout'], 0);
    });

    test('Latenz unter Last wird unter fünf Proben gar nicht behauptet', () {
      // Bei zwei Messwerten wäre ein „Maximum" ein Zufallswert. In einer
      // Beweisreihe ist ein fehlender Wert besser als ein weicher.
      expect(mit(lastUpMax: 900, lastUpProben: 2).lastlatenzMaxMs, isNull);
      expect(mit(lastUpMax: 900, lastUpProben: 5).lastlatenzMaxMs, 900);
    });

    test('von beiden Richtungen zählt die schlechtere', () {
      final e = mit(
        lastDownMax: 300, lastDownProben: 6,
        lastUpMax: 950, lastUpProben: 8,
      );
      expect(e.lastlatenzMaxMs, 950);
    });
  });

  group('Messplan', () {
    test('Vorgaben entsprechen dem, was der Datenverbrauch hergibt', () {
      const p = SpeedtestPlan();
      // 25 MB + 10 MB je Lauf, alle 30 Minuten ≈ 1,7 GB am Tag. Auf Business
      // Mobil L gedeckt (kein Drosselungssatz im Tarif), aber die Zahlen
      // sollen nicht unbemerkt wachsen.
      expect(p.downloadBytes, 25 * 1024 * 1024);
      expect(p.uploadBytes, 10 * 1024 * 1024);
      expect(p.streams, 4);
    });

    test('Server darf die Größen nachregeln, ohne dass die App neu muss', () {
      final p = SpeedtestPlan.fromJson({
        'download_bytes': 5 * 1024 * 1024,
        'upload_bytes': 2 * 1024 * 1024,
        'streams': 2,
        'aufwaerm_ms': 500,
        'latenz_proben': 20,
      });
      expect(p.downloadBytes, 5 * 1024 * 1024);
      expect(p.streams, 2);
      expect(p.aufwaermMs, 500);
      expect(p.latenzProben, 20);
    });

    test('ein unvollständiger Serverplan fällt auf die Vorgaben zurück, statt '
        'auf null zu messen', () {
      final p = SpeedtestPlan.fromJson({'streams': 8});
      expect(p.streams, 8);
      expect(p.downloadBytes, 25 * 1024 * 1024);
      expect(p.aufwaermMs, 300);
    });

    test('die Download-Menge passt in die Quelldatei auf dem Server', () {
      // Die Ströme holen sich per Range Scheiben aus rnd_100m.bin. Verlangte
      // plan.php mehr als die Datei hergibt, lägen die Anfragen hinter dem
      // Dateiende — nginx antwortete mit 416 oder lieferte weniger, und die
      // Messung wäre still zu niedrig. Der Client deckelt deshalb; dieser Test
      // hält fest, dass die Vorgabe von vornherein hineinpasst.
      expect(const SpeedtestPlan().downloadBytes, lessThanOrEqualTo(kSpeedtestQuelleBytes));
    });
  });

  group('Bewertungsmaßstab', () {
    // Im Mobilfunk gibt es keine zugesagte Mindestgeschwindigkeit, nur einen
    // Höchstwert. Gegen den direkt zu messen wäre sinnlos — deshalb der
    // Prozentsatz der BNetzA-Allgemeinverfügung 35/2026.

    test('Business Mobil L steht auf 300/50 Mbit/s', () {
      expect(kBusinessMobilLDownloadMax, 300);
      expect(kBusinessMobilLUploadMax, 50);
    });

    test('die Untergrenzen entsprechen der Allgemeinverfügung', () {
      // Tenor I.1: 25 % bei hoher, 15 % bei mittlerer, 10 % bei geringer
      // Haushaltsdichte. Kontraintuitiv — je dichter besiedelt, desto mehr
      // wird verlangt. Genau deshalb steht es hier fest.
      expect(kBusinessMobilLDownloadMax * SpeedtestDichte.hoch.anteil, 75);
      expect(kBusinessMobilLDownloadMax * SpeedtestDichte.mittel.anteil, 45);
      expect(kBusinessMobilLDownloadMax * SpeedtestDichte.gering.anteil, 30);
    });

    test('dichter besiedelt verlangt mehr, nicht weniger', () {
      expect(SpeedtestDichte.hoch.anteil, greaterThan(SpeedtestDichte.mittel.anteil));
      expect(SpeedtestDichte.mittel.anteil, greaterThan(SpeedtestDichte.gering.anteil));
    });
  });
}
