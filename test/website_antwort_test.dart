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

const String _antwortUebersicht = r'''{"success":true,"tage":30,"tiefe":{"besuche":260,"aufrufe":1060,"nur_eine":105,"tiefster":173,"je_besuch":4.08},"ausstieg":[{"pfad":"\/en","besuche":26},{"pfad":"\/impressum.php","besuche":25},{"pfad":"\/barrierefreiheit.php","besuche":20},{"pfad":"\/satzung.php","besuche":18},{"pfad":"\/ueberuns.php","besuche":14},{"pfad":"\/widerrufsrecht.php","besuche":12},{"pfad":"\/spenden.php","besuche":11},{"pfad":"\/kuendigung.php","besuche":9}],"dauer":{"median_s":3,"besuche":155},"verlauf":[{"datum":"2026-08-11","aufrufe":15,"besucher":1,"aufrufe_bot":129,"scans":0,"bytes":1314533,"fehler_4xx":5,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":1,"quelle":"rekonstruiert"},{"datum":"2026-08-12","aufrufe":266,"besucher":75,"aufrufe_bot":1005,"scans":0,"bytes":59642628,"fehler_4xx":5,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":14,"quelle":"rekonstruiert"},{"datum":"2026-08-13","aufrufe":152,"besucher":68,"aufrufe_bot":106,"scans":0,"bytes":18764328,"fehler_4xx":0,"fehler_5xx":0,"dauer_p50":0,"dauer_p95":0,"laender":11,"quelle":"rekonstruiert"},{"datum":"2026-08-14","aufrufe":340,"besucher":36,"aufrufe_bot":2497,"scans":0,"bytes":174357281,"fehler_4xx":37,"fehler_5xx":10,"dauer_p50":0,"dauer_p95":0,"laender":12,"quelle":"rekonstruiert"},{"datum":"2026-08-15","aufrufe":287,"besucher":80,"aufrufe_bot":2875,"scans":172,"bytes":131815552,"fehler_4xx":441,"fehler_5xx":0,"dauer_p50":2,"dauer_p95":9,"laender":19,"quelle":"gemischt"}],"summe":{"aufrufe":1060,"aufrufe_bot":6612,"scans":172,"bytes":385894322,"fehler_4xx":488,"fehler_5xx":10},"stand":"2026-08-15 18:07:01","zusammensetzung":[{"art":"mensch","aufrufe":1060},{"art":"maschine","aufrufe":6612},{"art":"scan","aufrufe":172}],"top_seiten":[{"pfad":"\/impressum.php","aufrufe":"80"},{"pfad":"\/kasse.php","aufrufe":"76"},{"pfad":"\/widerrufsrecht.php","aufrufe":"75"},{"pfad":"\/datenschutz.php","aufrufe":"75"},{"pfad":"\/en","aufrufe":"66"},{"pfad":"\/barrierefreiheit.php","aufrufe":"53"}],"sprachen":[{"sprache":"de","aufrufe":831},{"sprache":"en","aufrufe":119},{"sprache":"ro","aufrufe":90},{"sprache":"uk","aufrufe":9},{"sprache":"ru","aufrufe":6},{"sprache":"fr","aufrufe":5}],"geraete":[{"geraet":"handy","aufrufe":406},{"geraet":"desktop","aufrufe":395},{"geraet":"unbekannt","aufrufe":253},{"geraet":"tablet","aufrufe":6}],"laender":[{"land":"US","aufrufe":252},{"land":"DE","aufrufe":246},{"land":"FR","aufrufe":175},{"land":"NL","aufrufe":96},{"land":"HU","aufrufe":49},{"land":"BR","aufrufe":35},{"land":"SG","aufrufe":31},{"land":"KR","aufrufe":24}],"antwortzeit":{"mittel":2,"hoechst":14,"ueber_1s":0,"n":1060,"p50":2,"p95":5,"gemessen":102},"ziele":[{"schluessel":"mitglied","name":"Mitglied werden","pfad":"\/mitglied.php","aufrufe":44,"anteil":4.2},{"schluessel":"spenden","name":"Spenden","pfad":"\/spenden.php","aufrufe":50,"anteil":4.7},{"schluessel":"kontakt","name":"Kontakt","pfad":"\/kontakt.php","aufrufe":47,"anteil":4.4},{"schluessel":"anmeldung","name":"Antrag begonnen","pfad":"\/anmeldung.php","aufrufe":27,"anteil":2.5},{"schluessel":"satzung","name":"Satzung","pfad":"\/satzung.php","aufrufe":49,"anteil":4.6},{"schluessel":"transparenz","name":"Transparenz","pfad":"\/transparenz.php","aufrufe":38,"anteil":3.6},{"schluessel":"kasse","name":"Offene Kasse","pfad":"\/kasse.php","aufrufe":84,"anteil":7.9},{"schluessel":"barrierefreiheit","name":"Barrierefreiheit","pfad":"\/barrierefreiheit.php","aufrufe":58,"anteil":5.5},{"schluessel":"leichte_sprache","name":"Leichte Sprache","pfad":"\/leichte-sprache.php","aufrufe":8,"anteil":0.8}],"ziele_grundlage":1060,"trichter":[{"stufe":1,"name":"Beginn","pfad":"\/anmeldung.php","aufrufe":27},{"stufe":2,"name":"Sprache","pfad":"\/anmeldung_sprache.php","aufrufe":0},{"stufe":3,"name":"Darstellung","pfad":"\/anmeldung_stil.php","aufrufe":0},{"stufe":4,"name":"Zusammenfassung","pfad":"\/anmeldung_zusammen.php","aufrufe":0},{"stufe":5,"name":"Pr\u00fcfen","pfad":"\/anmeldung_pruefen.php","aufrufe":0},{"stufe":6,"name":"Abgeschickt","pfad":"\/anmeldung_fertig.php","aufrufe":0}],"verweise":[{"woher":"(direkt)","aufrufe":1035},{"woher":"ip53.ip-135-125-150.eu","aufrufe":15},{"woher":"securityheaders.com","aufrufe":8},{"woher":"135.125.150.53","aufrufe":2}],"verweise_direkt":1035,"besucher_mittel":52,"besucher_bester":80,"vergleich":{"aufrufe_vorher":0,"besucher_vorher":0,"bot_vorher":0,"scans_vorher":0,"bytes_vorher":0},"sicherheit":{"note":{"prozent":100,"stufe":"sehr gut","fehler":0,"warnungen":0,"geprueft":62},"geprueft":"2026-08-15 17:56:48"},"daten_ab":"2026-08-11","hinweis":"Gez\u00e4hlt wird im Zugriffsprotokoll des Servers, ohne Skript und ohne Cookie im Browser. Deshalb braucht der Auftritt keinen Einwilligungsbanner. Besucher werden \u00fcber einen t\u00e4glich neu gesalzenen Pr\u00fcfwert unterschieden \u2014 genau ist das nie, hinter einem Mobilfunk-Zugang teilen sich viele Menschen eine Adresse."}''';

