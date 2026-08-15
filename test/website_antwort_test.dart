import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/website_screen.dart';
import 'package:icd360sev_vorsitzer/widgets/website_diagramme.dart';

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
/// Vier Eigenheiten dieses Endpunkts stecken mit in den Daten:
///   * `SUM()` kommt ueber PDO als ZEICHENKETTE zurueck.
///   * rekonstruierte Zeilen haben ein leeres `tls`.
///   * der Server liefert nur Klassen, in denen etwas passiert ist — Stunden
///     und Wochentage haben Luecken, die der Bildschirm fuellen muss.
///   * `besucher_exakt` unterscheidet „Besucher" von „Besuchertagen"; ueber
///     mehrere Kalendertage ist die Zahl KEINE Besucherzahl.

const String _antwortUebersicht = r'''{"success":true,"tage":30,"verlauf":[{"datum":"2026-08-11","aufrufe":15,"besucher":1,"aufrufe_bot":129,"scans":0,"bytes":1314533,"fehler_4xx":5,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":1,"quelle":"rekonstruiert"},{"datum":"2026-08-12","aufrufe":266,"besucher":75,"aufrufe_bot":1005,"scans":0,"bytes":59642628,"fehler_4xx":5,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":14,"quelle":"rekonstruiert"},{"datum":"2026-08-13","aufrufe":152,"besucher":68,"aufrufe_bot":106,"scans":0,"bytes":18764328,"fehler_4xx":0,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":11,"quelle":"rekonstruiert"},{"datum":"2026-08-14","aufrufe":340,"besucher":36,"aufrufe_bot":2497,"scans":0,"bytes":174357281,"fehler_4xx":37,"fehler_5xx":10,"dauer_p50":0,"dauer_p95":0,"laender":12,"quelle":"rekonstruiert"},{"datum":"2026-08-15","aufrufe":144,"besucher":42,"aufrufe_bot":546,"scans":19,"bytes":88850476,"fehler_4xx":65,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":5,"laender":10,"quelle":"gemischt"}],"summe":{"aufrufe":917,"aufrufe_bot":4283,"scans":19,"bytes":342929246,"fehler_4xx":112,"fehler_5xx":10},"stand":"2026-08-15 11:37:01","zusammensetzung":[{"art":"mensch","aufrufe":917},{"art":"maschine","aufrufe":4283},{"art":"scan","aufrufe":19}],"top_seiten":[{"pfad":"/impressum.php","aufrufe":"80"},{"pfad":"/datenschutz.php","aufrufe":"76"},{"pfad":"/kasse.php","aufrufe":"76"},{"pfad":"/widerrufsrecht.php","aufrufe":"75"},{"pfad":"/spenden.php","aufrufe":"48"},{"pfad":"/en","aufrufe":"45"}],"sprachen":[{"sprache":"de","aufrufe":765},{"sprache":"en","aufrufe":74},{"sprache":"ro","aufrufe":64},{"sprache":"ru","aufrufe":10},{"sprache":"uk","aufrufe":4}],"geraete":[{"geraet":"handy","aufrufe":342},{"geraet":"desktop","aufrufe":321},{"geraet":"unbekannt","aufrufe":247},{"geraet":"tablet","aufrufe":7}],"laender":[{"land":"DE","aufrufe":224},{"land":"US","aufrufe":219},{"land":"FR","aufrufe":173},{"land":"NL","aufrufe":66},{"land":"HU","aufrufe":49},{"land":"SG","aufrufe":32},{"land":"KR","aufrufe":24},{"land":"BR","aufrufe":22}],"antwortzeit":{"mittel":8,"hoechst":122,"ueber_1s":0,"n":917},"besucher_mittel":44.4,"besucher_bester":75,"vergleich":{"aufrufe_vorher":0,"besucher_vorher":0},"sicherheit":{"note":{"prozent":96,"stufe":"sehr gut","fehler":0,"warnungen":5,"geprueft":59},"geprueft":"2026-08-15 11:43:16"},"daten_ab":"2026-08-11","hinweis":"Gezählt wird im Zugriffsprotokoll des Servers, ohne Skript und ohne Cookie im Browser. Deshalb braucht der Auftritt keinen Einwilligungsbanner. Besucher werden über einen täglich neu gesalzenen Prüfwert unterschieden — genau ist das nie, hinter einem Mobilfunk-Zugang teilen sich viele Menschen eine Adresse."}''';

