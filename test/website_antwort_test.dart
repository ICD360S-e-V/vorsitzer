import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/website_screen.dart';

/// Echte Serverantworten vom 15.08.2026, unveraendert uebernommen.
///
/// ⚠️ Der Sinn dieses Tests ist NICHT, die Zahlen zu pruefen, sondern die
/// FORM. Weder `flutter analyze` noch die uebrigen Tests fassen jemals eine
/// echte Antwort dieses Servers an — genau deshalb blieb der
/// Speedtest-Bildschirm am 05.08.2026 in der Produktion grau: PHP kennt nur
/// einen Array-Typ, eine leere Struktur kommt als `[]` und dieselbe gefuellt
/// als Objekt, und ein `as Map` auf einer Liste liefert nicht null, sondern
/// wirft.
///
/// Zwei Eigenheiten dieses Endpunkts stecken mit in den Daten:
///   * `SUM()` kommt ueber PDO als ZEICHENKETTE zurueck — in `seiten` steht
///     `"aufrufe":"80"`, nicht `80`.
///   * rekonstruierte Zeilen haben ein leeres `tls`, weil das alte
///     Protokollformat die Verschluesselung nicht mitgeschrieben hat.

const String _antwortUebersicht = r'''{"success":true,"tage":30,"verlauf":[{"datum":"2026-08-11","aufrufe":15,"besucher":1,"aufrufe_bot":129,"scans":0,"bytes":1314533,"fehler_4xx":5,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":1,"quelle":"rekonstruiert"},{"datum":"2026-08-12","aufrufe":266,"besucher":75,"aufrufe_bot":1005,"scans":0,"bytes":59642628,"fehler_4xx":5,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":14,"quelle":"rekonstruiert"},{"datum":"2026-08-13","aufrufe":152,"besucher":68,"aufrufe_bot":106,"scans":0,"bytes":18764328,"fehler_4xx":0,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":11,"quelle":"rekonstruiert"},{"datum":"2026-08-14","aufrufe":340,"besucher":36,"aufrufe_bot":2497,"scans":0,"bytes":174357281,"fehler_4xx":37,"fehler_5xx":10,"dauer_p50":0,"dauer_p95":0,"laender":12,"quelle":"rekonstruiert"},{"datum":"2026-08-15","aufrufe":113,"besucher":36,"aufrufe_bot":349,"scans":0,"bytes":56632009,"fehler_4xx":26,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":10,"quelle":"gemischt"}],"summe":{"aufrufe":886,"aufrufe_bot":4086,"scans":0,"bytes":310710779,"fehler_4xx":73,"fehler_5xx":10},"besucher_mittel":43.2,"besucher_bester":75,"vergleich":{"aufrufe_vorher":0,"besucher_vorher":0},"sicherheit":{"note":{"prozent":95,"stufe":"sehr gut","fehler":0,"warnungen":4,"geprueft":42},"geprueft":"2026-08-15 09:25:44"},"daten_ab":"2026-08-11","hinweis":"Gezählt wird im Zugriffsprotokoll des Servers, ohne Skript und ohne Cookie im Browser. Deshalb braucht der Auftritt keinen Einwilligungsbanner. Besucher werden über einen täglich neu gesalzenen Prüfwert unterschieden — genau ist das nie, hinter einem Mobilfunk-Zugang teilen sich viele Menschen eine Adresse."}''';