const String _antwortBesucher = r'''{"success":true,"tage":30,"fehlseiten":[{"pfad":"\/.well-known\/passkey-endpoints","aufrufe":6,"mensch":"6","zuletzt":"2026-08-15 17:35:37"},{"pfad":"\/en","aufrufe":5,"mensch":"5","zuletzt":"2026-08-14 23:22:06"},{"pfad":"\/sprachen.php","aufrufe":46,"mensch":"0","zuletzt":"2026-08-15 12:36:35"},{"pfad":"\/404.php","aufrufe":43,"mensch":"0","zuletzt":"2026-08-15 12:35:06"},{"pfad":"\/header.php","aufrufe":5,"mensch":"0","zuletzt":"2026-08-14 22:23:22"},{"pfad":"\/footer.php","aufrufe":4,"mensch":"0","zuletzt":"2026-08-14 22:23:22"},{"pfad":"\/\/wp-includes\/assets","aufrufe":4,"mensch":"0","zuletzt":"2026-08-15 18:03:02"},{"pfad":"\/yj09.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 18:02:51"},{"pfad":"\/wp-content\/plugins\/hellopress\/wp_filemanager.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 18:02:45"},{"pfad":"\/en\/404.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 00:14:12"},{"pfad":"\/this_is_a_new_hello_world.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 18:02:46"},{"pfad":"\/coffexium.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 18:02:50"},{"pfad":"\/ro\/404.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 00:14:12"},{"pfad":"\/fpwch.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 18:02:54"},{"pfad":"\/biufile.php","aufrufe":3,"mensch":"0","zuletzt":"2026-08-15 18:02:49"}],"maschinen_absicht":[{"gruppe":"werkzeug","aufrufe":6553,"namen":[{"bot_name":"curl","aufrufe":2288,"zuletzt":"2026-08-15 17:22:08"},{"bot_name":"Chrome (headless)","aufrufe":2145,"zuletzt":"2026-08-15 17:19:16"},{"bot_name":"Crawler","aufrufe":1528,"zuletzt":"2026-08-15 18:39:40"},{"bot_name":"ohne Kennung","aufrufe":544,"zuletzt":"2026-08-15 18:56:15"},{"bot_name":"Bot","aufrufe":48,"zuletzt":"2026-08-15 18:25:25"}]},{"gruppe":"ki","aufrufe":435,"namen":[{"bot_name":"Amazon","aufrufe":135,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"ChatGPT (Nutzeraufruf)","aufrufe":100,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"OpenAI GPTBot","aufrufe":94,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"OpenAI Search","aufrufe":37,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"Perplexity","aufrufe":37,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Anthropic ClaudeBot","aufrufe":32,"zuletzt":"2026-08-15 18:25:26"}]},{"gruppe":"suchmaschine","aufrufe":30,"namen":[{"bot_name":"Google","aufrufe":27,"zuletzt":"2026-08-15 18:42:38"},{"bot_name":"Bing","aufrufe":3,"zuletzt":"2026-08-15 17:59:44"}]},{"gruppe":"messung","aufrufe":1,"namen":[{"bot_name":"Messprojekt","aufrufe":1,"zuletzt":"2026-08-15 18:39:30"}]}],"wege":[{"vorher":"\/datenschutz.php","pfad":"\/widerrufsrecht.php","n":21},{"vorher":"\/impressum.php","pfad":"\/datenschutz.php","n":20},{"vorher":"\/transparenz.php","pfad":"\/kasse.php","n":14},{"vorher":"\/widerrufsrecht.php","pfad":"\/kuendigung.php","n":13},{"vorher":"\/sitemap.php","pfad":"\/spenden.php","n":13},{"vorher":"\/kontakt.php","pfad":"\/sitemap.php","n":11},{"vorher":"\/spenden.php","pfad":"\/barrierefreiheit.php","n":11},{"vorher":"\/kuendigung.php","pfad":"\/satzung.php","n":11},{"vorher":"\/ueberuns.php","pfad":"\/mitglied.php","n":11},{"vorher":"\/mitglied.php","pfad":"\/anmeldung.php","n":11},{"vorher":"\/barrierefreiheit.php","pfad":"\/aktuelles.php","n":10},{"vorher":"\/aktuelles.php","pfad":"\/ueberuns.php","n":10}],"tiefe_klassen":[{"klasse":"1 Seite","sortier":1,"besuche":108},{"klasse":"2 Seiten","sortier":2,"besuche":104},{"klasse":"3-4","sortier":3,"besuche":23},{"klasse":"5-9","sortier":4,"besuche":17},{"klasse":"10-19","sortier":5,"besuche":12},{"klasse":"20 und mehr","sortier":6,"besuche":8}],"dauer_klassen":[{"klasse":"unter 10 s","sortier":1,"besuche":111},{"klasse":"10-29 s","sortier":2,"besuche":11},{"klasse":"30-59 s","sortier":3,"besuche":3},{"klasse":"1-4 min","sortier":4,"besuche":9},{"klasse":"5-14 min","sortier":5,"besuche":7},{"klasse":"15 min und mehr","sortier":6,"besuche":23}],"letzte":[{"zeit":"2026-08-15 19:03:14","pfad":"\/impressum.php","sprache":"de","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":3,"ip_art":"v6"},{"zeit":"2026-08-15 19:03:14","pfad":"\/pl\/impressum.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":303,"dauer_ms":1,"ip_art":"v6"},{"zeit":"2026-08-15 19:03:00","pfad":"\/pl\/impressum.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":3,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:57","pfad":"\/pl\/datenschutz.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:55","pfad":"\/pl\/widerrufsrecht.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":1,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:47","pfad":"\/pl\/kuendigung.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":5,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:39","pfad":"\/pl\/satzung.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:36","pfad":"\/pl","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":5,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:36","pfad":"\/index.php","sprache":"de","land":"LU","geraet":"desktop","art":"mensch","status":303,"dauer_ms":1,"ip_art":"v6"},{"zeit":"2026-08-15 18:59:43","pfad":"\/fr\/transparenz.php","sprache":"fr","land":"US","geraet":"handy","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:28","pfad":"\/index.php","sprache":"de","land":"NL","geraet":"desktop","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v6"},{"zeit":"2026-08-15 18:56:15","pfad":"\/","sprache":"de","land":"NL","geraet":"unbekannt","art":"bot","status":400,"dauer_ms":13,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/sito\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":19,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/cms\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":10,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/site\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":13,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/wp2\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":11,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/media\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":13,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/test\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":15,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/wp1\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":12,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/shop\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":20,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/2019\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":14,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/2018\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":14,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/news\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":15,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/wp\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":11,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/website\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":12,"ip_art":"v4"}],"fenster_stunden":720,"von":"2026-07-16 19:20:31","klasse_sekunden":86400,"besucher_exakt":false,"stand":"2026-08-15 19:07:02","summe":{"aufrufe":1094,"besucher":272,"maschinen":6798,"scans":413},"tiefe":{"besuche":272,"aufrufe":1094,"nur_eine":108,"tiefster":173,"je_besuch":4.02},"verlauf":[{"klasse":"2026-08-10 02:00:00","aufrufe":2,"besucher":1,"maschinen":"2"},{"klasse":"2026-08-11 02:00:00","aufrufe":275,"besucher":12,"maschinen":"254"},{"klasse":"2026-08-12 02:00:00","aufrufe":1224,"besucher":95,"maschinen":"940"},{"klasse":"2026-08-13 02:00:00","aufrufe":202,"besucher":65,"maschinen":"74"},{"klasse":"2026-08-14 02:00:00","aufrufe":3079,"besucher":317,"maschinen":"2669"},{"klasse":"2026-08-15 02:00:00","aufrufe":3523,"besucher":120,"maschinen":"2859"}],"zusammensetzung":[{"art":"mensch","aufrufe":1094},{"art":"bot","aufrufe":6798},{"art":"scan","aufrufe":413}],"laender":[{"land":"US","aufrufe":256,"besucher":86},{"land":"DE","aufrufe":246,"besucher":43},{"land":"FR","aufrufe":175,"besucher":2},{"land":"NL","aufrufe":106,"besucher":22},{"land":"HU","aufrufe":49,"besucher":1},{"land":"BR","aufrufe":35,"besucher":19},{"land":"SG","aufrufe":35,"besucher":20},{"land":"KR","aufrufe":27,"besucher":16},{"land":"JP","aufrufe":24,"besucher":17},{"land":"SE","aufrufe":20,"besucher":6},{"land":"HK","aufrufe":17,"besucher":10},{"land":"SC","aufrufe":17,"besucher":3},{"land":"LU","aufrufe":15,"besucher":3},{"land":"PL","aufrufe":14,"besucher":6},{"land":"TH","aufrufe":12,"besucher":5},{"land":"UA","aufrufe":12,"besucher":1},{"land":"ID","aufrufe":9,"besucher":4},{"land":"IE","aufrufe":8,"besucher":1},{"land":"AL","aufrufe":6,"besucher":1},{"land":"GB","aufrufe":5,"besucher":2},{"land":"CA","aufrufe":2,"besucher":1},{"land":"VN","aufrufe":2,"besucher":1},{"land":"CN","aufrufe":1,"besucher":1},{"land":"AT","aufrufe":1,"besucher":1}],"netze":[{"netz":"Shenzhen Tencent Computer Systems Company Limited","aufrufe":293,"besucher":172},{"netz":"OVH SAS","aufrufe":230,"besucher":5},{"netz":"Stiftung Erneuerbare Freiheit","aufrufe":117,"besucher":13},{"netz":"Google LLC","aufrufe":109,"besucher":13},{"netz":"Church of Cyberology","aufrufe":91,"besucher":13},{"netz":"ATW Internet Kft.","aufrufe":49,"besucher":1},{"netz":"Deutsche Telekom AG","aufrufe":29,"besucher":5},{"netz":"Microsoft Corporation","aufrufe":27,"besucher":3},{"netz":"FranTech Solutions","aufrufe":19,"besucher":4},{"netz":"SABOTAGE LLC","aufrufe":17,"besucher":3},{"netz":"Amazon.com, Inc.","aufrufe":16,"besucher":3},{"netz":"Foreningen for digitala fri- och rattigheter","aufrufe":15,"besucher":3},{"netz":"Wojciech Czapkowicz","aufrufe":12,"besucher":5},{"netz":"SERVER.UA LLC","aufrufe":12,"besucher":1},{"netz":"Ruhr-Universitaet Bochum","aufrufe":11,"besucher":1},{"netz":"1337 Services GmbH","aufrufe":6,"besucher":3},{"netz":"Fastly, Inc.","aufrufe":6,"besucher":1},{"netz":"F3 Netze e.V.","aufrufe":4,"besucher":3},{"netz":"Internet Vikings International AB","aufrufe":4,"besucher":2},{"netz":"University of Waterloo","aufrufe":2,"besucher":1}],"geraete":[{"geraet":"handy","aufrufe":421},{"geraet":"desktop","aufrufe":414},{"geraet":"unbekannt","aufrufe":253},{"geraet":"tablet","aufrufe":6}],"sprachen":[{"sprache":"de","aufrufe":845,"besucher":202},{"sprache":"en","aufrufe":127,"besucher":61},{"sprache":"ro","aufrufe":92,"besucher":29},{"sprache":"uk","aufrufe":9,"besucher":6},{"sprache":"fr","aufrufe":7,"besucher":4},{"sprache":"pl","aufrufe":7,"besucher":1},{"sprache":"ru","aufrufe":7,"besucher":5}],"einstieg":[{"pfad":"\/en","besuche":31},{"pfad":"\/impressum.php","besuche":24},{"pfad":"\/barrierefreiheit.php","besuche":18},{"pfad":"\/satzung.php","besuche":17},{"pfad":"\/widerrufsrecht.php","besuche":15},{"pfad":"\/ueberuns.php","besuche":13},{"pfad":"\/kuendigung.php","besuche":11},{"pfad":"\/","besuche":11},{"pfad":"\/anmeldung.php","besuche":11},{"pfad":"\/spenden.php","besuche":10},{"pfad":"\/sitemap.php","besuche":9},{"pfad":"\/aktuelles.php","besuche":9}],"maschinen":[{"bot_name":"curl","aufrufe":2288,"zuletzt":"2026-08-15 17:22:08"},{"bot_name":"Chrome (headless)","aufrufe":2145,"zuletzt":"2026-08-15 17:19:16"},{"bot_name":"Crawler","aufrufe":1528,"zuletzt":"2026-08-15 18:39:40"},{"bot_name":"ohne Kennung","aufrufe":544,"zuletzt":"2026-08-15 18:56:15"},{"bot_name":"OpenAI GPTBot","aufrufe":76,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Amazon","aufrufe":56,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"ChatGPT (Nutzeraufruf)","aufrufe":44,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Bot","aufrufe":34,"zuletzt":"2026-08-15 18:25:25"},{"bot_name":"Google","aufrufe":27,"zuletzt":"2026-08-15 18:42:38"},{"bot_name":"Perplexity","aufrufe":21,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"OpenAI Search","aufrufe":17,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"Anthropic ClaudeBot","aufrufe":14,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Bing","aufrufe":3,"zuletzt":"2026-08-15 17:59:44"},{"bot_name":"Messprojekt","aufrufe":1,"zuletzt":"2026-08-15 18:39:30"}],"ip_art":[{"ip_art":"v4","aufrufe":800,"besucher":219},{"ip_art":"v6","aufrufe":294,"besucher":53}],"tls_art":[{"tls":"","aufrufe":943},{"tls":"TLSv1.3","aufrufe":149},{"tls":"TLSv1.2","aufrufe":2}],"status":[{"status":200,"aufrufe":838},{"status":303,"aufrufe":223},{"status":301,"aufrufe":16},{"status":404,"aufrufe":11},{"status":500,"aufrufe":6}],"stunden":[{"stunde":0,"aufrufe":81},{"stunde":1,"aufrufe":19},{"stunde":2,"aufrufe":17},{"stunde":3,"aufrufe":24},{"stunde":4,"aufrufe":32},{"stunde":5,"aufrufe":20},{"stunde":6,"aufrufe":23},{"stunde":7,"aufrufe":11},{"stunde":8,"aufrufe":17},{"stunde":9,"aufrufe":11},{"stunde":10,"aufrufe":16},{"stunde":11,"aufrufe":37},{"stunde":12,"aufrufe":36},{"stunde":13,"aufrufe":32},{"stunde":14,"aufrufe":29},{"stunde":15,"aufrufe":94},{"stunde":16,"aufrufe":61},{"stunde":17,"aufrufe":108},{"stunde":18,"aufrufe":127},{"stunde":19,"aufrufe":103},{"stunde":20,"aufrufe":85},{"stunde":21,"aufrufe":32},{"stunde":22,"aufrufe":19},{"stunde":23,"aufrufe":60}],"rhythmus_sinnvoll":true,"wochentage":[{"tag":3,"aufrufe":15},{"tag":4,"aufrufe":266},{"tag":5,"aufrufe":152},{"tag":6,"aufrufe":340},{"tag":7,"aufrufe":321}],"technik":[{"tls":"","protokoll":"HTTP\/1.1","ip_art":"v4","aufrufe":444},{"tls":"","protokoll":"HTTP\/2.0","ip_art":"v4","aufrufe":270},{"tls":"","protokoll":"HTTP\/2.0","ip_art":"v6","aufrufe":227},{"tls":"TLSv1.3","protokoll":"HTTP\/1.1","ip_art":"v4","aufrufe":76},{"tls":"TLSv1.3","protokoll":"HTTP\/2.0","ip_art":"v6","aufrufe":65},{"tls":"TLSv1.3","protokoll":"HTTP\/2.0","ip_art":"v4","aufrufe":8},{"tls":"","protokoll":"HTTP\/1.1","ip_art":"v6","aufrufe":2},{"tls":"TLSv1.2","protokoll":"HTTP\/1.1","ip_art":"v4","aufrufe":2}]}''';