const String _antwortBesucher = r'''{"success":true,"tage":30,"fenster_stunden":720,"von":"2026-07-16 11:49:09","klasse_sekunden":86400,"besucher_exakt":false,"stand":"2026-08-15 11:37:01","summe":{"aufrufe":917,"besucher":222,"maschinen":4283,"scans":19},"tiefe":{"besuche":222,"aufrufe":917,"nur_eine":101,"tiefster":173,"je_besuch":4.13},"verlauf":[{"klasse":"2026-08-10 02:00:00","aufrufe":2,"besucher":1,"maschinen":"2"},{"klasse":"2026-08-11 02:00:00","aufrufe":275,"besucher":12,"maschinen":"254"},{"klasse":"2026-08-12 02:00:00","aufrufe":1224,"besucher":95,"maschinen":"940"},{"klasse":"2026-08-13 02:00:00","aufrufe":202,"besucher":65,"maschinen":"74"},{"klasse":"2026-08-14 02:00:00","aufrufe":3079,"besucher":317,"maschinen":"2669"},{"klasse":"2026-08-15 02:00:00","aufrufe":437,"besucher":38,"maschinen":"344"}],"zusammensetzung":[{"art":"mensch","aufrufe":917},{"art":"bot","aufrufe":4283},{"art":"scan","aufrufe":19}],"laender":[{"land":"DE","aufrufe":224,"besucher":36},{"land":"US","aufrufe":219,"besucher":74},{"land":"FR","aufrufe":173,"besucher":1},{"land":"NL","aufrufe":66,"besucher":16},{"land":"HU","aufrufe":49,"besucher":1},{"land":"SG","aufrufe":32,"besucher":18},{"land":"KR","aufrufe":24,"besucher":15},{"land":"BR","aufrufe":22,"besucher":14},{"land":"JP","aufrufe":21,"besucher":16},{"land":"SC","aufrufe":16,"besucher":2},{"land":"HK","aufrufe":15,"besucher":9},{"land":"PL","aufrufe":14,"besucher":6},{"land":"SE","aufrufe":13,"besucher":3},{"land":"UA","aufrufe":12,"besucher":1},{"land":"TH","aufrufe":6,"besucher":4},{"land":"LU","aufrufe":6,"besucher":2},{"land":"ID","aufrufe":3,"besucher":2},{"land":"GB","aufrufe":1,"besucher":1},{"land":"AT","aufrufe":1,"besucher":1}],"netze":[{"netz":"OVH SAS","aufrufe":236,"besucher":3},{"netz":"Shenzhen Tencent Computer Systems Company Limited","aufrufe":225,"besucher":148},{"netz":"Google LLC","aufrufe":99,"besucher":8},{"netz":"Stiftung Erneuerbare Freiheit","aufrufe":91,"besucher":9},{"netz":"Church of Cyberology","aufrufe":56,"besucher":10},{"netz":"ATW Internet Kft.","aufrufe":49,"besucher":1},{"netz":"Deutsche Telekom AG","aufrufe":29,"besucher":5},{"netz":"Microsoft Corporation","aufrufe":27,"besucher":3},{"netz":"SABOTAGE LLC","aufrufe":16,"besucher":2},{"netz":"SERVER.UA LLC","aufrufe":12,"besucher":1},{"netz":"Foreningen for digitala fri- och rattigheter","aufrufe":12,"besucher":2},{"netz":"Wojciech Czapkowicz","aufrufe":12,"besucher":5},{"netz":"Ruhr-Universitaet Bochum","aufrufe":11,"besucher":1},{"netz":"FranTech Solutions","aufrufe":10,"besucher":3},{"netz":"1337 Services GmbH","aufrufe":6,"besucher":3},{"netz":"DigitalOcean, LLC","aufrufe":4,"besucher":2},{"netz":"F3 Netze e.V.","aufrufe":3,"besucher":2},{"netz":"Scaleway SAS","aufrufe":2,"besucher":1},{"netz":"Ivanov Vitaliy Sergeevich","aufrufe":2,"besucher":1},{"netz":"UCLOUD INFORMATION TECHNOLOGY (HK) LIMITED","aufrufe":2,"besucher":1}],"geraete":[{"geraet":"handy","aufrufe":342},{"geraet":"desktop","aufrufe":321},{"geraet":"unbekannt","aufrufe":247},{"geraet":"tablet","aufrufe":7}],"sprachen":[{"sprache":"de","aufrufe":765,"besucher":176},{"sprache":"en","aufrufe":74,"besucher":36},{"sprache":"ro","aufrufe":64,"besucher":24},{"sprache":"ru","aufrufe":10,"besucher":3},{"sprache":"uk","aufrufe":4,"besucher":3}],"einstieg":[{"pfad":"/impressum.php","besuche":24},{"pfad":"/en","besuche":23},{"pfad":"/satzung.php","besuche":17},{"pfad":"/widerrufsrecht.php","besuche":15},{"pfad":"/ueberuns.php","besuche":14},{"pfad":"/kuendigung.php","besuche":11},{"pfad":"/barrierefreiheit.php","besuche":10},{"pfad":"/spenden.php","besuche":10},{"pfad":"/sitemap.php","besuche":9},{"pfad":"/kasse.php","besuche":9},{"pfad":"/anmeldung.php","besuche":9},{"pfad":"/aktuelles.php","besuche":8}],"maschinen":[{"bot_name":"curl","aufrufe":2514,"zuletzt":"2026-08-15 10:47:02"},{"bot_name":"Crawler","aufrufe":1527,"zuletzt":"2026-08-14 19:29:16"},{"bot_name":"Chrome (headless)","aufrufe":87,"zuletzt":"2026-08-15 09:36:49"},{"bot_name":"OpenAI GPTBot","aufrufe":69,"zuletzt":"2026-08-14 22:48:17"},{"bot_name":"ohne Kennung","aufrufe":64,"zuletzt":"2026-08-15 10:46:10"},{"bot_name":"Google","aufrufe":21,"zuletzt":"2026-08-15 10:42:06"},{"bot_name":"Bing","aufrufe":1,"zuletzt":"2026-08-13 12:31:07"}],"ip_art":[{"ip_art":"v4","aufrufe":709,"besucher":184},{"ip_art":"v6","aufrufe":208,"besucher":38}],"tls_art":[{"tls":"","aufrufe":888},{"tls":"TLSv1.3","aufrufe":27},{"tls":"TLSv1.2","aufrufe":2}],"status":[{"status":200,"aufrufe":728},{"status":303,"aufrufe":171},{"status":301,"aufrufe":7},{"status":500,"aufrufe":6},{"status":404,"aufrufe":5}],"stunden":[{"stunde":0,"aufrufe":81},{"stunde":1,"aufrufe":19},{"stunde":2,"aufrufe":17},{"stunde":3,"aufrufe":24},{"stunde":4,"aufrufe":32},{"stunde":5,"aufrufe":20},{"stunde":6,"aufrufe":23},{"stunde":7,"aufrufe":11},{"stunde":8,"aufrufe":17},{"stunde":9,"aufrufe":21},{"stunde":10,"aufrufe":38},{"stunde":11,"aufrufe":17},{"stunde":12,"aufrufe":29},{"stunde":13,"aufrufe":22},{"stunde":14,"aufrufe":21},{"stunde":15,"aufrufe":22},{"stunde":16,"aufrufe":37},{"stunde":17,"aufrufe":74},{"stunde":18,"aufrufe":102},{"stunde":19,"aufrufe":94},{"stunde":20,"aufrufe":85},{"stunde":21,"aufrufe":32},{"stunde":22,"aufrufe":19},{"stunde":23,"aufrufe":60}],"rhythmus_sinnvoll":true,"wochentage":[{"tag":3,"aufrufe":15},{"tag":4,"aufrufe":266},{"tag":5,"aufrufe":152},{"tag":6,"aufrufe":340},{"tag":7,"aufrufe":144}],"technik":[{"tls":"","protokoll":"HTTP/1.1","ip_art":"v4","aufrufe":422},{"tls":"","protokoll":"HTTP/2.0","ip_art":"v4","aufrufe":269},{"tls":"","protokoll":"HTTP/2.0","ip_art":"v6","aufrufe":195},{"tls":"TLSv1.3","protokoll":"HTTP/1.1","ip_art":"v4","aufrufe":16},{"tls":"TLSv1.3","protokoll":"HTTP/2.0","ip_art":"v6","aufrufe":11},{"tls":"","protokoll":"HTTP/1.1","ip_art":"v6","aufrufe":2},{"tls":"TLSv1.2","protokoll":"HTTP/1.1","ip_art":"v4","aufrufe":2}]}''';