const String _antwortBesucher = r'''{"success":true,"tage":30,"laender":[{"land":"US","aufrufe":218,"besucher":73},{"land":"DE","aufrufe":213,"besucher":35},{"land":"FR","aufrufe":173,"besucher":1},{"land":"NL","aufrufe":53,"besucher":15},{"land":"HU","aufrufe":49,"besucher":1},{"land":"SG","aufrufe":28,"besucher":16},{"land":"BR","aufrufe":22,"besucher":14},{"land":"KR","aufrufe":22,"besucher":14},{"land":"JP","aufrufe":21,"besucher":16},{"land":"SC","aufrufe":16,"besucher":2},{"land":"HK","aufrufe":15,"besucher":9},{"land":"PL","aufrufe":14,"besucher":6},{"land":"SE","aufrufe":13,"besucher":3},{"land":"UA","aufrufe":12,"besucher":1},{"land":"LU","aufrufe":6,"besucher":2},{"land":"TH","aufrufe":6,"besucher":4},{"land":"ID","aufrufe":3,"besucher":2},{"land":"GB","aufrufe":1,"besucher":1},{"land":"AT","aufrufe":1,"besucher":1}],"netze":[{"netz":"OVH SAS","aufrufe":228,"besucher":3},{"netz":"Shenzhen Tencent Computer Systems Company Limited","aufrufe":218,"besucher":144},{"netz":"Google LLC","aufrufe":99,"besucher":8},{"netz":"Stiftung Erneuerbare Freiheit","aufrufe":91,"besucher":9},{"netz":"ATW Internet Kft.","aufrufe":49,"besucher":1},{"netz":"Church of Cyberology","aufrufe":46,"besucher":9},{"netz":"Deutsche Telekom AG","aufrufe":29,"besucher":5},{"netz":"Microsoft Corporation","aufrufe":27,"besucher":3},{"netz":"SABOTAGE LLC","aufrufe":16,"besucher":2},{"netz":"SERVER.UA LLC","aufrufe":12,"besucher":1},{"netz":"Foreningen for digitala fri- och rattigheter","aufrufe":12,"besucher":2},{"netz":"Wojciech Czapkowicz","aufrufe":12,"besucher":5},{"netz":"Ruhr-Universitaet Bochum","aufrufe":11,"besucher":1},{"netz":"FranTech Solutions","aufrufe":10,"besucher":3},{"netz":"F3 Netze e.V.","aufrufe":3,"besucher":2},{"netz":"1337 Services GmbH","aufrufe":3,"besucher":3},{"netz":"Scaleway SAS","aufrufe":2,"besucher":1},{"netz":"Ivanov Vitaliy Sergeevich","aufrufe":2,"besucher":1},{"netz":"UCLOUD INFORMATION TECHNOLOGY (HK) LIMITED","aufrufe":2,"besucher":1},{"netz":"StormyCloud Inc","aufrufe":2,"besucher":1}],"geraete":[{"geraet":"handy","aufrufe":335},{"geraet":"desktop","aufrufe":305},{"geraet":"unbekannt","aufrufe":239},{"geraet":"tablet","aufrufe":7}],"sprachen":[{"sprache":"de","aufrufe":754,"besucher":172},{"sprache":"en","aufrufe":70,"besucher":34},{"sprache":"ro","aufrufe":62,"besucher":23}],"stunden":[{"stunde":0,"aufrufe":81},{"stunde":1,"aufrufe":19},{"stunde":2,"aufrufe":17},{"stunde":3,"aufrufe":24},{"stunde":4,"aufrufe":32},{"stunde":5,"aufrufe":20},{"stunde":6,"aufrufe":23},{"stunde":7,"aufrufe":11},{"stunde":8,"aufrufe":17},{"stunde":9,"aufrufe":13},{"stunde":10,"aufrufe":15},{"stunde":11,"aufrufe":17},{"stunde":12,"aufrufe":29},{"stunde":13,"aufrufe":22},{"stunde":14,"aufrufe":21},{"stunde":15,"aufrufe":22},{"stunde":16,"aufrufe":37},{"stunde":17,"aufrufe":74},{"stunde":18,"aufrufe":102},{"stunde":19,"aufrufe":94},{"stunde":20,"aufrufe":85},{"stunde":21,"aufrufe":32},{"stunde":22,"aufrufe":19},{"stunde":23,"aufrufe":60}],"wochentage":[{"tag":3,"aufrufe":15},{"tag":4,"aufrufe":266},{"tag":5,"aufrufe":152},{"tag":6,"aufrufe":340},{"tag":7,"aufrufe":113}],"technik":[{"tls":"","protokoll":"HTTP/1.1","ip_art":"v4","aufrufe":419},{"tls":"","protokoll":"HTTP/2.0","ip_art":"v4","aufrufe":269},{"tls":"","protokoll":"HTTP/2.0","ip_art":"v6","aufrufe":195},{"tls":"","protokoll":"HTTP/1.1","ip_art":"v6","aufrufe":2},{"tls":"TLSv1.3","protokoll":"HTTP/2.0","ip_art":"v6","aufrufe":1}]}''';