const String _antwortBesucher1h = r'''{"success":true,"tage":30,"fehlseiten":[{"pfad":"\/en\/\/xmlrpc.php","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/test\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/blog\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/media\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/web\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/wp2\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/wordpress\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/site\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/website\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/cms\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/@fs\/proc\/self\/environ","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:25:22"},{"pfad":"\/en\/\/wp\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/en\/\/sito\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"},{"pfad":"\/@fs\/etc\/passwd","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:25:22"},{"pfad":"\/en\/\/news\/wp-includes\/wlwmanifest.xml","aufrufe":1,"mensch":"0","zuletzt":"2026-08-15 18:56:15"}],"maschinen_absicht":[{"gruppe":"ki","aufrufe":354,"namen":[{"bot_name":"Amazon","aufrufe":123,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"ChatGPT (Nutzeraufruf)","aufrufe":100,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"OpenAI Search","aufrufe":37,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"Perplexity","aufrufe":37,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Anthropic ClaudeBot","aufrufe":32,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"OpenAI GPTBot","aufrufe":25,"zuletzt":"2026-08-15 18:25:26"}]},{"gruppe":"werkzeug","aufrufe":50,"namen":[{"bot_name":"Bot","aufrufe":32,"zuletzt":"2026-08-15 18:25:25"},{"bot_name":"ohne Kennung","aufrufe":17,"zuletzt":"2026-08-15 18:56:15"},{"bot_name":"Crawler","aufrufe":1,"zuletzt":"2026-08-15 18:39:40"}]},{"gruppe":"suchmaschine","aufrufe":1,"namen":[{"bot_name":"Google","aufrufe":1,"zuletzt":"2026-08-15 18:42:38"}]},{"gruppe":"messung","aufrufe":1,"namen":[{"bot_name":"Messprojekt","aufrufe":1,"zuletzt":"2026-08-15 18:39:30"}]}],"wege":[{"vorher":"\/","pfad":"\/en","n":3},{"vorher":"\/en\/anmeldung.php","pfad":"\/fr\/anmeldung.php","n":1},{"vorher":"\/leichte-sprache.php","pfad":"\/ru\/index.php","n":1},{"vorher":"\/en\/transparenz.php","pfad":"\/transparenz.php","n":1},{"vorher":"\/index.php","pfad":"\/pl","n":1},{"vorher":"\/pl","pfad":"\/pl\/satzung.php","n":1},{"vorher":"\/pl\/satzung.php","pfad":"\/pl\/kuendigung.php","n":1},{"vorher":"\/pl\/kuendigung.php","pfad":"\/pl\/widerrufsrecht.php","n":1},{"vorher":"\/pl\/widerrufsrecht.php","pfad":"\/pl\/datenschutz.php","n":1},{"vorher":"\/pl\/datenschutz.php","pfad":"\/pl\/impressum.php","n":1},{"vorher":"\/pl\/impressum.php","pfad":"\/impressum.php","n":1}],"tiefe_klassen":[{"klasse":"1 Seite","sortier":1,"besuche":4},{"klasse":"2 Seiten","sortier":2,"besuche":6},{"klasse":"3-4","sortier":3,"besuche":2},{"klasse":"5-9","sortier":4,"besuche":1}],"dauer_klassen":[{"klasse":"unter 10 s","sortier":1,"besuche":6},{"klasse":"10-29 s","sortier":2,"besuche":1},{"klasse":"30-59 s","sortier":3,"besuche":1},{"klasse":"1-4 min","sortier":4,"besuche":1}],"letzte":[{"zeit":"2026-08-15 19:03:14","pfad":"\/impressum.php","sprache":"de","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":3,"ip_art":"v6"},{"zeit":"2026-08-15 19:03:14","pfad":"\/pl\/impressum.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":303,"dauer_ms":1,"ip_art":"v6"},{"zeit":"2026-08-15 19:03:00","pfad":"\/pl\/impressum.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":3,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:57","pfad":"\/pl\/datenschutz.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:55","pfad":"\/pl\/widerrufsrecht.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":1,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:47","pfad":"\/pl\/kuendigung.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":5,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:39","pfad":"\/pl\/satzung.php","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:36","pfad":"\/pl","sprache":"pl","land":"LU","geraet":"desktop","art":"mensch","status":200,"dauer_ms":5,"ip_art":"v6"},{"zeit":"2026-08-15 19:02:36","pfad":"\/index.php","sprache":"de","land":"LU","geraet":"desktop","art":"mensch","status":303,"dauer_ms":1,"ip_art":"v6"},{"zeit":"2026-08-15 18:59:43","pfad":"\/fr\/transparenz.php","sprache":"fr","land":"US","geraet":"handy","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:28","pfad":"\/index.php","sprache":"de","land":"NL","geraet":"desktop","art":"mensch","status":200,"dauer_ms":2,"ip_art":"v6"},{"zeit":"2026-08-15 18:56:15","pfad":"\/","sprache":"de","land":"NL","geraet":"unbekannt","art":"bot","status":400,"dauer_ms":13,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/sito\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":19,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/cms\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":10,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/site\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":13,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/wp2\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":11,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/media\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":13,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/test\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":15,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/wp1\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":12,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/shop\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":20,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/2019\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":14,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/2018\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":14,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/news\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":15,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/wp\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":11,"ip_art":"v4"},{"zeit":"2026-08-15 18:56:15","pfad":"\/en\/\/website\/wp-includes\/wlwmanifest.xml","sprache":"en","land":"NL","geraet":"desktop","art":"scan","status":404,"dauer_ms":12,"ip_art":"v4"}],"fenster_stunden":1,"von":"2026-08-15 18:20:31","klasse_sekunden":300,"besucher_exakt":true,"stand":"2026-08-15 19:07:02","summe":{"aufrufe":31,"besucher":13,"maschinen":185,"scans":241},"tiefe":{"besuche":13,"aufrufe":31,"nur_eine":4,"tiefster":9,"je_besuch":2.38},"verlauf":[{"klasse":"2026-08-15 18:25:00","aufrufe":408,"besucher":16,"maschinen":"178"},{"klasse":"2026-08-15 18:35:00","aufrufe":2,"besucher":2,"maschinen":"2"},{"klasse":"2026-08-15 18:40:00","aufrufe":7,"besucher":5,"maschinen":"3"},{"klasse":"2026-08-15 18:45:00","aufrufe":3,"besucher":2,"maschinen":"0"},{"klasse":"2026-08-15 18:50:00","aufrufe":3,"besucher":1,"maschinen":"0"},{"klasse":"2026-08-15 18:55:00","aufrufe":25,"besucher":4,"maschinen":"2"},{"klasse":"2026-08-15 19:00:00","aufrufe":9,"besucher":1,"maschinen":"0"}],"zusammensetzung":[{"art":"mensch","aufrufe":31},{"art":"bot","aufrufe":185},{"art":"scan","aufrufe":241}],"laender":[{"land":"NL","aufrufe":10,"besucher":6},{"land":"LU","aufrufe":9,"besucher":1},{"land":"US","aufrufe":3,"besucher":2},{"land":"KR","aufrufe":3,"besucher":1},{"land":"SG","aufrufe":2,"besucher":1},{"land":"HK","aufrufe":2,"besucher":1},{"land":"ID","aufrufe":2,"besucher":1}],"netze":[{"netz":"Shenzhen Tencent Computer Systems Company Limited","aufrufe":10,"besucher":5},{"netz":"FranTech Solutions","aufrufe":9,"besucher":1},{"netz":"Google LLC","aufrufe":7,"besucher":4},{"netz":"1337 Services GmbH","aufrufe":3,"besucher":1},{"netz":"Church of Cyberology","aufrufe":2,"besucher":2}],"geraete":[{"geraet":"desktop","aufrufe":19},{"geraet":"handy","aufrufe":12}],"sprachen":[{"sprache":"de","aufrufe":14,"besucher":10},{"sprache":"pl","aufrufe":7,"besucher":1},{"sprache":"en","aufrufe":5,"besucher":5},{"sprache":"ro","aufrufe":2,"besucher":1},{"sprache":"fr","aufrufe":2,"besucher":2},{"sprache":"ru","aufrufe":1,"besucher":1}],"einstieg":[{"pfad":"\/","besuche":5},{"pfad":"\/index.php","besuche":3},{"pfad":"\/fr\/transparenz.php","besuche":1},{"pfad":"\/en\/anmeldung.php","besuche":1},{"pfad":"\/leichte-sprache.php","besuche":1},{"pfad":"\/en\/transparenz.php","besuche":1},{"pfad":"\/ro\/index.php","besuche":1}],"maschinen":[{"bot_name":"ChatGPT (Nutzeraufruf)","aufrufe":44,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Amazon","aufrufe":44,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"Perplexity","aufrufe":21,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Bot","aufrufe":18,"zuletzt":"2026-08-15 18:25:25"},{"bot_name":"ohne Kennung","aufrufe":17,"zuletzt":"2026-08-15 18:56:15"},{"bot_name":"OpenAI Search","aufrufe":17,"zuletzt":"2026-08-15 18:25:27"},{"bot_name":"Anthropic ClaudeBot","aufrufe":14,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"OpenAI GPTBot","aufrufe":7,"zuletzt":"2026-08-15 18:25:26"},{"bot_name":"Messprojekt","aufrufe":1,"zuletzt":"2026-08-15 18:39:30"},{"bot_name":"Crawler","aufrufe":1,"zuletzt":"2026-08-15 18:39:40"},{"bot_name":"Google","aufrufe":1,"zuletzt":"2026-08-15 18:42:38"}],"ip_art":[{"ip_art":"v4","aufrufe":20,"besucher":10},{"ip_art":"v6","aufrufe":11,"besucher":3}],"tls_art":[{"tls":"TLSv1.3","aufrufe":26},{"tls":"","aufrufe":3},{"tls":"TLSv1.2","aufrufe":2}],"status":[{"status":200,"aufrufe":20},{"status":303,"aufrufe":8},{"status":301,"aufrufe":3}],"stunden":[],"rhythmus_sinnvoll":false,"wochentage":[],"technik":[{"tls":"TLSv1.3","protokoll":"HTTP\/1.1","ip_art":"v4","aufrufe":15},{"tls":"TLSv1.3","protokoll":"HTTP\/2.0","ip_art":"v6","aufrufe":11},{"tls":"","protokoll":"HTTP\/1.1","ip_art":"v4","aufrufe":3},{"tls":"TLSv1.2","protokoll":"HTTP\/1.1","ip_art":"v4","aufrufe":2}]}''';