const String _antwortBesucher1h = r'''{"success":true,"tage":30,"fenster_stunden":1,"von":"2026-08-15 10:49:09","klasse_sekunden":300,"besucher_exakt":true,"stand":"2026-08-15 11:37:01","summe":{"aufrufe":0,"besucher":0,"maschinen":0,"scans":0},"tiefe":{"besuche":0,"aufrufe":0,"nur_eine":0,"tiefster":0,"je_besuch":0},"verlauf":[],"zusammensetzung":[{"art":"mensch","aufrufe":0},{"art":"bot","aufrufe":0},{"art":"scan","aufrufe":0}],"laender":[],"netze":[],"geraete":[],"sprachen":[],"einstieg":[],"maschinen":[],"ip_art":[],"tls_art":[],"status":[],"stunden":[],"rhythmus_sinnvoll":false,"wochentage":[],"technik":[]}''';

const String _antwortSeiten = r'''{"success":true,"tage":30,"seiten":[{"pfad":"/impressum.php","mensch":"80","maschine":"433","besucher":37,"aufrufe":513,"dauer":"7","bytes":"23869253","zuletzt":"2026-08-15 09:37:28"},{"pfad":"/datenschutz.php","mensch":"76","maschine":"288","besucher":22,"aufrufe":364,"dauer":"10","bytes":"20290908","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/satzung.php","mensch":"45","maschine":"282","besucher":26,"aufrufe":327,"dauer":"7","bytes":"19294798","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/widerrufsrecht.php","mensch":"75","maschine":"239","besucher":24,"aufrufe":314,"dauer":"14","bytes":"15031232","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/kontakt.php","mensch":"41","maschine":"260","besucher":18,"aufrufe":301,"dauer":"10","bytes":"14318183","zuletzt":"2026-08-15 09:34:58"},{"pfad":"/kasse.php","mensch":"76","maschine":"171","besucher":19,"aufrufe":247,"dauer":"15","bytes":"12785481","zuletzt":"2026-08-15 09:34:58"},{"pfad":"/anmeldung.php","mensch":"25","maschine":"219","besucher":14,"aufrufe":244,"dauer":"16","bytes":"14307600","zuletzt":"2026-08-15 09:17:23"},{"pfad":"/sitemap.php","mensch":"28","maschine":"215","besucher":15,"aufrufe":243,"dauer":"12","bytes":"13445621","zuletzt":"2026-08-15 09:34:59"},{"pfad":"/spenden.php","mensch":"48","maschine":"176","besucher":20,"aufrufe":224,"dauer":"12","bytes":"13436639","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/ueberuns.php","mensch":"41","maschine":"162","besucher":26,"aufrufe":203,"dauer":"7","bytes":"12289537","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/kuendigung.php","mensch":"40","maschine":"163","besucher":17,"aufrufe":203,"dauer":"24","bytes":"13195529","zuletzt":"2026-08-15 09:34:59"},{"pfad":"/mitglied.php","mensch":"39","maschine":"160","besucher":15,"aufrufe":199,"dauer":"12","bytes":"12250844","zuletzt":"2026-08-15 09:34:59"},{"pfad":"/kontaktformular.php","mensch":"25","maschine":"172","besucher":12,"aufrufe":197,"dauer":"21","bytes":"11829158","zuletzt":"2026-08-15 09:34:58"},{"pfad":"/barrierefreiheit.php","mensch":"33","maschine":"161","besucher":16,"aufrufe":194,"dauer":"13","bytes":"11496786","zuletzt":"2026-08-15 09:34:57"},{"pfad":"/transparenz.php","mensch":"31","maschine":"158","besucher":19,"aufrufe":189,"dauer":"12","bytes":"11434933","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/widerruf.php","mensch":"12","maschine":"159","besucher":3,"aufrufe":171,"dauer":"13","bytes":"10476439","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/aktuelles.php","mensch":"41","maschine":"112","besucher":15,"aufrufe":153,"dauer":"90","bytes":"7016989","zuletzt":"2026-08-15 09:34:57"},{"pfad":"/en","mensch":"45","maschine":"5","besucher":27,"aufrufe":50,"dauer":"44","bytes":"2831941","zuletzt":"2026-08-15 10:19:47"},{"pfad":"/404.php","mensch":"0","maschine":"46","besucher":0,"aufrufe":46,"dauer":"3","bytes":"3193306","zuletzt":"2026-08-15 09:11:20"},{"pfad":"/","mensch":"7","maschine":"31","besucher":4,"aufrufe":38,"dauer":"119","bytes":"53273","zuletzt":"2026-08-15 10:46:53"},{"pfad":"/en/index.php","mensch":"3","maschine":"32","besucher":3,"aufrufe":35,"dauer":"5","bytes":"3861871","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/index.php","mensch":"1","maschine":"27","besucher":1,"aufrufe":28,"dauer":"7","bytes":"831235","zuletzt":"2026-08-15 10:47:02"},{"pfad":"/ro/index.php","mensch":"9","maschine":"17","besucher":8,"aufrufe":26,"dauer":"5","bytes":"2914404","zuletzt":"2026-08-15 10:42:27"},{"pfad":"/en/satzung.php","mensch":"3","maschine":"18","besucher":1,"aufrufe":21,"dauer":"8","bytes":"3051665","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/en/impressum.php","mensch":"1","maschine":"20","besucher":1,"aufrufe":21,"dauer":"9","bytes":"2946397","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/ro/satzung.php","mensch":"5","maschine":"15","besucher":3,"aufrufe":20,"dauer":"7","bytes":"2859038","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/ro/impressum.php","mensch":"4","maschine":"16","besucher":3,"aufrufe":20,"dauer":"9","bytes":"2586671","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/widerruf.php","mensch":"1","maschine":"19","besucher":1,"aufrufe":20,"dauer":"7","bytes":"2697161","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/widerrufsrecht.php","mensch":"3","maschine":"16","besucher":3,"aufrufe":19,"dauer":"8","bytes":"2484642","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/datenschutz.php","mensch":"3","maschine":"14","besucher":3,"aufrufe":17,"dauer":"10","bytes":"2373678","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/ro/ueberuns.php","mensch":"6","maschine":"10","besucher":5,"aufrufe":16,"dauer":"8","bytes":"1671874","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/en/widerrufsrecht.php","mensch":"1","maschine":"15","besucher":1,"aufrufe":16,"dauer":"9","bytes":"2322582","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/widerruf.php","mensch":"1","maschine":"15","besucher":1,"aufrufe":16,"dauer":"7","bytes":"2197646","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/aktuelles.php","mensch":"6","maschine":"10","besucher":5,"aufrufe":16,"dauer":"11","bytes":"1619106","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/ro/kasse.php","mensch":"3","maschine":"13","besucher":2,"aufrufe":16,"dauer":"9","bytes":"2016630","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/kasse.php","mensch":"3","maschine":"12","besucher":2,"aufrufe":15,"dauer":"10","bytes":"1863893","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/datenschutz.php","mensch":"1","maschine":"14","besucher":1,"aufrufe":15,"dauer":"11","bytes":"2298978","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/aktuelles.php","mensch":"4","maschine":"10","besucher":4,"aufrufe":14,"dauer":"13","bytes":"1614246","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/ueberuns.php","mensch":"4","maschine":"10","besucher":4,"aufrufe":14,"dauer":"8","bytes":"1662942","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/kuendigung.php","mensch":"3","maschine":"11","besucher":3,"aufrufe":14,"dauer":"8","bytes":"1816264","zuletzt":"2026-08-15 09:35:02"}],"seiten_verlauf":[{"pfad":"/impressum.php","datum":"2026-08-11","mensch":"5"},{"pfad":"/datenschutz.php","datum":"2026-08-11","mensch":"3"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-11","mensch":"3"},{"pfad":"/satzung.php","datum":"2026-08-11","mensch":"3"},{"pfad":"/kontakt.php","datum":"2026-08-11","mensch":"1"},{"pfad":"/impressum.php","datum":"2026-08-12","mensch":"42"},{"pfad":"/datenschutz.php","datum":"2026-08-12","mensch":"57"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-12","mensch":"56"},{"pfad":"/satzung.php","datum":"2026-08-12","mensch":"19"},{"pfad":"/kontakt.php","datum":"2026-08-12","mensch":"20"},{"pfad":"/datenschutz.php","datum":"2026-08-13","mensch":"3"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-13","mensch":"5"},{"pfad":"/satzung.php","datum":"2026-08-13","mensch":"6"},{"pfad":"/kontakt.php","datum":"2026-08-13","mensch":"3"},{"pfad":"/impressum.php","datum":"2026-08-13","mensch":"21"},{"pfad":"/datenschutz.php","datum":"2026-08-14","mensch":"11"},{"pfad":"/kontakt.php","datum":"2026-08-14","mensch":"16"},{"pfad":"/satzung.php","datum":"2026-08-14","mensch":"13"},{"pfad":"/impressum.php","datum":"2026-08-14","mensch":"11"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-14","mensch":"10"},{"pfad":"/datenschutz.php","datum":"2026-08-15","mensch":"2"},{"pfad":"/impressum.php","datum":"2026-08-15","mensch":"1"},{"pfad":"/kontakt.php","datum":"2026-08-15","mensch":"1"},{"pfad":"/satzung.php","datum":"2026-08-15","mensch":"4"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-15","mensch":"1"}],"einstieg":[{"pfad":"/impressum.php","besuche":24},{"pfad":"/en","besuche":23},{"pfad":"/satzung.php","besuche":17},{"pfad":"/widerrufsrecht.php","besuche":15},{"pfad":"/ueberuns.php","besuche":14},{"pfad":"/kuendigung.php","besuche":11},{"pfad":"/barrierefreiheit.php","besuche":10},{"pfad":"/spenden.php","besuche":10},{"pfad":"/sitemap.php","besuche":9},{"pfad":"/kasse.php","besuche":9},{"pfad":"/anmeldung.php","besuche":9},{"pfad":"/aktuelles.php","besuche":8},{"pfad":"/transparenz.php","besuche":7},{"pfad":"/datenschutz.php","besuche":7},{"pfad":"/kontakt.php","besuche":6}],"sprach_seiten":[{"sprache":"de","seiten":35,"mensch":"765","maschine":"3674"},{"sprache":"en","seiten":19,"mensch":"74","maschine":"244"},{"sprache":"ro","seiten":19,"mensch":"64","maschine":"216"},{"sprache":"ru","seiten":20,"mensch":"10","maschine":"75"},{"sprache":"uk","seiten":21,"mensch":"4","maschine":"74"}],"status_verteilung":[{"status":200,"mensch":"728","maschine":"3465","scan":"0","gesamt":4193},{"status":303,"mensch":"171","maschine":"705","scan":"0","gesamt":876},{"status":404,"mensch":"5","maschine":"63","scan":"19","gesamt":87},{"status":301,"mensch":"7","maschine":"21","scan":"0","gesamt":28},{"status":400,"mensch":"0","maschine":"25","scan":"0","gesamt":25},{"status":500,"mensch":"6","maschine":"4","scan":"0","gesamt":10}],"verweise":[{"verweis":"ip53.ip-135-125-150.eu","aufrufe":15,"besucher":1},{"verweis":"135.125.150.53","aufrufe":1,"besucher":1}],"fehlseiten":[{"pfad":"/404.php","status":404,"treffer":31,"zuletzt":"2026-08-15 09:11:20"},{"pfad":"/","status":400,"treffer":25,"zuletzt":"2026-08-15 10:46:10"},{"pfad":"/header.php","status":404,"treffer":5,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/en","status":404,"treffer":5,"zuletzt":"2026-08-14 23:22:06"},{"pfad":"/footer.php","status":404,"treffer":4,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/en/404.php","status":404,"treffer":3,"zuletzt":"2026-08-15 00:14:12"},{"pfad":"/ro/404.php","status":404,"treffer":3,"zuletzt":"2026-08-15 00:14:12"},{"pfad":"/widerruf_formular.php","status":404,"treffer":2,"zuletzt":"2026-08-15 09:08:54"},{"pfad":"/anmeldung_ansicht.php","status":500,"treffer":2,"zuletzt":"2026-08-14 12:39:58"},{"pfad":"/uk/404.php","status":404,"treffer":2,"zuletzt":"2026-08-15 09:11:05"},{"pfad":"/anmeldung_stil.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/uk/footer.php","status":404,"treffer":1,"zuletzt":"2026-08-15 09:37:28"},{"pfad":"/formularschutz.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/ru/inhalt/ru/index.php","status":404,"treffer":1,"zuletzt":"2026-08-15 09:37:29"},{"pfad":"/uk/sprachen/uk.php","status":404,"treffer":1,"zuletzt":"2026-08-15 09:37:29"},{"pfad":"/widerruf.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/impressum.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/datenschutz.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/widerrufsrecht.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/kuendigung.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/anmeldung_fertig.php","status":500,"treffer":1,"zuletzt":"2026-08-14 12:39:41"},{"pfad":"/satzung.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/anmeldung_zusammen.php","status":500,"treffer":1,"zuletzt":"2026-08-14 12:39:41"},{"pfad":"/anmeldung_ansicht.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/sprachen.php","status":404,"treffer":1,"zuletzt":"2026-08-14 22:23:22"}],"langsam":[{"pfad":"/en","aufrufe":3,"mittel":"44","hoechst":122},{"pfad":"/uk","aufrufe":3,"mittel":"5","hoechst":7},{"pfad":"/","aufrufe":4,"mittel":"3","hoechst":4}],"bots":[{"bot_name":"curl","aufrufe":2514,"zuletzt":"2026-08-15 10:47:02"},{"bot_name":"Crawler","aufrufe":1527,"zuletzt":"2026-08-14 19:29:16"},{"bot_name":"Chrome (headless)","aufrufe":87,"zuletzt":"2026-08-15 09:36:49"},{"bot_name":"OpenAI GPTBot","aufrufe":69,"zuletzt":"2026-08-14 22:48:17"},{"bot_name":"ohne Kennung","aufrufe":64,"zuletzt":"2026-08-15 10:46:10"},{"bot_name":"Google","aufrufe":21,"zuletzt":"2026-08-15 10:42:06"},{"bot_name":"Bing","aufrufe":1,"zuletzt":"2026-08-13 12:31:07"}],"suchmaschinen":[{"bot_name":"Google","abrufe":21,"seiten":10,"zuletzt":"2026-08-15 10:42:06","erstmals":"2026-08-12 14:47:31","fehler":"0"},{"bot_name":"Bing","abrufe":1,"seiten":1,"zuletzt":"2026-08-13 12:31:07","erstmals":"2026-08-13 12:31:07","fehler":"0"}],"gecrawlt":[{"pfad":"/impressum.php","abrufe":4,"zuletzt":"2026-08-14 17:13:35"},{"pfad":"/datenschutz.php","abrufe":3,"zuletzt":"2026-08-14 17:51:04"},{"pfad":"/kontakt.php","abrufe":3,"zuletzt":"2026-08-14 19:43:37"},{"pfad":"/mitglied.php","abrufe":3,"zuletzt":"2026-08-14 18:28:34"},{"pfad":"/transparenz.php","abrufe":3,"zuletzt":"2026-08-14 23:28:34"},{"pfad":"/widerrufsrecht.php","abrufe":2,"zuletzt":"2026-08-13 15:15:52"},{"pfad":"/spenden.php","abrufe":1,"zuletzt":"2026-08-13 01:47:52"},{"pfad":"/sitemap.php","abrufe":1,"zuletzt":"2026-08-13 02:41:54"},{"pfad":"/satzung.php","abrufe":1,"zuletzt":"2026-08-14 20:58:35"},{"pfad":"/satzung360s","abrufe":1,"zuletzt":"2026-08-15 10:42:06"}],"unbesucht":[{"pfad":"/barrierefreiheit_grafik.php","gecrawlt":false},{"pfad":"/ru/404.php","gecrawlt":false}],"nicht_gecrawlt":[{"pfad":"/"},{"pfad":"/404.php"},{"pfad":"/aktuelles.php"},{"pfad":"/anmeldung.php"},{"pfad":"/anmeldung_ansicht.php"},{"pfad":"/anmeldung_entwurf.php"},{"pfad":"/anmeldung_fertig.php"},{"pfad":"/anmeldung_listen.php"},{"pfad":"/anmeldung_pruefen.php"},{"pfad":"/anmeldung_stil.php"},{"pfad":"/anmeldung_zusammen.php"},{"pfad":"/barrierefreiheit.php"},{"pfad":"/barrierefreiheit_grafik.php"},{"pfad":"/en"},{"pfad":"/en/404.php"},{"pfad":"/en/aktuelles.php"},{"pfad":"/en/barrierefreiheit.php"},{"pfad":"/en/datenschutz.php"},{"pfad":"/en/impressum.php"},{"pfad":"/en/kasse.php"},{"pfad":"/en/kontakt.php"},{"pfad":"/en/kontaktformular.php"},{"pfad":"/en/kuendigung.php"},{"pfad":"/en/mitglied.php"},{"pfad":"/en/satzung.php"},{"pfad":"/en/sitemap.php"},{"pfad":"/en/spenden.php"},{"pfad":"/en/transparenz.php"},{"pfad":"/en/ueberuns.php"},{"pfad":"/en/widerruf.php"},{"pfad":"/en/widerrufsrecht.php"},{"pfad":"/kasse.php"},{"pfad":"/kontaktformular.php"},{"pfad":"/kuendigung.php"},{"pfad":"/ro"},{"pfad":"/ro/404.php"},{"pfad":"/ro/aktuelles.php"},{"pfad":"/ro/barrierefreiheit.php"},{"pfad":"/ro/datenschutz.php"},{"pfad":"/ro/impressum.php"}],"seiten_gesamt":100}''';