const String _antwortSeiten = r'''{"success":true,"tage":30,"seiten":[{"pfad":"/impressum.php","aufrufe":"80","besucher":"37"},{"pfad":"/kasse.php","aufrufe":"76","besucher":"19"},{"pfad":"/widerrufsrecht.php","aufrufe":"75","besucher":"24"},{"pfad":"/datenschutz.php","aufrufe":"75","besucher":"22"},{"pfad":"/spenden.php","aufrufe":"48","besucher":"20"},{"pfad":"/satzung.php","aufrufe":"43","besucher":"26"},{"pfad":"/en","aufrufe":"42","besucher":"25"},{"pfad":"/kontakt.php","aufrufe":"41","besucher":"18"},{"pfad":"/ueberuns.php","aufrufe":"41","besucher":"26"},{"pfad":"/aktuelles.php","aufrufe":"41","besucher":"15"},{"pfad":"/kuendigung.php","aufrufe":"40","besucher":"17"},{"pfad":"/mitglied.php","aufrufe":"39","besucher":"15"},{"pfad":"/barrierefreiheit.php","aufrufe":"33","besucher":"16"},{"pfad":"/transparenz.php","aufrufe":"31","besucher":"19"},{"pfad":"/sitemap.php","aufrufe":"28","besucher":"15"},{"pfad":"/kontaktformular.php","aufrufe":"25","besucher":"12"},{"pfad":"/anmeldung.php","aufrufe":"25","besucher":"14"},{"pfad":"/widerruf.php","aufrufe":"12","besucher":"3"},{"pfad":"/ro","aufrufe":"11","besucher":"9"},{"pfad":"/ro/index.php","aufrufe":"8","besucher":"7"},{"pfad":"/ro/ueberuns.php","aufrufe":"6","besucher":"5"},{"pfad":"/ro/aktuelles.php","aufrufe":"6","besucher":"5"},{"pfad":"/ro/satzung.php","aufrufe":"4","besucher":"3"},{"pfad":"/en/ueberuns.php","aufrufe":"4","besucher":"4"},{"pfad":"/en/aktuelles.php","aufrufe":"4","besucher":"4"},{"pfad":"/ro/impressum.php","aufrufe":"4","besucher":"3"},{"pfad":"/en/kasse.php","aufrufe":"3","besucher":"2"},{"pfad":"/ro/widerrufsrecht.php","aufrufe":"3","besucher":"3"},{"pfad":"/ro/datenschutz.php","aufrufe":"3","besucher":"3"},{"pfad":"/ro/kasse.php","aufrufe":"3","besucher":"2"},{"pfad":"/ro/kuendigung.php","aufrufe":"3","besucher":"3"},{"pfad":"/en/index.php","aufrufe":"3","besucher":"3"},{"pfad":"/ro/transparenz.php","aufrufe":"2","besucher":"2"},{"pfad":"/ro/sitemap.php","aufrufe":"2","besucher":"2"},{"pfad":"/en/satzung.php","aufrufe":"2","besucher":"1"},{"pfad":"/ro/barrierefreiheit.php","aufrufe":"2","besucher":"2"},{"pfad":"/en/kontakt.php","aufrufe":"1","besucher":"1"},{"pfad":"/ro/mitglied.php","aufrufe":"1","besucher":"1"},{"pfad":"/en/kontaktformular.php","aufrufe":"1","besucher":"1"},{"pfad":"/en/widerruf.php","aufrufe":"1","besucher":"1"}],"verweise":[{"verweis":"ip53.ip-135-125-150.eu","aufrufe":15,"besucher":1},{"verweis":"135.125.150.53","aufrufe":1,"besucher":1}],"fehlseiten":[{"pfad":"/404.php","status":404,"treffer":31,"zuletzt":"2026-08-15 09:11:20"},{"pfad":"/","status":400,"treffer":9,"zuletzt":"2026-08-15 09:26:43"},{"pfad":"/header.php","status":404,"treffer":5,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/en","status":404,"treffer":5,"zuletzt":"2026-08-14 23:22:06"},{"pfad":"/footer.php","status":404,"treffer":4,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/en/404.php","status":404,"treffer":3,"zuletzt":"2026-08-15 00:14:12"},{"pfad":"/ro/404.php","status":404,"treffer":3,"zuletzt":"2026-08-15 00:14:12"},{"pfad":"/anmeldung_ansicht.php","status":500,"treffer":2,"zuletzt":"2026-08-14 12:39:58"},{"pfad":"/uk/404.php","status":404,"treffer":2,"zuletzt":"2026-08-15 09:11:05"},{"pfad":"/widerruf_formular.php","status":404,"treffer":2,"zuletzt":"2026-08-15 09:08:54"},{"pfad":"/widerrufsrecht.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/kuendigung.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/satzung.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/anmeldung_fertig.php","status":500,"treffer":1,"zuletzt":"2026-08-14 12:39:41"},{"pfad":"/anmeldung_zusammen.php","status":500,"treffer":1,"zuletzt":"2026-08-14 12:39:41"},{"pfad":"/sprachen.php","status":404,"treffer":1,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/anmeldung_ansicht.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/anmeldung_fertig.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/anmeldung_zusammen.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/anmeldung_pruefen.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/anmeldung_entwurf.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/anmeldung_listen.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/anmeldung_stil.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/formularschutz.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/widerruf.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"}],"langsam":[],"bots":[{"bot_name":"curl","aufrufe":2341,"zuletzt":"2026-08-15 09:24:42"},{"bot_name":"Crawler","aufrufe":1527,"zuletzt":"2026-08-14 19:29:16"},{"bot_name":"Chrome (headless)","aufrufe":84,"zuletzt":"2026-08-15 09:23:50"},{"bot_name":"OpenAI GPTBot","aufrufe":69,"zuletzt":"2026-08-14 22:48:17"},{"bot_name":"ohne Kennung","aufrufe":44,"zuletzt":"2026-08-15 09:26:43"},{"bot_name":"Google","aufrufe":20,"zuletzt":"2026-08-14 23:28:34"},{"bot_name":"Bing","aufrufe":1,"zuletzt":"2026-08-13 12:31:07"}]}''';