const String _antwortSeiten = r'''{"success":true,"tage":30,"seiten":[{"pfad":"/impressum.php","mensch":"80","maschine":"433","besucher":37,"aufrufe":513,"dauer":"7","bytes":"23869253","zuletzt":"2026-08-15 09:37:28"},{"pfad":"/datenschutz.php","mensch":"76","maschine":"288","besucher":22,"aufrufe":364,"dauer":"10","bytes":"20290908","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/satzung.php","mensch":"45","maschine":"282","besucher":26,"aufrufe":327,"dauer":"7","bytes":"19294798","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/widerrufsrecht.php","mensch":"75","maschine":"239","besucher":24,"aufrufe":314,"dauer":"14","bytes":"15031232","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/kontakt.php","mensch":"41","maschine":"260","besucher":18,"aufrufe":301,"dauer":"10","bytes":"14318183","zuletzt":"2026-08-15 09:34:58"},{"pfad":"/kasse.php","mensch":"76","maschine":"171","besucher":19,"aufrufe":247,"dauer":"15","bytes":"12785481","zuletzt":"2026-08-15 09:34:58"},{"pfad":"/anmeldung.php","mensch":"25","maschine":"219","besucher":14,"aufrufe":244,"dauer":"16","bytes":"14307600","zuletzt":"2026-08-15 09:17:23"},{"pfad":"/sitemap.php","mensch":"28","maschine":"215","besucher":15,"aufrufe":243,"dauer":"12","bytes":"13445621","zuletzt":"2026-08-15 09:34:59"},{"pfad":"/spenden.php","mensch":"48","maschine":"176","besucher":20,"aufrufe":224,"dauer":"12","bytes":"13436639","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/ueberuns.php","mensch":"41","maschine":"162","besucher":26,"aufrufe":203,"dauer":"7","bytes":"12289537","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/kuendigung.php","mensch":"40","maschine":"163","besucher":17,"aufrufe":203,"dauer":"24","bytes":"13195529","zuletzt":"2026-08-15 09:34:59"},{"pfad":"/mitglied.php","mensch":"39","maschine":"160","besucher":15,"aufrufe":199,"dauer":"12","bytes":"12250844","zuletzt":"2026-08-15 09:34:59"},{"pfad":"/kontaktformular.php","mensch":"25","maschine":"172","besucher":12,"aufrufe":197,"dauer":"21","bytes":"11829158","zuletzt":"2026-08-15 09:34:58"},{"pfad":"/barrierefreiheit.php","mensch":"33","maschine":"161","besucher":16,"aufrufe":194,"dauer":"13","bytes":"11496786","zuletzt":"2026-08-15 09:34:57"},{"pfad":"/transparenz.php","mensch":"31","maschine":"158","besucher":19,"aufrufe":189,"dauer":"12","bytes":"11434933","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/widerruf.php","mensch":"12","maschine":"159","besucher":3,"aufrufe":171,"dauer":"13","bytes":"10476439","zuletzt":"2026-08-15 09:35:00"},{"pfad":"/aktuelles.php","mensch":"41","maschine":"112","besucher":15,"aufrufe":153,"dauer":"90","bytes":"7016989","zuletzt":"2026-08-15 09:34:57"},{"pfad":"/en","mensch":"45","maschine":"5","besucher":27,"aufrufe":50,"dauer":"44","bytes":"2831941","zuletzt":"2026-08-15 10:19:47"},{"pfad":"/404.php","mensch":"0","maschine":"46","besucher":0,"aufrufe":46,"dauer":"3","bytes":"3193306","zuletzt":"2026-08-15 09:11:20"},{"pfad":"/","mensch":"7","maschine":"31","besucher":4,"aufrufe":38,"dauer":"119","bytes":"53273","zuletzt":"2026-08-15 10:46:53"},{"pfad":"/en/index.php","mensch":"3","maschine":"32","besucher":3,"aufrufe":35,"dauer":"5","bytes":"3861871","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/index.php","mensch":"1","maschine":"27","besucher":1,"aufrufe":28,"dauer":"7","bytes":"831235","zuletzt":"2026-08-15 10:47:02"},{"pfad":"/ro/index.php","mensch":"9","maschine":"17","besucher":8,"aufrufe":26,"dauer":"5","bytes":"2914404","zuletzt":"2026-08-15 10:42:27"},{"pfad":"/en/satzung.php","mensch":"3","maschine":"18","besucher":1,"aufrufe":21,"dauer":"8","bytes":"3051665","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/en/impressum.php","mensch":"1","maschine":"20","besucher":1,"aufrufe":21,"dauer":"9","bytes":"2946397","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/ro/satzung.php","mensch":"5","maschine":"15","besucher":3,"aufrufe":20,"dauer":"7","bytes":"2859038","zuletzt":"2026-08-15 09:35:20"},{"pfad":"/ro/impressum.php","mensch":"4","maschine":"16","besucher":3,"aufrufe":20,"dauer":"9","bytes":"2586671","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/widerruf.php","mensch":"1","maschine":"19","besucher":1,"aufrufe":20,"dauer":"7","bytes":"2697161","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/widerrufsrecht.php","mensch":"3","maschine":"16","besucher":3,"aufrufe":19,"dauer":"8","bytes":"2484642","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/datenschutz.php","mensch":"3","maschine":"14","besucher":3,"aufrufe":17,"dauer":"10","bytes":"2373678","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/ro/ueberuns.php","mensch":"6","maschine":"10","besucher":5,"aufrufe":16,"dauer":"8","bytes":"1671874","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/en/widerrufsrecht.php","mensch":"1","maschine":"15","besucher":1,"aufrufe":16,"dauer":"9","bytes":"2322582","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/widerruf.php","mensch":"1","maschine":"15","besucher":1,"aufrufe":16,"dauer":"7","bytes":"2197646","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/aktuelles.php","mensch":"6","maschine":"10","besucher":5,"aufrufe":16,"dauer":"11","bytes":"1619106","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/ro/kasse.php","mensch":"3","maschine":"13","besucher":2,"aufrufe":16,"dauer":"9","bytes":"2016630","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/kasse.php","mensch":"3","maschine":"12","besucher":2,"aufrufe":15,"dauer":"10","bytes":"1863893","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/datenschutz.php","mensch":"1","maschine":"14","besucher":1,"aufrufe":15,"dauer":"11","bytes":"2298978","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/aktuelles.php","mensch":"4","maschine":"10","besucher":4,"aufrufe":14,"dauer":"13","bytes":"1614246","zuletzt":"2026-08-15 09:35:01"},{"pfad":"/en/ueberuns.php","mensch":"4","maschine":"10","besucher":4,"aufrufe":14,"dauer":"8","bytes":"1662942","zuletzt":"2026-08-15 09:35:03"},{"pfad":"/ro/kuendigung.php","mensch":"3","maschine":"11","besucher":3,"aufrufe":14,"dauer":"8","bytes":"1816264","zuletzt":"2026-08-15 09:35:02"}],"seiten_verlauf":[{"pfad":"/impressum.php","datum":"2026-08-11","mensch":"5"},{"pfad":"/datenschutz.php","datum":"2026-08-11","mensch":"3"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-11","mensch":"3"},{"pfad":"/satzung.php","datum":"2026-08-11","mensch":"3"},{"pfad":"/kontakt.php","datum":"2026-08-11","mensch":"1"},{"pfad":"/impressum.php","datum":"2026-08-12","mensch":"42"},{"pfad":"/datenschutz.php","datum":"2026-08-12","mensch":"57"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-12","mensch":"56"},{"pfad":"/satzung.php","datum":"2026-08-12","mensch":"19"},{"pfad":"/kontakt.php","datum":"2026-08-12","mensch":"20"},{"pfad":"/datenschutz.php","datum":"2026-08-13","mensch":"3"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-13","mensch":"5"},{"pfad":"/satzung.php","datum":"2026-08-13","mensch":"6"},{"pfad":"/kontakt.php","datum":"2026-08-13","mensch":"3"},{"pfad":"/impressum.php","datum":"2026-08-13","mensch":"21"},{"pfad":"/datenschutz.php","datum":"2026-08-14","mensch":"11"},{"pfad":"/kontakt.php","datum":"2026-08-14","mensch":"16"},{"pfad":"/satzung.php","datum":"2026-08-14","mensch":"13"},{"pfad":"/impressum.php","datum":"2026-08-14","mensch":"11"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-14","mensch":"10"},{"pfad":"/datenschutz.php","datum":"2026-08-15","mensch":"2"},{"pfad":"/impressum.php","datum":"2026-08-15","mensch":"1"},{"pfad":"/kontakt.php","datum":"2026-08-15","mensch":"1"},{"pfad":"/satzung.php","datum":"2026-08-15","mensch":"4"},{"pfad":"/widerrufsrecht.php","datum":"2026-08-15","mensch":"1"}],"einstieg":[{"pfad":"/impressum.php","besuche":24},{"pfad":"/en","besuche":23},{"pfad":"/satzung.php","besuche":17},{"pfad":"/widerrufsrecht.php","besuche":15},{"pfad":"/ueberuns.php","besuche":14},{"pfad":"/kuendigung.php","besuche":11},{"pfad":"/barrierefreiheit.php","besuche":10},{"pfad":"/spenden.php","besuche":10},{"pfad":"/sitemap.php","besuche":9},{"pfad":"/kasse.php","besuche":9},{"pfad":"/anmeldung.php","besuche":9},{"pfad":"/aktuelles.php","besuche":8},{"pfad":"/transparenz.php","besuche":7},{"pfad":"/datenschutz.php","besuche":7},{"pfad":"/kontakt.php","besuche":6}],"sprach_seiten":[{"sprache":"de","seiten":35,"mensch":"765","maschine":"3674"},{"sprache":"en","seiten":19,"mensch":"74","maschine":"244"},{"sprache":"ro","seiten":19,"mensch":"64","maschine":"216"},{"sprache":"ru","seiten":20,"mensch":"10","maschine":"75"},{"sprache":"uk","seiten":21,"mensch":"4","maschine":"74"}],"status_verteilung":[{"status":200,"mensch":"728","maschine":"3465","scan":"0","gesamt":4193},{"status":303,"mensch":"171","maschine":"705","scan":"0","gesamt":876},{"status":404,"mensch":"5","maschine":"63","scan":"19","gesamt":87},{"status":301,"mensch":"7","maschine":"21","scan":"0","gesamt":28},{"status":400,"mensch":"0","maschine":"25","scan":"0","gesamt":25},{"status":500,"mensch":"6","maschine":"4","scan":"0","gesamt":10}],"verweise":[{"verweis":"ip53.ip-135-125-150.eu","aufrufe":15,"besucher":1},{"verweis":"135.125.150.53","aufrufe":1,"besucher":1}],"fehlseiten":[{"pfad":"/404.php","status":404,"treffer":31,"zuletzt":"2026-08-15 09:11:20"},{"pfad":"/","status":400,"treffer":25,"zuletzt":"2026-08-15 10:46:10"},{"pfad":"/header.php","status":404,"treffer":5,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/en","status":404,"treffer":5,"zuletzt":"2026-08-14 23:22:06"},{"pfad":"/footer.php","status":404,"treffer":4,"zuletzt":"2026-08-14 22:23:22"},{"pfad":"/en/404.php","status":404,"treffer":3,"zuletzt":"2026-08-15 00:14:12"},{"pfad":"/ro/404.php","status":404,"treffer":3,"zuletzt":"2026-08-15 00:14:12"},{"pfad":"/widerruf_formular.php","status":404,"treffer":2,"zuletzt":"2026-08-15 09:08:54"},{"pfad":"/anmeldung_ansicht.php","status":500,"treffer":2,"zuletzt":"2026-08-14 12:39:58"},{"pfad":"/uk/404.php","status":404,"treffer":2,"zuletzt":"2026-08-15 09:11:05"},{"pfad":"/anmeldung_stil.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/uk/footer.php","status":404,"treffer":1,"zuletzt":"2026-08-15 09:37:28"},{"pfad":"/formularschutz.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/ru/inhalt/ru/index.php","status":404,"treffer":1,"zuletzt":"2026-08-15 09:37:29"},{"pfad":"/uk/sprachen/uk.php","status":404,"treffer":1,"zuletzt":"2026-08-15 09:37:29"},{"pfad":"/widerruf.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/impressum.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/datenschutz.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/widerrufsrecht.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/kuendigung.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/anmeldung_fertig.php","status":500,"treffer":1,"zuletzt":"2026-08-14 12:39:41"},{"pfad":"/satzung.php","status":500,"treffer":1,"zuletzt":"2026-08-14 19:46:00"},{"pfad":"/anmeldung_zusammen.php","status":500,"treffer":1,"zuletzt":"2026-08-14 12:39:41"},{"pfad":"/anmeldung_ansicht.php","status":404,"treffer":1,"zuletzt":"2026-08-14 13:03:12"},{"pfad":"/sprachen.php","status":404,"treffer":1,"zuletzt":"2026-08-14 22:23:22"}],"langsam":[{"pfad":"/en","aufrufe":3,"mittel":"44","hoechst":122},{"pfad":"/uk","aufrufe":3,"mittel":"5","hoechst":7},{"pfad":"/","aufrufe":4,"mittel":"3","hoechst":4}],"bots":[{"bot_name":"curl","aufrufe":2514,"zuletzt":"2026-08-15 10:47:02"},{"bot_name":"Crawler","aufrufe":1527,"zuletzt":"2026-08-14 19:29:16"},{"bot_name":"Chrome (headless)","aufrufe":87,"zuletzt":"2026-08-15 09:36:49"},{"bot_name":"OpenAI GPTBot","aufrufe":69,"zuletzt":"2026-08-14 22:48:17"},{"bot_name":"ohne Kennung","aufrufe":64,"zuletzt":"2026-08-15 10:46:10"},{"bot_name":"Google","aufrufe":21,"zuletzt":"2026-08-15 10:42:06"},{"bot_name":"Bing","aufrufe":1,"zuletzt":"2026-08-13 12:31:07"}],"suchmaschinen":[{"bot_name":"Google","abrufe":21,"seiten":10,"zuletzt":"2026-08-15 10:42:06","erstmals":"2026-08-12 14:47:31","fehler":"0"},{"bot_name":"Bing","abrufe":1,"seiten":1,"zuletzt":"2026-08-13 12:31:07","erstmals":"2026-08-13 12:31:07","fehler":"0"}],"gecrawlt":[{"pfad":"/impressum.php","abrufe":4,"zuletzt":"2026-08-14 17:13:35"},{"pfad":"/datenschutz.php","abrufe":3,"zuletzt":"2026-08-14 17:51:04"},{"pfad":"/kontakt.php","abrufe":3,"zuletzt":"2026-08-14 19:43:37"},{"pfad":"/mitglied.php","abrufe":3,"zuletzt":"2026-08-14 18:28:34"},{"pfad":"/transparenz.php","abrufe":3,"zuletzt":"2026-08-14 23:28:34"},{"pfad":"/widerrufsrecht.php","abrufe":2,"zuletzt":"2026-08-13 15:15:52"},{"pfad":"/spenden.php","abrufe":1,"zuletzt":"2026-08-13 01:47:52"},{"pfad":"/sitemap.php","abrufe":1,"zuletzt":"2026-08-13 02:41:54"},{"pfad":"/satzung.php","abrufe":1,"zuletzt":"2026-08-14 20:58:35"},{"pfad":"/satzung360s","abrufe":1,"zuletzt":"2026-08-15 10:42:06"}],"unbesucht":[{"pfad":"/barrierefreiheit_grafik.php","gecrawlt":false},{"pfad":"/ru/404.php","gecrawlt":false}],"nicht_gecrawlt":[{"pfad":"/"},{"pfad":"/404.php"},{"pfad":"/aktuelles.php"},{"pfad":"/anmeldung.php"},{"pfad":"/anmeldung_ansicht.php"},{"pfad":"/anmeldung_entwurf.php"},{"pfad":"/anmeldung_fertig.php"},{"pfad":"/anmeldung_listen.php"},{"pfad":"/anmeldung_pruefen.php"},{"pfad":"/anmeldung_stil.php"},{"pfad":"/anmeldung_zusammen.php"},{"pfad":"/barrierefreiheit.php"},{"pfad":"/barrierefreiheit_grafik.php"},{"pfad":"/en"},{"pfad":"/en/404.php"},{"pfad":"/en/aktuelles.php"},{"pfad":"/en/barrierefreiheit.php"},{"pfad":"/en/datenschutz.php"},{"pfad":"/en/impressum.php"},{"pfad":"/en/kasse.php"},{"pfad":"/en/kontakt.php"},{"pfad":"/en/kontaktformular.php"},{"pfad":"/en/kuendigung.php"},{"pfad":"/en/mitglied.php"},{"pfad":"/en/satzung.php"},{"pfad":"/en/sitemap.php"},{"pfad":"/en/spenden.php"},{"pfad":"/en/transparenz.php"},{"pfad":"/en/ueberuns.php"},{"pfad":"/en/widerruf.php"},{"pfad":"/en/widerrufsrecht.php"},{"pfad":"/kasse.php"},{"pfad":"/kontaktformular.php"},{"pfad":"/kuendigung.php"},{"pfad":"/ro"},{"pfad":"/ro/404.php"},{"pfad":"/ro/aktuelles.php"},{"pfad":"/ro/barrierefreiheit.php"},{"pfad":"/ro/datenschutz.php"},{"pfad":"/ro/impressum.php"}],"seiten_gesamt":100}''';