const String _antwortAngriffe = r'''{"success":true,"tage":30,"muster":[{"pfad":"/en//2019/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//wordpress/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//blog/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:10"},{"pfad":"/en//cms/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/en//wp/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//media/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/en//wp1/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//news/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//wp2/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/en//shop/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//xmlrpc.php","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:10"},{"pfad":"/en//site/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/wp-login.php","versuche":1,"quellen":1,"zuletzt":"2026-08-15 09:33:10"},{"pfad":"/en//sito/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:14"},{"pfad":"/en//test/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//web/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//2018/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//website/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"}],"herkunft":[{"land":"NL","netz":"1337 Services GmbH","versuche":18,"zuletzt":"2026-08-15 10:07:14"},{"land":"DE","netz":"OVH SAS","versuche":1,"zuletzt":"2026-08-15 09:33:10"}],"laender":[{"land":"NL","versuche":18,"quellen":1},{"land":"DE","versuche":1,"quellen":1}],"werkzeuge":[{"werkzeug":"ohne Kennung","versuche":18,"pfade":18,"zuletzt":"2026-08-15 10:07:14"},{"werkzeug":"curl","versuche":1,"pfade":1,"zuletzt":"2026-08-15 09:33:10"}],"antworten":[{"status":404,"versuche":19}],"stunden":[{"stunde":9,"versuche":1},{"stunde":10,"versuche":18}],"letzte":[{"zeit":"2026-08-15 10:07:14","pfad":"/en//sito/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//media/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//wp2/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//site/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//cms/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//2019/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//shop/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//wp1/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//test/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//blog/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//web/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//wordpress/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//website/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//wp/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//news/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//2018/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:10","pfad":"/en//wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:10","pfad":"/en//xmlrpc.php","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 09:33:10","pfad":"/wp-login.php","status":404,"land":"DE","netz":"OVH SAS","bot_name":"curl"}],"verlauf":[{"datum":"2026-08-11","scans":0},{"datum":"2026-08-12","scans":0},{"datum":"2026-08-13","scans":0},{"datum":"2026-08-14","scans":0},{"datum":"2026-08-15","scans":19}],"erfolge":[],"anteil":{"mensch":917,"maschine":4283,"scan":19},"fail2ban":"7 Wachen aktiv, 1 Adressen gesperrt","hinweis":"Abgewiesene Versuche sind der Normalfall — der Auftritt steht im offenen Netz. Wichtig ist die Liste „hat geantwortet\": dort darf nichts stehen, was nach einer Konfigurationsdatei aussieht."}''';