const String _antwortAngriffe = r'''{"success":true,"tage":30,"muster":[],"herkunft":[],"verlauf":[{"datum":"2026-08-11","scans":0},{"datum":"2026-08-12","scans":0},{"datum":"2026-08-13","scans":0},{"datum":"2026-08-14","scans":0},{"datum":"2026-08-15","scans":0}],"erfolge":[],"hinweis":"Abgewiesene Versuche sind der Normalfall — der Auftritt steht im offenen Netz. Wichtig ist die Liste „hat geantwortet\": dort darf nichts stehen, was nach einer Konfigurationsdatei aussieht."}''';

void main() {
  Map<String, dynamic> lies(String roh) => jsonDecode(roh) as Map<String, dynamic>;

  group('Die echten Antworten lassen sich vollstaendig lesen', () {
    test('uebersicht', () {
      final a = lies(_antwortUebersicht);
      expect(a['success'], isTrue);

      final verlauf = webListe(a['verlauf']);
      expect(verlauf, isNotEmpty);
      expect(webZahl(verlauf.first['aufrufe']), greaterThan(0));

      // `summe` und `vergleich` sind Objekte, `verlauf` ist eine Liste.
      // Beide Helfer duerfen an der jeweils falschen Form nicht werfen.
      expect(webKarte(a['summe']), isNotEmpty);
      expect(webKarte(a['verlauf']), isEmpty);
      expect(webListe(a['summe']), isEmpty);

      final note = webKarte(webKarte(a['sicherheit'])['note']);
      expect(webZahl(note['prozent']), inInclusiveRange(0, 100));
    });

    test('besucher — auch die Stundenliste mit Luecken', () {
      final a = lies(_antwortBesucher);
      final stunden = webListe(a['stunden']);
      expect(stunden, isNotEmpty);
      // Der Server liefert NUR Stunden mit Zugriffen. Der Bildschirm fuellt
      // die Luecken selbst; kaeme hier eine feste 24er-Reihe an, wuerde diese
      // Erwartung stillschweigend falsch.
      expect(stunden.length, lessThanOrEqualTo(24));
      for (final s in stunden) {
        expect(webZahl(s['stunde']), inInclusiveRange(0, 23));
      }

      // Rekonstruierte Zeilen haben ein leeres `tls` — das darf nicht werfen.
      final technik = webListe(a['technik']);
      expect(technik.any((t) => '${t['tls']}'.isEmpty), isTrue);

      for (final l in webListe(a['laender'])) {
        expect('${l['land']}'.length, 2);
      }
    });

    test('seiten — SUM() kommt als Zeichenkette zurueck', () {
      final a = lies(_antwortSeiten);
      final seiten = webListe(a['seiten']);
      expect(seiten, isNotEmpty);

      // Der eigentliche Fallstrick dieses Endpunkts: MySQL liefert SUM() ueber
      // PDO als String. Ein `as int` waere hier durchgefallen.
      expect(seiten.first['aufrufe'], isA<String>());
      expect(webZahl(seiten.first['aufrufe']), greaterThan(0));

      expect(webListe(a['fehlseiten']), isNotEmpty);
      // `langsam` ist im Rueckblick leer — die leere Liste muss durchgehen.
      expect(webListe(a['langsam']), isEmpty);
    });

    test('angriffe — lauter leere Listen sind der Normalfall', () {
      final a = lies(_antwortAngriffe);
      expect(webListe(a['muster']), isEmpty);
      expect(webListe(a['herkunft']), isEmpty);
      expect(webListe(a['erfolge']), isEmpty);
      expect(webListe(a['verlauf']), isNotEmpty);
    });
  });

  group('Die Helfer werfen nie', () {
    test('eine Liste, wo eine Karte erwartet wird, ergibt Leeres', () {
      expect(webKarte(const []), isEmpty);
      expect(webKarte(const [1, 2, 3]), isEmpty);
      expect(webKarte(null), isEmpty);
      expect(webKarte('Text'), isEmpty);
    });

    test('eine Karte, wo eine Liste erwartet wird, ergibt Leeres', () {
      expect(webListe(const <String, dynamic>{}), isEmpty);
      expect(webListe(const {'a': 1}), isEmpty);
      expect(webListe(null), isEmpty);
    });

    test('Zahlen kommen als int, double, String oder gar nicht', () {
      expect(webZahl(7), 7);
      expect(webZahl(7.6), 8);
      expect(webZahl('42'), 42);
      expect(webZahl(''), 0);
      expect(webZahl(null), 0);
      expect(webZahl('kaputt'), 0);
      expect(webKomma('3.5'), 3.5);
      expect(webKomma(null), 0);
    });
  });

  group('Darstellung', () {
    test('Tausendertrennung', () {
      expect(webTausend(0), '0');
      expect(webTausend(999), '999');
      expect(webTausend(1000), '1.000');
      expect(webTausend(1234567), '1.234.567');
    });

    test('Byte-Groessen', () {
      expect(webBytes(512), '512 B');
      expect(webBytes(2048), '2 kB');
      expect(webBytes(5 * 1048576), '5.0 MB');
      expect(webBytes(3 * 1073741824), '3.0 GB');
    });

    test('Laenderkennung wird zur Flagge', () {
      expect(webFlagge('DE'), '\u{1F1E9}\u{1F1EA}');
      expect(webFlagge('de'), '\u{1F1E9}\u{1F1EA}');
      // ⚠️ Unsinn darf kein Kaestchen ergeben, sondern gar nichts — sonst
      // steht in der Liste ein Tofu-Rechteck neben dem Land.
      expect(webFlagge(''), '');
      expect(webFlagge('D'), '');
      expect(webFlagge('12'), '');
      expect(webFlagge('DEU'), '');
    });

    test('jede Befundstufe hat Farbe und Zeichen, auch eine unbekannte', () {
      for (final stand in ['ok', 'warnung', 'fehler', 'info', 'voellig neu']) {
        final s = webStand(stand);
        expect(s.text, isNotEmpty);
      }
      // Eine Stufe, die eine neuere Serverfassung erfindet, faellt auf den
      // neutralen Zweig — nicht auf „Fehler", sonst meldete ein alter Client
      // Alarm fuer etwas, das er nur nicht kennt.
      expect(webStand('voellig neu').farbe, webStand('info').farbe);
    });
  });
}