const String _antwortAngriffe = r'''{"success":true,"tage":30,"muster":[{"pfad":"/en//2019/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//wordpress/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//blog/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:10"},{"pfad":"/en//cms/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/en//wp/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//media/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/en//wp1/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//news/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//wp2/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/en//shop/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//xmlrpc.php","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:10"},{"pfad":"/en//site/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:13"},{"pfad":"/wp-login.php","versuche":1,"quellen":1,"zuletzt":"2026-08-15 09:33:10"},{"pfad":"/en//sito/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:14"},{"pfad":"/en//test/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:12"},{"pfad":"/en//web/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//2018/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"},{"pfad":"/en//website/wp-includes/wlwmanifest.xml","versuche":1,"quellen":1,"zuletzt":"2026-08-15 10:07:11"}],"herkunft":[{"land":"NL","netz":"1337 Services GmbH","versuche":18,"zuletzt":"2026-08-15 10:07:14"},{"land":"DE","netz":"OVH SAS","versuche":1,"zuletzt":"2026-08-15 09:33:10"}],"laender":[{"land":"NL","versuche":18,"quellen":1},{"land":"DE","versuche":1,"quellen":1}],"werkzeuge":[{"werkzeug":"ohne Kennung","versuche":18,"pfade":18,"zuletzt":"2026-08-15 10:07:14"},{"werkzeug":"curl","versuche":1,"pfade":1,"zuletzt":"2026-08-15 09:33:10"}],"antworten":[{"status":404,"versuche":19}],"stunden":[{"stunde":9,"versuche":1},{"stunde":10,"versuche":18}],"letzte":[{"zeit":"2026-08-15 10:07:14","pfad":"/en//sito/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//media/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//wp2/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//site/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:13","pfad":"/en//cms/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//2019/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//shop/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//wp1/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:12","pfad":"/en//test/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//blog/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//web/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//wordpress/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//website/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//wp/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//news/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:11","pfad":"/en//2018/wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:10","pfad":"/en//wp-includes/wlwmanifest.xml","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 10:07:10","pfad":"/en//xmlrpc.php","status":404,"land":"NL","netz":"1337 Services GmbH","bot_name":""},{"zeit":"2026-08-15 09:33:10","pfad":"/wp-login.php","status":404,"land":"DE","netz":"OVH SAS","bot_name":"curl"}],"verlauf":[{"datum":"2026-08-11","scans":0},{"datum":"2026-08-12","scans":0},{"datum":"2026-08-13","scans":0},{"datum":"2026-08-14","scans":0},{"datum":"2026-08-15","scans":19}],"erfolge":[],"anteil":{"mensch":917,"maschine":4283,"scan":19},"fail2ban":"7 Wachen aktiv, 1 Adressen gesperrt","hinweis":"Abgewiesene Versuche sind der Normalfall — der Auftritt steht im offenen Netz. Wichtig ist die Liste „hat geantwortet\": dort darf nichts stehen, was nach einer Konfigurationsdatei aussieht."}''';
const String _antwortTiefe = r'''{"success":true,"bericht":{"geprueft":"2026-08-15 13:40:10","dauer_sekunden":108,"note":{"prozent":90,"stufe":"gut","fehler":0,"warnungen":9,"geprueft":46},"note_kopfzeilen":"A+","prozent_kopfzeilen":100,"bloecke":[{"schluessel":"kopfnote","titel":"Kopfzeilen-Note (A+ bis F)","note":"A+","prozent":100,"pruefungen":[{"schluessel":"note_gesamt","titel":"Kopfzeilen-Note","stand":"info","wert":"A+ (100 von 100)","soll":"Dieselben sechs Kopfzeilen, nach denen securityheaders.com benotet — aber selbst gerechnet. ⚠️ Deren Schnittstelle wurde im Januar 2026 zum April 2026 abgekündigt und liefert die Note nicht mehr; darauf zu bauen hieße, die Prüfung eines Tages still zu verlieren.","hinweis":"","quelle":"live"},{"schluessel":"note_strict_transport_security","titel":"Strict-Transport-Security","stand":"ok","wert":"max-age=31536000","soll":"Geht mit 25 von 25 Punkten in die Kopfzeilen-Note ein.","hinweis":"","quelle":"live"},{"schluessel":"note_content_security_policy","titel":"Content-Security-Policy","stand":"ok","wert":"gesetzt, Skript-Richtlinie ohne Lockerung","soll":"Geht mit 25 von 50 Punkten in die Kopfzeilen-Note ein.","hinweis":"","quelle":"live"},{"schluessel":"note_x_frame_options","titel":"X-Frame-Options","stand":"ok","wert":"DENY","soll":"Geht mit 20 von 70 Punkten in die Kopfzeilen-Note ein.","hinweis":"","quelle":"live"},{"schluessel":"note_x_content_type_options","titel":"X-Content-Type-Options","stand":"ok","wert":"nosniff","soll":"Geht mit 10 von 80 Punkten in die Kopfzeilen-Note ein.","hinweis":"","quelle":"live"},{"schluessel":"note_referrer_policy","titel":"Referrer-Policy","stand":"ok","wert":"no-referrer","soll":"Geht mit 10 von 90 Punkten in die Kopfzeilen-Note ein.","hinweis":"","quelle":"live"},{"schluessel":"note_permissions_policy","titel":"Permissions-Policy","stand":"ok","wert":"gesetzt","soll":"Geht mit 10 von 100 Punkten in die Kopfzeilen-Note ein.","hinweis":"","quelle":"live"}]},{"schluessel":"csp","titel":"Content-Security-Policy im Einzelnen","pruefungen":[{"schluessel":"csp_default","titel":"default-src 'none'","stand":"ok","wert":"gesetzt — alles muss einzeln erlaubt werden","soll":"Die strengste Grundstellung. Möglich, weil dieser Auftritt keine fremden Skripte, Schriften oder Bilder einbindet.","hinweis":"","quelle":"live"},{"schluessel":"csp_base_uri","titel":"base-uri","stand":"ok","wert":"'none'","soll":"Verhindert, dass ein eingeschleustes <base> alle relativen Verweise auf einen fremden Server umbiegt. ⚠️ Wird von default-src NICHT abgedeckt.","hinweis":"","quelle":"live"},{"schluessel":"csp_form_action","titel":"form-action","stand":"ok","wert":"'self'","soll":"Legt fest, wohin Formulare abgeschickt werden dürfen. ⚠️ Wird von default-src NICHT abgedeckt — ohne sie kann ein eingeschleustes Formular Eingaben nach außen tragen.","hinweis":"","quelle":"live"},{"schluessel":"csp_frame_ancestors","titel":"frame-ancestors","stand":"ok","wert":"'none'","soll":"Wer diese Seite in einen Rahmen setzen darf. ⚠️ Wird von default-src NICHT abgedeckt.","hinweis":"","quelle":"live"},{"schluessel":"csp_object","titel":"object-src","stand":"ok","wert":"über default-src 'none' abgedeckt","soll":"Sperrt <object> und <embed> — veraltete Einbindungswege, über die sich Code nachladen lässt.","hinweis":"","quelle":"live"},{"schluessel":"csp_locker","titel":"Keine gefährlichen Lockerungen","stand":"ok","wert":"nur style-src 'unsafe-inline' (unkritisch)","soll":"'unsafe-inline' und 'unsafe-eval' bei Skripten heben den Schutz gegen eingeschleusten Code praktisch auf. Bei style-src ist die Lockerung der Normalfall: ein <style> führt keinen Code aus.","hinweis":"","quelle":"live"}]},{"schluessel":"tls_tief","titel":"TLS-Tiefenprüfung (testssl.sh)","pruefungen":[{"schluessel":"testssl","titel":"testssl.sh","stand":"ok","wert":"2 Einzelprüfungen, 2 davon mit Befund","soll":"Prüft die bekannten TLS-Schwächen (Heartbleed, ROBOT, POODLE, LOGJAM, FREAK, DROWN, SWEET32, Lucky13, CRIME, Ticketbleed, Renegotiation …) sowie Protokolle und Verfahren.","hinweis":"","quelle":"server"},{"schluessel":"tls_engine_problem","titel":"engine_problem","stand":"info","wert":"No engine or GOST support via engine with your /bin/openssl","soll":"Bewusst so entschieden — die Begründung steht hier, damit sie bei jedem Lauf mitgelesen wird.","hinweis":"Betrifft das PRÜFPROGRAMM, nicht den Server: dem openssl dieser Maschine fehlt die GOST-Unterstützung. Sagt über den Auftritt nichts aus.","quelle":"server"},{"schluessel":"tls_BREACH","titel":"BREACH","stand":"info","wert":"potentially VULNERABLE, gzip HTTP compression detected  - only supplied '/' tested","soll":"Bewusst so entschieden — die Begründung steht hier, damit sie bei jedem Lauf mitgelesen wird.","hinweis":"Die Kompression ist am 14.08.2026 absichtlich eingeschaltet worden: die Seiten sind reiner Text und schrumpfen um rund 72 %, und das bei jedem Aufruf. BREACH braucht ein Geheimnis in der Antwort, das sich Stück für Stück erraten lässt — dieser Auftritt hat weder Anmeldung noch Sitzung noch Zeichen in der Seite. ⚠️ Sobald dort je etwas Angemeldetes erscheint, kehrt sich diese Abwägung um.","quelle":"server"}]},{"schluessel":"alle_seiten","titel":"Alle Seiten im Einzelnen","pruefungen":[{"schluessel":"seiten_abruf","titel":"Alle Seiten abgerufen","stand":"ok","wert":"109 Seiten erreichbar, davon 5 über eine Umleitung","soll":"Jede Seite des Auftritts muss erreichbar sein. Die stündliche Prüfung sieht nur die Startseite — hier wird der ganze Auftritt abgerufen.","hinweis":"","quelle":"live"},{"schluessel":"titel_eindeutig","titel":"Jede Seite hat einen eigenen Titel","stand":"warnung","wert":"1 Titel mehrfach vergeben: Contact – ICD360S e.V.","soll":"Zwei Seiten mit demselben <title> sehen im Suchergebnis gleich aus.","hinweis":"","quelle":"live"},{"schluessel":"beschreibung_eindeutig","titel":"Meta-Beschreibungen","stand":"ok","wert":"alle vorhanden und verschieden","soll":"Jede Seite braucht eine eigene Beschreibung — sie ist der Text unter dem Suchergebnis.","hinweis":"","quelle":"live"},{"schluessel":"canonical_alle","titel":"Canonical auf jeder Seite","stand":"ok","wert":"auf allen 109 Seiten","soll":"rel=\"canonical\" nennt die maßgebliche Adresse. Bei Sprachfassungen zeigt jede auf sich selbst.","hinweis":"","quelle":"live"},{"schluessel":"lang_alle","titel":"Sprachauszeichnung auf jeder Seite","stand":"ok","wert":"auf allen 109 Seiten","soll":"<html lang=\"…\"> — davon hängt ab, wie ein Vorleseprogramm die Seite ausspricht (WCAG 3.1.1).","hinweis":"","quelle":"live"},{"schluessel":"klartext_alle","titel":"Keine unverschlüsselten Einbindungen","stand":"ok","wert":"auf allen 109 Seiten","soll":"Eine einzige über http:// eingebundene Datei macht die Seite angreifbar.","hinweis":"","quelle":"live"},{"schluessel":"alt_alle","titel":"Bilder mit Textalternative","stand":"ok","wert":"auf allen 109 Seiten","soll":"WCAG 1.1.1 — bei einem Verein von Menschen mit Behinderung keine Formalie.","hinweis":"","quelle":"live"},{"schluessel":"groesse_alle","titel":"Größte Seite","stand":"ok","wert":"/ru/barrierefreiheit.php mit 205 kB (unkomprimiert, Schnitt 169 kB)","soll":"Was über die Leitung geht, zählt — und der Verein weist gerade nach, wie langsam seine Mobilverbindung ist.","hinweis":"","quelle":"live"}]},{"schluessel":"verweise","titel":"Interne Verweise","pruefungen":[{"schluessel":"verweise_tot","titel":"Kein toter Verweis","stand":"ok","wert":"0 Ziele geprüft, alle erreichbar","soll":"Jeder Verweis innerhalb des Auftritts muss irgendwohin führen. Ein toter Verweis kostet den Besucher den Faden und den Suchdienst das Vertrauen.","hinweis":"","quelle":"live"}]},{"schluessel":"sitemap_voll","titel":"Sitemap vollständig","pruefungen":[{"schluessel":"sitemap_voll","titel":"Alle Adressen aus der Sitemap","stand":"ok","wert":"109 Adressen, alle mit HTTP 200","soll":"Die stündliche Prüfung nimmt eine Stichprobe von fünf — hier wird jede einzelne abgerufen. Eine Sitemap voller toter Adressen wird vom Suchdienst insgesamt abgewertet.","hinweis":"","quelle":"live"}]},{"schluessel":"auslage","titel":"Auslageprobe","pruefungen":[{"schluessel":"auslage","titel":"Nichts versehentlich ausgelegt","stand":"ok","wert":"76 Pfade geprüft, keiner liefert 200","soll":"Sicherungskopien, Zugangsdateien und Werkzeugverzeichnisse dürfen von außen nicht abrufbar sein. Der Vorfall vom 25.07.2026 war genau das: eine config.php.bak.statuscheck mit Zugangsdaten im Klartext, aus der sich ein gültiges Anmeldezeichen für den Vorsitz bauen ließ.","hinweis":"","quelle":"live"}]},{"schluessel":"barrierefreiheit","titel":"Barrierefreiheit","pruefungen":[{"schluessel":"bf_h1","titel":"Genau eine Hauptüberschrift","stand":"ok","wert":"auf allen 104 Seiten","soll":"Jede Seite braucht genau ein <h1>. Ein Vorleseprogramm springt darüber in den Inhalt (WCAG 1.3.1, 2.4.6).","hinweis":"","quelle":"live"},{"schluessel":"bf_h1_mehrfach","titel":"Keine doppelte Hauptüberschrift","stand":"ok","wert":"auf allen 104 Seiten","soll":"Mehrere <h1> machen die Gliederung mehrdeutig.","hinweis":"","quelle":"live"},{"schluessel":"bf_h_sprung","titel":"Überschriftenstufen ohne Sprung","stand":"ok","wert":"auf allen 104 Seiten","soll":"Von h2 direkt auf h4 zu springen bricht die Gliederung, an der sich ein Vorleseprogramm durch die Seite hangelt (WCAG 1.3.1).","hinweis":"","quelle":"live"},{"schluessel":"bf_main","titel":"Hauptbereich ausgezeichnet","stand":"ok","wert":"auf allen 104 Seiten","soll":"<main> lässt ein Hilfsmittel direkt zum Inhalt springen (WCAG 1.3.1).","hinweis":"","quelle":"live"},{"schluessel":"bf_sprungmarke","titel":"Sprungmarke zum Inhalt","stand":"ok","wert":"auf allen 104 Seiten","soll":"Ein Verweis „zum Inhalt\" ganz am Anfang erspart Tastaturnutzern, sich durch das ganze Menü zu drücken (WCAG 2.4.1).","hinweis":"","quelle":"live"},{"schluessel":"bf_ids","titel":"Keine doppelten id-Werte","stand":"ok","wert":"auf allen 104 Seiten","soll":"Ein doppelter id-Wert bricht jede Verknüpfung von Beschriftung und Feld.","hinweis":"","quelle":"live"},{"schluessel":"bf_linktext","titel":"Aussagekräftige Verweistexte","stand":"ok","wert":"auf allen 104 Seiten","soll":"Ein Vorleseprogramm liest oft nur die Verweisliste vor. „Hier\" und „mehr\" sagen dort nichts (WCAG 2.4.4).","hinweis":"","quelle":"live"},{"schluessel":"bf_label","titel":"Formularfelder beschriftet","stand":"ok","wert":"auf allen 104 Seiten","soll":"Jedes Eingabefeld braucht ein <label for> oder ein aria-label — sonst weiß niemand, was einzutragen ist (WCAG 1.3.1, 3.3.2).","hinweis":"","quelle":"live"},{"schluessel":"bf_anzeigefeld","titel":"Nur-Anzeige-Felder mit Namen","stand":"warnung","wert":"6 Seiten betroffen: /en/kuendigung.php, /es/kuendigung.php, /kuendigung.php, /ro/kuendigung.php, /ru/kuendigung.php","soll":"Felder mit readonly oder disabled kann niemand ausfüllen — ein Vorleseprogramm nennt sie aber trotzdem, und ohne aria-label heißt das „Textfeld, 31.12.2026\". Kein Fehler, aber unschön.","hinweis":"","quelle":"live"},{"schluessel":"bf_iframe","titel":"Rahmen mit Titel","stand":"ok","wert":"auf allen 104 Seiten","soll":"<iframe> ohne title wird als „Rahmen\" vorgelesen (WCAG 4.1.2).","hinweis":"","quelle":"live"},{"schluessel":"bf_tabelle","titel":"Tabellen mit Kopfzellen","stand":"warnung","wert":"6 Seiten betroffen: /en/kasse.php, /es/kasse.php, /kasse.php, /ro/kasse.php, /ru/kasse.php","soll":"Ohne <th> ist eine Tabelle für ein Vorleseprogramm eine Zahlenwüste (WCAG 1.3.1).","hinweis":"","quelle":"live"},{"schluessel":"bf_grenze","titel":"Was hier NICHT geprüft wird","stand":"info","wert":"Kontrast, Fokusreihenfolge, Verständlichkeit, Vorlesbarkeit in der Praxis","soll":"Automatisch entscheidbar ist nur der Teil, der im HTML steht. Nach allen Erhebungen findet ein Prüfprogramm rund ein Drittel der Barrieren.","hinweis":"⚠️ „Alles grün\" heißt hier NICHT „barrierefrei\". Es heißt: die Fehler, die eine Maschine finden kann, sind nicht darunter. Der Rest braucht Menschen — in diesem Verein sind sie zum Glück im Vorstand.","quelle":"live"}]},{"schluessel":"struktur","titel":"Strukturierte Daten & Vorschau","pruefungen":[{"schluessel":"jsonld","titel":"Strukturierte Daten","stand":"warnung","wert":"kein JSON-LD auf der Startseite","soll":"Ein JSON-LD-Block mit @type \"NGO\" (oder \"Organization\") und darin name, url, logo, address, email und sameAs. Er sagt Suchdiensten und Sprachmodellen, WER hinter dem Auftritt steht — bei einem Verein die Grundlage dafür, überhaupt als Einrichtung erkannt zu werden.","hinweis":"","quelle":"live"},{"schluessel":"og","titel":"Vorschau beim Teilen","stand":"info","wert":"es fehlt: og:image (vorhanden: 8)","soll":"og:title, og:description, og:image, og:url und og:type. Ohne sie zeigt jede geteilte Nachricht — WhatsApp, Signal, Mastodon — nur die nackte Adresse statt einer Vorschau mit Bild.","hinweis":"","quelle":"live"}]},{"schluessel":"rechtschreibung","titel":"Rechtschreibung","pruefungen":[{"schluessel":"rechtschreibung_de","titel":"Rechtschreibung — Deutsch","stand":"warnung","wert":"31 auffällige Wörter auf 19 Seiten: BITV-Test (4×), geld (3×), icd (2×), antrag (2×), MStV (2×), Kategoriesumme (2×), seite (2×), AusweisZweiter, vorhandenNachnameGeburtsname, abweichtGeburtsdatum, TT.MM.JJJJGeburtsortGeschlechtBitte, lebendgeschiedenverwitwet, BIK, BITV-Tests","soll":"Geprüft mit dem eigenen LanguageTool — kein Text verlässt den Server.","hinweis":"⚠️ Hinweise, keine Fehler: Eigennamen und Fachbegriffe kennt kein Wörterbuch. Was richtig ist, gehört in WT_LT_BEKANNT.","quelle":"server"},{"schluessel":"rechtschreibung_en","titel":"Rechtschreibung — Englisch","stand":"warnung","wert":"76 auffällige Wörter auf 17 Seiten: Feld (4×), bitte (4×), frei (4×), lassen (4×), Transparente (3×), Zivilgesellschaft (3×), Finanzamt (3×), yyyy (3×), icd (2×), antrag (2×), MStV (2×), Mitgliedschaft (2×), Abgabenordnung (2×), Jobcenter (2×)","soll":"Geprüft mit dem eigenen LanguageTool — kein Text verlässt den Server.","hinweis":"⚠️ Stehen hier gewöhnliche deutsche Wörter, ist das KEIN Tippfehler, sondern unübersetzter Text auf einer fremdsprachigen Seite. Genau dafür ist diese Aufteilung da.","quelle":"server"},{"schluessel":"rechtschreibung_es","titel":"Rechtschreibung — Spanisch","stand":"warnung","wert":"91 auffällige Wörter auf 17 Seiten: Neu (16×), Straße (9×), Memmingen (6×), Dieses (4×), Feld (4×), bitte (4×), frei (4×), lassen (4×), Zivilgesellschaft (3×), Finanzamt (3×), Initiative (2×), arts (2×), MStV (2×), Mitgliedschaft (2×)","soll":"Geprüft mit dem eigenen LanguageTool — kein Text verlässt den Server.","hinweis":"⚠️ Stehen hier gewöhnliche deutsche Wörter, ist das KEIN Tippfehler, sondern unübersetzter Text auf einer fremdsprachigen Seite. Genau dafür ist diese Aufteilung da.","quelle":"server"},{"schluessel":"rechtschreibung_ru","titel":"Rechtschreibung — Russisch","stand":"warnung","wert":"28 auffällige Wörter auf 17 Seiten: самопредставительство (3×), Нойульм (2×), предл (2×), личностиВторое, естьФамилияФамилия, отличаетсяДата, ГГГГМесто, рожденияПолВыберите, мужскойженскийинойСемейное, положениеВыберите, замужемв, бракепроживает, раздельноразведён, разведенавдовец","soll":"Geprüft mit dem eigenen LanguageTool — kein Text verlässt den Server.","hinweis":"⚠️ Stehen hier gewöhnliche deutsche Wörter, ist das KEIN Tippfehler, sondern unübersetzter Text auf einer fremdsprachigen Seite. Genau dafür ist diese Aufteilung da.","quelle":"server"},{"schluessel":"rechtschreibung_uk","titel":"Rechtschreibung — Ukrainisch","stand":"warnung","wert":"19 auffällige Wörter auf 17 Seiten: незастосовно (4×), РРРР (3×), Нойульм (2×), реч (2×), особиДруге, єПрізвищеПрізвище, відрізняєтьсяДата, РРРРМісце, народженняСтатьВиберіть, чоловічажіночаіншаСімейний, станВиберіть, незаміжняу, шлюбіпроживає, окреморозлучений(а)удівець","soll":"Geprüft mit dem eigenen LanguageTool — kein Text verlässt den Server.","hinweis":"⚠️ Stehen hier gewöhnliche deutsche Wörter, ist das KEIN Tippfehler, sondern unübersetzter Text auf einer fremdsprachigen Seite. Genau dafür ist diese Aufteilung da.","quelle":"server"},{"schluessel":"rechtschreibung_luecke","titel":"Ungeprüfte Sprachfassungen","stand":"info","wert":"Rumänisch (18 Seiten)","soll":"LanguageTool beherrscht diese Sprache nicht (60 Varianten geprüft).","hinweis":"Ausdrücklich gemeldet statt still übersprungen — sonst stünde „keine Fehler\" für eine Sprache, die niemand angesehen hat.","quelle":"server"}]},{"schluessel":"extern","titel":"Verweise nach draußen","pruefungen":[{"schluessel":"extern_tot","titel":"Fremde Ziele erreichbar","stand":"ok","wert":"0 Ziele geprüft, keines tot","soll":"Ein Verweis auf ein Gesetz oder eine Behörde, der ins Leere führt, macht die ganze Seite unglaubwürdig — und niemand meldet es.","hinweis":"","quelle":"server"}]},{"schluessel":"beobachtung","titel":"Beobachtung","pruefungen":[{"schluessel":"ct","titel":"Certificate Transparency","stand":"ok","wert":"25 bekannte Zertifikate, keines neu","soll":"Jedes öffentlich vertrauenswürdige Zertifikat für unseren Namen landet binnen Sekunden in den CT-Protokollen. CAA sagt den Stellen, wer ausstellen darf — CT zeigt, wer es getan hat.","hinweis":"","quelle":"server"},{"schluessel":"dns_diff","titel":"DNS unverändert","stand":"ok","wert":"18 Einträge, keine Änderung seit dem letzten Lauf","soll":"Ein umgebogener A-Eintrag oder ein zusätzlicher MX ist die stillste Art, einen Auftritt zu übernehmen.","hinweis":"","quelle":"server"},{"schluessel":"sperrliste","titel":"Sperrlisten","stand":"ok","wert":"3 Adressen auf 3 Listen geprüft, keine Eintragung (Selbsttest bestanden)","soll":"Steht die Mail-Adresse auf einer Sperrliste, nimmt kein großer Anbieter mehr Post an — und im eigenen Protokoll steht davon nichts.","hinweis":"","quelle":"server"},{"schluessel":"dbl","titel":"Domain-Sperrliste","stand":"ok","wert":"icd360s.de nicht gelistet","soll":"Die DBL erfasst Domainnamen, die in Spam auftauchen — auch, wenn der Server sauber ist und nur der Name missbraucht wird.","hinweis":"","quelle":"server"}]}]},"geprueft":"2026-08-15 13:40:10"}''';

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

    test('tiefe — der taegliche Befund', () {
      final a = lies(_antwortTiefe);
      final b = webKarte(a['bericht']);
      expect(b, isNotEmpty);
      // Die Kopfzeilen-Note ist eine ZEICHENKETTE (A+ … F), keine Zahl —
      // ein webZahl() darauf ergaebe still 0.
      expect(b['note_kopfzeilen'], isA<String>());
      expect(webZahl(b['prozent_kopfzeilen']), inInclusiveRange(0, 100));
      final bloecke = webListe(b['bloecke']);
      expect(bloecke.length, greaterThanOrEqualTo(12));
      // Der Beobachtungsblock MUSS dabei sein — er ist der einzige, der
      // meldet, was sich hinter unserem Ruecken aendert (fremdes Zertifikat,
      // umgebogener DNS-Eintrag, Eintrag auf einer Sperrliste).
      for (final erwartet in ['beobachtung', 'barrierefreiheit', 'struktur',
                              'rechtschreibung', 'extern', 'tls_tief']) {
        expect(bloecke.map((b) => '${b['schluessel']}'), contains(erwartet));
      }
      for (final bl in bloecke) {
        expect(webListe(bl['pruefungen']), isNotEmpty);
        for (final pr in webListe(bl['pruefungen'])) {
          // Jede Pruefung muss eine bekannte Stufe tragen, sonst faellt sie im
          // Bildschirm auf den neutralen Zweig und niemand sieht den Mangel.
          expect(['ok', 'warnung', 'fehler', 'info'], contains('${pr['stand']}'));
        }
      }
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

  group('Die neuen Reihen der Uebersicht', () {
    late Map<String, dynamic> u;
    setUp(() => u = jsonDecode(_antwortUebersicht) as Map<String, dynamic>);

    test('ziele, trichter und verweise sind LISTEN, keine Objekte', () {
      // ⚠️ PHP hat nur einen Array-Typ. Ob am Ende eine JSON-Liste oder ein
      // JSON-Objekt steht, entscheidet sich erst an den Schluesseln — und
      // `as Map?` auf einer Liste gibt nicht null zurueck, sondern wirft.
      // Genau daran ist dieser Bildschirm schon einmal grau geblieben.
      for (final k in ['ziele', 'trichter', 'verweise']) {
        expect(u[k], isA<List<dynamic>>(), reason: '$k muss eine Liste sein');
        expect(webListe(u[k]), isNotEmpty, reason: '$k darf nicht leer sein');
      }
    });

    test('jedes Ziel traegt Name, Pfad, Aufrufe und Anteil', () {
      for (final z in webListe(u['ziele'])) {
        expect('${z['name']}', isNotEmpty);
        expect('${z['pfad']}', startsWith('/'));
        expect(webZahl(z['aufrufe']), greaterThanOrEqualTo(0));
        // ⚠️ Der Anteil ist eine Zahl, kein Text. PHPs round() liefert bei
        // glatten Werten einen int und sonst ein float — beides kommt hier an,
        // deshalb wird auf num geprueft und nicht auf double.
        expect(z['anteil'], isA<num>());
        expect(z['anteil'] as num, inInclusiveRange(0, 100));
      }
    });

    test('der Trichter hat sechs Stufen in der richtigen Reihenfolge', () {
      final t = webListe(u['trichter']);
      expect(t, hasLength(6));
      for (var i = 0; i < t.length; i++) {
        expect(webZahl(t[i]['stufe']), i + 1);
      }
    });

    test('kein Verweis heisst zweimal dasselbe', () {
      // ⚠️ Regressionsschutz: der Alias hiess einmal `quelle` und kollidierte
      // mit der gleichnamigen Spalte in web_zugriffe. MariaDB gruppierte dann
      // nach der Herkunft der Protokollzeile, und „(direkt)" stand zweimal in
      // der Liste. Das SQL sah dabei vollkommen richtig aus.
      final namen = webListe(u['verweise']).map((v) => '${v['woher']}').toList();
      expect(namen.toSet(), hasLength(namen.length));
    });

    test('die Antwortzeit nennt p50, p95 und die Zahl der Messungen', () {
      final a = webKarte(u['antwortzeit']);
      expect(a.containsKey('p50'), isTrue);
      expect(a.containsKey('p95'), isTrue);
      expect(webZahl(a['p95']), greaterThanOrEqualTo(webZahl(a['p50'])));
      // ⚠️ Weniger Messungen als Aufrufe ist der Normalfall, nicht der Fehler:
      // die rekonstruierten Tage tragen ueberhaupt keine Dauer.
      expect(webZahl(a['gemessen']), lessThanOrEqualTo(webZahl(a['n'])));
    });

    test('der Vergleich deckt alle Kennzahlen ab', () {
      final v = webKarte(u['vergleich']);
      for (final k in ['aufrufe_vorher', 'besucher_vorher', 'bot_vorher',
                       'scans_vorher', 'bytes_vorher']) {
        expect(v.containsKey(k), isTrue, reason: '$k fehlt im Vergleich');
      }
    });
  });

  group('Besuche, Ausstieg und Verweildauer', () {
    late Map<String, dynamic> u;
    setUp(() => u = jsonDecode(_antwortUebersicht) as Map<String, dynamic>);

    test('die Tiefe traegt alle fuenf Zahlen', () {
      final t = webKarte(u['tiefe']);
      for (final k in ['besuche', 'aufrufe', 'nur_eine', 'tiefster', 'je_besuch']) {
        expect(t.containsKey(k), isTrue, reason: '$k fehlt');
      }
      // Wer nur eine Seite sah, ist eine Teilmenge aller Besuche.
      expect(webZahl(t['nur_eine']), lessThanOrEqualTo(webZahl(t['besuche'])));
      expect(webZahl(t['tiefster']), greaterThanOrEqualTo(1));
    });

    test('ausstieg ist eine Liste mit Pfad und Besuchen', () {
      expect(u['ausstieg'], isA<List<dynamic>>());
      for (final a in webListe(u['ausstieg'])) {
        expect('${a['pfad']}', isNotEmpty);
        expect(webZahl(a['besuche']), greaterThan(0));
      }
    });

    test('die Verweildauer nennt, worueber sie rechnet', () {
      final d = webKarte(u['dauer']);
      expect(d.containsKey('median_s'), isTrue);
      // ⚠️ Ein-Seiten-Besuche sind ausgenommen — aus dem Protokoll gibt es
      // fuer sie nur EINEN Zeitstempel. Die Grundlage muss deshalb kleiner
      // sein als die Zahl aller Besuche, sonst rechnet jemand Nullen mit.
      expect(webZahl(d['besuche']),
          lessThanOrEqualTo(webZahl(webKarte(u['tiefe'])['besuche'])));
    });
  });

  group('Die neuen Auswertungen im Reiter Besucher', () {
    late Map<String, dynamic> b;
    setUp(() => b = jsonDecode(_antwortBesucher) as Map<String, dynamic>);

    test('wege, die beiden Verteilungen und die juengsten Zugriffe sind Listen', () {
      for (final k in ['wege', 'tiefe_klassen', 'dauer_klassen', 'letzte']) {
        expect(b[k], isA<List<dynamic>>(), reason: '$k muss eine Liste sein');
      }
    });

    test('ein Weg fuehrt von einer Seite auf eine ANDERE', () {
      // ⚠️ Das Neuladen derselben Seite ist kein Weg. Faellt der Filter im SQL
      // weg, steht hier auf einmal „/impressum -> /impressum" ganz oben.
      for (final w in webListe(b['wege'])) {
        expect('${w['vorher']}', isNotEmpty);
        expect('${w['pfad']}', isNot(equals('${w['vorher']}')));
        expect(webZahl(w['n']), greaterThan(0));
      }
    });

    test('die Klassen kommen in ihrer eigenen Ordnung, nicht alphabetisch', () {
      // ⚠️ Nach der Beschriftung sortiert stuende „10-19" vor „2 Seiten".
      // Dafuer traegt jede Zeile ein eigenes Sortierfeld.
      for (final schluessel in ['tiefe_klassen', 'dauer_klassen']) {
        final s = webListe(b[schluessel]).map((k) => webZahl(k['sortier'])).toList();
        expect(s, equals(List.of(s)..sort()), reason: '$schluessel steht falsch');
        expect(s.toSet(), hasLength(s.length), reason: '$schluessel doppelt');
      }
    });

    test('die juengsten Zugriffe tragen KEINEN Besucherschluessel', () {
      // ⚠️ Mit ihm liessen sich die Zeilen zu Sitzungen zusammensetzen — genau
      // das soll dieser Aufbau nicht hergeben. Der Schutz gehoert in den Test,
      // sonst kommt das Feld beim naechsten Ausbau still zurueck.
      for (final z in webListe(b['letzte'])) {
        expect(z.containsKey('besucher'), isFalse);
        expect(z.containsKey('netz'), isFalse);
        expect('${z['zeit']}', isNotEmpty);
        expect('${z['pfad']}', isNotEmpty);
      }
    });

    test('das kurze Fenster liefert dieselbe Form', () {
      final k = jsonDecode(_antwortBesucher1h) as Map<String, dynamic>;
      expect(webZahl(k['fenster_stunden']), 1);
      for (final s in ['wege', 'tiefe_klassen', 'dauer_klassen', 'letzte']) {
        expect(k[s], isA<List<dynamic>>(), reason: '$s fehlt im kurzen Fenster');
      }
    });
  });

  group('Fehlseiten und Maschinen nach Absicht', () {
    late Map<String, dynamic> b;
    setUp(() => b = jsonDecode(_antwortBesucher) as Map<String, dynamic>);

    test('beides sind Listen', () {
      // ⚠️ maschinen_absicht waere als Karte mit den Gruppennamen als
      // Schluessel ein JSON-Objekt geworden — und `as List` darauf wirft.
      expect(b['fehlseiten'], isA<List<dynamic>>());
      expect(b['maschinen_absicht'], isA<List<dynamic>>());
    });

    test('jede Fehlseite nennt Pfad, Summe und den Anteil der Menschen', () {
      for (final f in webListe(b['fehlseiten'])) {
        expect('${f['pfad']}', startsWith('/'));
        expect(webZahl(f['aufrufe']), greaterThan(0));
        // Menschliche 404 sind eine Teilmenge aller 404 derselben Adresse.
        expect(webZahl(f['mensch']), lessThanOrEqualTo(webZahl(f['aufrufe'])));
      }
    });

    test('Fehlseiten, die Menschen trafen, stehen vorn', () {
      // ⚠️ Genau darum geht es: auf hundert Klopfversuche kommt eine Adresse,
      // die ein Mensch angeklickt hat. Sortiert nach Gesamtzahl ginge sie
      // unter.
      final mensch = webListe(b['fehlseiten']).map((f) => webZahl(f['mensch']));
      expect(mensch.toList(), equals(List.of(mensch)..sort((x, y) => y.compareTo(x))));
    });

    test('die Gruppen sind bekannt und doppeln sich nicht', () {
      final gruppen =
          webListe(b['maschinen_absicht']).map((g) => '${g['gruppe']}').toList();
      expect(gruppen.toSet(), hasLength(gruppen.length));
      for (final g in gruppen) {
        expect(['suchmaschine', 'ki', 'messung', 'werkzeug'], contains(g));
      }
    });

    test('die Summe einer Gruppe passt zu ihren Namen', () {
      for (final g in webListe(b['maschinen_absicht'])) {
        final teile = webListe(g['namen'])
            .map((n) => webZahl(n['aufrufe']))
            .fold(0, (a, x) => a + x);
        // ⚠️ Die Namensliste ist auf acht gekuerzt, die Summe ist es nicht.
        // Kleiner-gleich ist richtig, Gleichheit waere zu streng.
        expect(teile, lessThanOrEqualTo(webZahl(g['aufrufe'])));
      }
    });
  });
}