void main() {
  Map<String, dynamic> lies(String roh) => jsonDecode(roh) as Map<String, dynamic>;

  group('Die echten Antworten lassen sich vollstaendig lesen', () {
    test('uebersicht', () {
      final a = lies(_antwortUebersicht);
      expect(a['success'], isTrue);

      final verlauf = webListe(a['verlauf']);
      expect(verlauf, isNotEmpty);
      expect(webZahl(verlauf.first['aufrufe']), greaterThan(0));

      // `summe` ist ein Objekt, `verlauf` eine Liste. Beide Helfer duerfen an
      // der jeweils falschen Form nicht werfen.
      expect(webKarte(a['summe']), isNotEmpty);
      expect(webKarte(a['verlauf']), isEmpty);
      expect(webListe(a['summe']), isEmpty);

      expect(webListe(a['zusammensetzung']).length, 3);
      expect(webListe(a['top_seiten']), isNotEmpty);
      expect(webKarte(a['antwortzeit']), isNotEmpty);

      final note = webKarte(webKarte(a['sicherheit'])['note']);
      expect(webZahl(note['prozent']), inInclusiveRange(0, 100));
    });

    test('besucher — Monatsfenster', () {
      final a = lies(_antwortBesucher);
      expect(webZahl(a['fenster_stunden']), 720);

      // ⚠️ Ueber mehrere Kalendertage ist die Zahl KEINE Besucherzahl. Der
      // Server sagt das ausdruecklich, und der Bildschirm beschriftet sie
      // danach — faellt das Feld weg, steht dort still eine falsche Zahl.
      expect(a['besucher_exakt'], isFalse);

      expect(webKarte(a['summe']), isNotEmpty);
      expect(webKarte(a['tiefe'])['je_besuch'], isNotNull);
      expect(webListe(a['verlauf']), isNotEmpty);
      expect(webListe(a['einstieg']), isNotEmpty);
      expect(webListe(a['maschinen']), isNotEmpty);

      for (final l in webListe(a['laender'])) {
        expect('${l['land']}'.length, 2);
      }
      // Rekonstruierte Zeilen haben ein leeres `tls` — das darf nicht werfen.
      expect(webListe(a['technik']).any((t) => '${t['tls']}'.isEmpty), isTrue);
    });

    test('besucher — Stundenfenster ist exakt und liefert dieselben Felder', () {
      final kurz = lies(_antwortBesucher1h);
      final lang = lies(_antwortBesucher);
      expect(webZahl(kurz['fenster_stunden']), 1);

      // Innerhalb EINES Kalendertages stimmt die Besucherzahl.
      expect(kurz['besucher_exakt'], isTrue);
      // Unter 24 h ist ein Tagesrhythmus sinnlos — sechs von vierundzwanzig
      // Saeulen saehen aus wie „dort liest niemand".
      expect(kurz['rhythmus_sinnvoll'], isFalse);
      expect(webListe(kurz['stunden']), isEmpty);

      // ⚠️ Beide Fenster MUESSEN dieselben Felder liefern. Faellt eines bei
      // kurzem Fenster weg, greift der Bildschirm ins Leere — und zwar nur
      // dann, also genau bei der Einstellung, die niemand testet.
      final fehlend = lang.keys.where((k) => !kurz.containsKey(k)).toList();
      expect(fehlend, isEmpty, reason: 'fehlt bei 1 h: $fehlend');
    });

    test('seiten — SUM() kommt als Zeichenkette, Mensch und Maschine getrennt', () {
      final a = lies(_antwortSeiten);
      final seiten = webListe(a['seiten']);
      expect(seiten, isNotEmpty);

      // Der eigentliche Fallstrick: MySQL liefert SUM() ueber PDO als String.
      expect(seiten.first['mensch'], isA<String>());
      expect(webZahl(seiten.first['mensch']), greaterThanOrEqualTo(0));
      expect(webZahl(seiten.first['aufrufe']), greaterThan(0));

      expect(webListe(a['suchmaschinen']), isNotEmpty);
      expect(webListe(a['nicht_gecrawlt']), isNotEmpty);
      expect(webZahl(a['seiten_gesamt']), greaterThan(0));
      expect(webListe(a['status_verteilung']), isNotEmpty);
      expect(webListe(a['seiten_verlauf']), isNotEmpty);
    });

    test('angriffe', () {
      final a = lies(_antwortAngriffe);
      expect(webListe(a['muster']), isNotEmpty);
      expect(webListe(a['werkzeuge']), isNotEmpty);
      expect(webListe(a['letzte']), isNotEmpty);
      expect(webKarte(a['anteil']), isNotEmpty);
      // Der wichtigste Befund ist der LEERE: hat etwas geantwortet?
      expect(webListe(a['erfolge']), isEmpty);
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

  group('Faecher fuellen die Luecken des Servers', () {
    test('Stunden ohne Zugriffe werden zu 0, nicht zusammengeschoben', () {
      final a = lies(_antwortBesucher);
      final stunden = webFaecher(webListe(a['stunden']), 'stunde', 'aufrufe', 24);
      expect(stunden.length, 24);
      // Jede gelieferte Stunde muss an ihrem Platz stehen.
      for (final s in webListe(a['stunden'])) {
        expect(stunden[webZahl(s['stunde'])], webZahl(s['aufrufe']));
      }
    });

    test('eine Klasse ausserhalb des Rasters wird verworfen statt zu werfen', () {
      final f = webFaecher([
        {'stunde': 3, 'aufrufe': 5},
        {'stunde': 99, 'aufrufe': 7},
        {'stunde': -1, 'aufrufe': 9},
      ], 'stunde', 'aufrufe', 24);
      expect(f[3], 5);
      expect(f.fold<int>(0, (a, b) => a + b), 5);
    });

    test('Wochentage: MySQL zaehlt ab 1 = Sonntag', () {
      // ⚠️ DAYOFWEEK liefert 1 fuer Sonntag. Ohne die Drehung im Bildschirm
      // stuende der Sonntag am Montagsplatz — ein Fehler, den nur bemerkt,
      // wer die Zahlen auswendig kennt.
      final roh = webFaecher([
        {'tag': 1, 'aufrufe': 70},  // Sonntag
        {'tag': 2, 'aufrufe': 10},  // Montag
      ], 'tag', 'aufrufe', 8);
      final gedreht = [roh[2], roh[3], roh[4], roh[5], roh[6], roh[7], roh[1]];
      expect(gedreht.first, 10, reason: 'Montag steht vorne');
      expect(gedreht.last, 70, reason: 'Sonntag steht hinten');
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
      // ⚠️ Unsinn darf kein Kaestchen ergeben, sondern gar nichts.
      expect(webFlagge(''), '');
      expect(webFlagge('D'), '');
      expect(webFlagge('12'), '');
      expect(webFlagge('DEU'), '');
    });

    test('jede Befundstufe hat Farbe und Zeichen, auch eine unbekannte', () {
      for (final stand in ['ok', 'warnung', 'fehler', 'info', 'voellig neu']) {
        expect(webStand(stand).text, isNotEmpty);
      }
      // Eine Stufe, die eine neuere Serverfassung erfindet, faellt auf den
      // neutralen Zweig — nicht auf „Fehler", sonst meldete ein alter Client
      // Alarm fuer etwas, das er nur nicht kennt.
      expect(webStand('voellig neu').farbe, webStand('info').farbe);
    });

    test('Mensch, Maschine und Angriff haben ueberall dieselbe Farbe', () {
      // ⚠️ Zwei Karten mit vertauschten Farben waeren schlimmer als gar keine
      // Farbe. Deshalb kommen alle aus derselben Funktion.
      expect(webArtFarbe('mensch'), kWebMensch);
      expect(webArtFarbe('bot'), kWebMaschine);
      expect(webArtFarbe('maschine'), kWebMaschine);
      expect(webArtFarbe('scan'), kWebScan);
      expect(webArtFarbe('unbekannt'), isNot(kWebMensch));
      expect(webArtName('mensch'), 'Menschen');
      expect(webArtName('scan'), 'Angriffsversuche');
    });

    test('Prozente werden deutsch geschrieben', () {
      // ⚠️ toStringAsFixed liefert den Punkt; „83.1 %" liest sich auf einer
      // durchweg deutschen Oberflaeche wie ein Tippfehler.
      expect(webProzent(917, 5219), '17,6 %');
      expect(webProzent(0, 59), '0,0 %');
      expect(webProzent(5, 0), '—');
    });

    test('ein Punkt kennt seine Summe', () {
      expect(const WebPunkt('x', [3, 4, 5]).summe, 12);
      expect(const WebPunkt('x', []).summe, 0);
    });
  });
}
