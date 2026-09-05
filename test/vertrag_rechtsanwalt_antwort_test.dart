import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/ra_antwort.dart';

/// Test gegen die **echten**, ungekürzten Antworten von
/// `api/admin/vertrag_rechtsanwalt_manage.php`.
///
/// ⚠️ Warum echte Antworten und keine nachgebauten: die Form der Antwort ist
/// ein Nebeneffekt von `jsonResponse()` (`array_merge` in die Wurzel) und
/// davon, ob PHP ein Array als Liste oder als Objekt kodiert. Beides kann
/// man sich falsch merken, und ein Test gegen eine ausgedachte Antwort
/// prüft dann nur, ob man konsequent falsch liegt.
///
/// Genau das ist am 05.08.2026 im Speedtest-Bildschirm passiert: eine
/// PHP-Liste wurde als Map gelesen, `as Map?` gab **nicht** `null` zurück
/// sondern warf, und im Release-Build blieb eine graue Fläche ohne jede
/// Meldung übrig — an der weder `flutter analyze` noch 514 Tests etwas
/// auszusetzen hatten, weil keiner davon die echte Serverantwort anfasste.
///
/// Abgenommen am 14.08.2026 mit `_server_rechtsanwalt/ra_antwort_dump.php`.
/// Wird der Endpunkt geändert, wird dieses Skript erneut ausgeführt und die
/// Zeichenketten hier ersetzt — nicht von Hand angepasst.
void main() {
  // ── Echte Antworten, Wort für Wort vom Server ────────────────────────

  const listAktenzeichen = r'''
{"success":true,"items":[{"id":5,"status":"mahnverfahren","eroeffnet_am":"2026-07-05","geschlossen_am":null,"naechste_frist":null,"aktenzeichen":"DUMP 42\/26","bezeichnung":"Probeakte","gegenseite":"Musterstrom AG","gegner_anwalt":null,"gegner_aktenzeichen":null,"gericht":null,"gericht_aktenzeichen":null,"streitwert":"1234,56","notizen":null,"created_at":"2026-08-14 13:38:18","mahn_stufe":"vb_zugestellt","hat_mahnverfahren":true,"fristen_offen":2,"vollmacht_aktiv":false}]}
''';

  const getMandat = r'''
{"success":true,"exists":true,"data":{"id":5,"rechtsanwalt_id":5,"status":"mandat_erteilt","mandat_seit":"2026-07-01","mandat_bis":null,"ansprechpartner":"Frau Muster","telefon_durchwahl":null,"email_ansprechpartner":null,"ra_aktenzeichen":"142\/26 MU","gegenstand":null,"rechtsschutz":null,"rsv_name":null,"rsv_schadennummer":null,"notizen":null,"kanzlei":{"firmenname":"DUMP Kanzlei Muster PartG mbB","anwalt_name":"Dr. Erika Muster","strasse":"Musterstrasse 12","plz_ort":"89073 Ulm","telefon":"+49 731 0000000","fax":null,"email":"kanzlei@example.invalid","website":null,"rechtsanwaltskammer":"RAK Tuebingen","bea_safe_id":"DE.DUMP.0001","fachgebiete":"Fachanwaeltin fuer Zivilrecht"}}}
''';

  const getMahnverfahren = r'''
{"success":true,"exists":true,"data":{"id":6,"rolle":"antragsgegner","stufe":"vb_zugestellt","mb_beantragt_am":null,"mb_erlassen_am":null,"mb_zugestellt_am":"2026-06-01","widerspruch_am":null,"widerspruch_umfang":"kein","vb_beantragt_am":null,"vb_erlassen_am":"2026-07-20","vb_zugestellt_am":"2026-08-03","einspruch_am":null,"abgabe_am":null,"vollstreckung_am":null,"zustellung_ausland":0,"erledigt":0,"mahngericht":"Amtsgericht Stuttgart","gz_mahngericht":null,"antragsteller":null,"antragsteller_vertreter":null,"hauptforderung":"987,65","zinsen":null,"kosten":null,"widerspruch_begruendung":null,"notizen":null},"stufen":{"kein":{"label":"Kein Mahnverfahren","norm":""},"mb_beantragt":{"label":"Mahnbescheid beantragt","norm":"§ 690 ZPO"},"mb_zugestellt":{"label":"Mahnbescheid zugestellt","norm":"§ 693 ZPO"},"widerspruch":{"label":"Widerspruch eingelegt","norm":"§ 694 ZPO"},"vb_beantragt":{"label":"Vollstreckungsbescheid beantragt","norm":"§ 699 ZPO"},"vb_zugestellt":{"label":"Vollstreckungsbescheid zugestellt","norm":"§ 700 ZPO"},"einspruch":{"label":"Einspruch eingelegt","norm":"§ 700 i.V.m. § 338 ZPO"},"streitverfahren":{"label":"Abgabe an das Streitgericht","norm":"§ 696 ZPO"},"vollstreckung":{"label":"Zwangsvollstreckung","norm":"§ 794 Abs. 1 Nr. 4 ZPO"},"erledigt":{"label":"Erledigt","norm":""}},"fristen":[{"schluessel":"einspruch","titel":"Einspruch gegen den Vollstreckungsbescheid","norm":"§ 700 Abs. 1 ZPO i.V.m. § 339 Abs. 1 ZPO","ab":"2026-08-03","ab_label":"Zustellung des Vollstreckungsbescheids","datum":"2026-08-17","notfrist":true,"erledigt":false,"hinweis":"Notfrist. Sie kann nicht verlaengert werden (§ 224 Abs. 2 ZPO).","tage":3,"dringlichkeit":"bald"},{"schluessel":"mb_wirkung","titel":"Wirkung des Mahnbescheids entfaellt","norm":"§ 701 ZPO","ab":"2026-06-01","ab_label":"Zustellung des Mahnbescheids","datum":"2026-12-01","notfrist":false,"erledigt":false,"hinweis":"Wird bis dahin kein Vollstreckungsbescheid beantragt, verliert der Mahnbescheid seine Wirkung — auch die Hemmung der Verjaehrung endet dann (§ 204 Abs. 2 BGB). Das ist eine Frist zugunsten des Mitglieds.","tage":109,"dringlichkeit":"offen"},{"schluessel":"widerspruch","titel":"Widerspruch gegen den Mahnbescheid","norm":"§ 692 Abs. 1 Nr. 3 ZPO","ab":"2026-06-01","ab_label":"Zustellung des Mahnbescheids","datum":"2026-06-15","notfrist":false,"erledigt":false,"hinweis":"Der Vollstreckungsbescheid ist bereits erlassen — ein Widerspruch ist nach § 694 Abs. 1 ZPO nicht mehr moeglich. Was bleibt, ist der Einspruch.","tage":-60,"dringlichkeit":"abgelaufen"}],"vorbehalt":"Berechnet nach §§ 187 Abs. 1, 188 BGB i.V.m. § 222 ZPO; ein Fristende an einem Samstag, Sonntag oder gesetzlichen Feiertag ist auf den naechsten Werktag geschoben (§ 222 Abs. 2 ZPO). Beruecksichtigt sind die bundeseinheitlichen Feiertage — landesrechtliche Feiertage am Sitz des Gerichts koennen das Ende weiter nach hinten schieben. Massgeblich bleiben Zustellungsurkunde und Kanzlei; diese Uebersicht ist eine Erinnerungshilfe, keine Fristenberechnung im Rechtssinne."}
''';

  const postDienstleister = r'''
{"success":true,"items":[{"id":1,"name":"Deutsche Post","art":"brief","reichweite":"bundesweit","hinweis":"Einschreiben werden verfolgt, ein einfacher Brief nicht.","verfolgbar":1},{"id":2,"name":"PIN Mail AG","art":"brief","reichweite":"Berlin und Brandenburg, \u00fcber Verbund dar\u00fcber hinaus","hinweis":"Keine Sendungsverfolgung mit Nummer im Netz.","verfolgbar":0},{"id":3,"name":"Postcon Deutschland","art":"brief","reichweite":"bundesweit \u00fcber Zustellpartner","hinweis":"Gesch\u00e4ftspost; keine offene Sendungsverfolgung.","verfolgbar":0},{"id":4,"name":"Citipost","art":"brief","reichweite":"Niedersachsen und ostdeutsche L\u00e4nder (PIN Group)","hinweis":"Regionaler Briefdienst, keine offene Sendungsverfolgung.","verfolgbar":0},{"id":5,"name":"mail alliance","art":"brief","reichweite":"Verbund regionaler Briefdienste, bundesweit","hinweis":"Verbund, nicht ein einzelnes Unternehmen.","verfolgbar":0},{"id":6,"name":"DHL Paket","art":"paket","reichweite":"bundesweit","hinweis":null,"verfolgbar":1},{"id":7,"name":"DPD","art":"paket","reichweite":"bundesweit","hinweis":null,"verfolgbar":1},{"id":8,"name":"GLS","art":"paket","reichweite":"bundesweit","hinweis":null,"verfolgbar":1},{"id":9,"name":"Hermes","art":"paket","reichweite":"bundesweit","hinweis":null,"verfolgbar":1},{"id":10,"name":"UPS","art":"paket","reichweite":"bundesweit","hinweis":null,"verfolgbar":1},{"id":11,"name":"FedEx","art":"paket","reichweite":"bundesweit","hinweis":"TNT geh\u00f6rt seit 2016 zu FedEx.","verfolgbar":1},{"id":12,"name":"GO! Express & Logistics","art":"kurier","reichweite":"bundesweit","hinweis":"Kurier mit Zustellprotokoll.","verfolgbar":0},{"id":13,"name":"Anderer Kurierdienst","art":"kurier","reichweite":null,"hinweis":"Name im Feld Notiz festhalten.","verfolgbar":0},{"id":14,"name":"Anderer Dienstleister","art":"sonstige","reichweite":null,"hinweis":"Name im Feld Notiz festhalten.","verfolgbar":0}],"versandarten":[{"schluessel":"einschreiben_rueckschein","titel":"Einschreiben mit R\u00fcckschein","beweis":"stark","hinweis":"Unterschrift und Datum des Empf\u00e4ngers kommen zur\u00fcck. Der h\u00f6chste Beweiswert, den die Post bietet."},{"schluessel":"uebergabe_einschreiben","titel":"\u00dcbergabe-Einschreiben","beweis":"stark","hinweis":"Wird pers\u00f6nlich \u00fcbergeben und quittiert."},{"schluessel":"kurier","titel":"Kurier \/ Bote mit Zustellprotokoll","beweis":"stark","hinweis":"Nach dem BAG-Urteil vom 07.05.2026 der empfohlene Weg, wenn es auf den Zugang ankommt."},{"schluessel":"persoenlich","titel":"Pers\u00f6nlich \u00fcbergeben","beweis":"stark","hinweis":"Nur mit Empfangsbekenntnis oder Eingangsstempel auf der Kopie."},{"schluessel":"bea_egvp","titel":"beA \/ EGVP \/ Mein Justizpostfach","beweis":"stark","hinweis":"Automatische Eingangsbest\u00e4tigung des Gerichts (\u00a7 130a Abs. 5 ZPO)."},{"schluessel":"einwurf_einschreiben","titel":"Einwurf-Einschreiben","beweis":"schwach","hinweis":"\u26a0\ufe0f BAG 07.05.2026 \u2013 2 AZR 184\/25: im Scan-Verfahren KEIN Anscheinsbeweis f\u00fcr den Zugang. Der Zusteller best\u00e4tigt, bevor er einwirft. Nicht als alleiniger Nachweis verwenden."},{"schluessel":"fax","titel":"Telefax","beweis":"mittel","hinweis":"Der Sendebericht belegt die \u00dcbertragung. \u26a0\ufe0f Formgebundene Antr\u00e4ge nehmen die Mahngerichte NICHT per Fax an."},{"schluessel":"paket","titel":"Paketdienst mit Sendungsverfolgung","beweis":"mittel","hinweis":"Belegt Zustellung an die Adresse, nicht den Inhalt."},{"schluessel":"standardbrief","titel":"Einfacher Brief","beweis":"kein","hinweis":"Kein Nachweis von Absendung noch Zugang. Nur festhalten, was war."}],"hinweis":"Die Sendungsnummer belegt den Weg der Sendung, nie ihren Inhalt. Wer beweisen muss, WAS im Umschlag lag, legt eine Kopie des Schriftsatzes dazu."}
''';

  const mahngerichteAlle = r'''
{"success":true,"items":[{"id":21,"name":"Amtsgericht Stuttgart \u2014 Zentrales Mahngericht","adresse":"Postanschrift: 70154 Stuttgart\nHausanschrift: Hauffstra\u00dfe 5, 70190 Stuttgart","telefon":"0711 921-3567","fax":"0711 921-3400","email":"Poststelle@mahngstuttgart.justiz.bwl.de","oeffnungszeiten":"Mahnabteilung: vor\u00fcbergehend eingeschr\u00e4nkt seit 29.06.2026 \u2014 Mo, Mi, Fr 09:00\u201311:30 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Baden-W\u00fcrttemberg","bundesland":"Baden-W\u00fcrttemberg"},{"id":22,"name":"Amtsgericht Coburg \u2014 Zentrales Mahngericht","adresse":"Postanschrift: 96441 Coburg\nHausanschrift: Heiligkreuzstra\u00dfe 22, 96450 Coburg","telefon":"09561 878-5","fax":"09621 962414-232","email":"poststelle.zentrales.mahngericht@ag-co.bayern.de","oeffnungszeiten":"Mahnabteilung: telefonisch Mo\u2013Fr 08:00\u201312:00 Uhr oder nach Vereinbarung","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Bayern","bundesland":"Bayern"},{"id":23,"name":"Amtsgericht Wedding \u2014 Zentrales Mahngericht Berlin-Brandenburg","adresse":"Postanschrift: 13343 Berlin\nBesucheranschrift: Sch\u00f6nstedtstr. 5, 13357 Berlin","telefon":"030 90156-0","fax":"030 90156-203, -233, -402, -231","email":"poststelle@aumav.berlin.de","oeffnungszeiten":"Mahnabteilung: Mo\u2013Fr 09:00\u201313:00 Uhr; Do dar\u00fcber hinaus nach Vereinbarung","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Berlin oder Brandenburg.\n\u26a0\ufe0f Au\u00dferdem ausschlie\u00dflich zust\u00e4ndig, wenn der Antragsteller KEINEN allgemeinen Gerichtsstand in Deutschland hat (\u00a7 689 Abs. 2 Satz 2 ZPO), und bundesweit f\u00fcr das Europ\u00e4ische Mahnverfahren.","bundesland":"Berlin, Brandenburg"},{"id":24,"name":"Amtsgericht Bremen \u2014 Mahnabteilung","adresse":"Ostertorstr. 25-31, 28195 Bremen","telefon":"0421 361-6115","fax":"0421 496-34851","email":"mahnabteilung@amtsgericht.bremen.de","oeffnungszeiten":"Mahnabteilung: Mo\u2013Fr 09:00\u201312:30 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Bremen","bundesland":"Bremen"},{"id":25,"name":"Amtsgericht Hamburg-Altona \u2014 gemeinsames Mahngericht","adresse":"Postanschrift: 22747 Hamburg\nHausanschrift: Max-Brauer-Allee 89, 22765 Hamburg","telefon":"040 42811-1462","fax":"040 4279-83264 (Poststelle), -83290 (Gesch\u00e4ftsstelle), -83265 (Systemverwaltung)","email":"poststelleagaltona@ag.justiz.hamburg.de","oeffnungszeiten":"Gericht allgemein: Mo, Di, Do, Fr 09:00\u201312:00 Uhr; Mi keine Sprechzeit","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Hamburg oder Mecklenburg-Vorpommern","bundesland":"Hamburg, Mecklenburg-Vorpommern"},{"id":26,"name":"Amtsgericht H\u00fcnfeld \u2014 Mahnabteilung","adresse":"Postanschrift: 36084 H\u00fcnfeld\nHausanschrift: Hauptstra\u00dfe 24, 36088 H\u00fcnfeld","telefon":"06652 600-01","fax":"0611 327618-206","email":"poststelle@ag-huenfeld.justiz.hessen.de","oeffnungszeiten":"Gericht allgemein: Mo\u2013Fr 09:00\u201312:00 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Hessen","bundesland":"Hessen"},{"id":27,"name":"Amtsgericht Uelzen \u2014 Zentrales Mahngericht","adresse":"Rosenmauer 2, 29525 Uelzen","telefon":"0581 8851-0","fax":"0581 8851-200","email":"AGUE-PoststelleZema@justiz.niedersachsen.de","oeffnungszeiten":"Gericht allgemein: Mo\u2013Fr 09:00\u201312:00 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Niedersachsen","bundesland":"Niedersachsen"},{"id":29,"name":"Amtsgericht Euskirchen \u2014 Zentrale Mahnabteilung","adresse":"Postanschrift: 53878 Euskirchen\nHausanschrift: K\u00f6lner Str. 40-42, 53879 Euskirchen","telefon":"02251 951-0","fax":"02251 951-2900","email":"poststelle@ag-euskirchen.nrw.de","oeffnungszeiten":"Mahnabteilung: Mo\u2013Fr 08:30\u201312:00 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz im OLG-Bezirk K\u00f6ln","bundesland":"Nordrhein-Westfalen"},{"id":28,"name":"Amtsgericht Hagen \u2014 Zentrale Mahnabteilung","adresse":"Postanschrift: 58081 Hagen\nHausanschrift: Hagener Str. 145, 58099 Hagen","telefon":"02331 967-5","fax":"02331 967-700","email":"poststelle.zema@ag-hagen.nrw.de","oeffnungszeiten":"Gericht allgemein: Mo, Mi, Do, Fr 08:30\u201312:30 Uhr; Di 12:00\u201316:00 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in den OLG-Bezirken D\u00fcsseldorf oder Hamm","bundesland":"Nordrhein-Westfalen"},{"id":30,"name":"Amtsgericht Mayen \u2014 Zentrale Mahnabteilung","adresse":"Postanschrift: 56723 Mayen\nHausanschrift: St. Veit-Stra\u00dfe 38, 56727 Mayen","telefon":"02651 403-0","fax":"02651 403-100","email":"amtsgericht.mayen@ko.jm.rlp.de","oeffnungszeiten":"Mahnabteilung: Mo\u2013Fr 09:00\u201312:00 Uhr und nach Vereinbarung","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Rheinland-Pfalz oder im Saarland","bundesland":"Rheinland-Pfalz, Saarland"},{"id":31,"name":"Amtsgericht Aschersleben \u2014 Gemeinsames Mahngericht","adresse":"Lehrter Str. 15, 39418 Sta\u00dffurt","telefon":"03925 876-0","fax":"03925 876-252","email":"Mahngericht@Justiz.sachsen-anhalt.de","oeffnungszeiten":null,"zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Sachsen, Sachsen-Anhalt oder Th\u00fcringen","bundesland":"Sachsen, Sachsen-Anhalt, Th\u00fcringen"},{"id":32,"name":"Amtsgericht Schleswig \u2014 Zentrales Mahngericht","adresse":"Postanschrift: Postfach 1170, 24821 Schleswig\nHausanschrift: Lollfu\u00df 78, 24837 Schleswig","telefon":"04621 815-0","fax":"04621 815-333","email":"Mahnabteilung@AG-Schleswig.LandSH.de","oeffnungszeiten":"Mahnabteilung: Mo\u2013Fr 09:00\u201312:00 Uhr oder nach Vereinbarung","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in Schleswig-Holstein","bundesland":"Schleswig-Holstein"}],"hinweis":"Zust\u00e4ndig ist das Mahngericht am Sitz des Antragstellers (\u00a7 689 Abs. 2 ZPO), nicht am Wohnort des Mitglieds. Ma\u00dfgeblich bleibt das Gericht, das auf dem Mahnbescheid steht.","einreichung":"Die E-Mail-Adresse ist eine Verwaltungsadresse. Ein Widerspruch oder ein anderer Verfahrensantrag ist per einfacher E-Mail nicht wirksam \u2014 \u00a7 130a ZPO verlangt eine qualifizierte Signatur oder einen sicheren \u00dcbermittlungsweg (beA, beBPo, Mein Justizpostfach). Formgebundene Antr\u00e4ge d\u00fcrfen auch nicht per Telefax \u00fcbermittelt werden. Fristwahrend ist der Postweg mit dem Vordruck."}
''';

  const mahngerichteHamm = r'''
{"success":true,"items":[{"id":28,"name":"Amtsgericht Hagen \u2014 Zentrale Mahnabteilung","adresse":"Postanschrift: 58081 Hagen\nHausanschrift: Hagener Str. 145, 58099 Hagen","telefon":"02331 967-5","fax":"02331 967-700","email":"poststelle.zema@ag-hagen.nrw.de","oeffnungszeiten":"Gericht allgemein: Mo, Mi, Do, Fr 08:30\u201312:30 Uhr; Di 12:00\u201316:00 Uhr","zustaendigkeit":"Antragsteller mit Sitz\/Wohnsitz in den OLG-Bezirken D\u00fcsseldorf oder Hamm","bundesland":"Nordrhein-Westfalen"}],"hinweis":"Zust\u00e4ndig ist das Mahngericht am Sitz des Antragstellers (\u00a7 689 Abs. 2 ZPO), nicht am Wohnort des Mitglieds. Ma\u00dfgeblich bleibt das Gericht, das auf dem Mahnbescheid steht.","einreichung":"Die E-Mail-Adresse ist eine Verwaltungsadresse. Ein Widerspruch oder ein anderer Verfahrensantrag ist per einfacher E-Mail nicht wirksam \u2014 \u00a7 130a ZPO verlangt eine qualifizierte Signatur oder einen sicheren \u00dcbermittlungsweg (beA, beBPo, Mein Justizpostfach). Formgebundene Antr\u00e4ge d\u00fcrfen auch nicht per Telefax \u00fcbermittelt werden. Fristwahrend ist der Postweg mit dem Vordruck."}
''';

  const planWartend = r'''
{"success":true,"items":[{"id":18,"gesamt":"150,00","monatlich":"50,00","anzahl":3,"erste_am":"2026-08-15","letzte_am":"2026-10-15","status":"angeboten","angeboten_am":"2026-08-10 23:58:36","korr_id":null,"zahlweise":"dauerauftrag","beantwortet_am":null,"antwort_notiz":"","tage_wartend":5,"erinnert":false,"pdf_url":"\/api\/admin\/vertrag_ra_raten_pdf.php?id=18","bezahlt":0,"raten":[{"id":87,"nr":1,"betrag":"50,00","faellig_am":"2026-09-15","ticket_am":"2026-08-15","ticket_id":null,"ticket_status":null,"ticket_closed_at":null},{"id":88,"nr":2,"betrag":"50,00","faellig_am":"2026-10-15","ticket_am":"2026-08-15","ticket_id":null,"ticket_status":null,"ticket_closed_at":null},{"id":89,"nr":3,"betrag":"50,00","faellig_am":"2026-11-15","ticket_am":"2026-08-15","ticket_id":null,"ticket_status":null,"ticket_closed_at":null}]}]}
''';

  const planAngenommen = r'''
{"success":true,"items":[{"id":18,"gesamt":"150,00","monatlich":"50,00","anzahl":3,"erste_am":"2026-08-15","letzte_am":"2026-10-15","status":"angenommen","angeboten_am":"2026-08-10 23:58:36","korr_id":null,"zahlweise":"dauerauftrag","beantwortet_am":"2026-08-15","antwort_notiz":"Bestaetigung per Mail","tage_wartend":null,"erinnert":true,"pdf_url":"\/api\/admin\/vertrag_ra_raten_pdf.php?id=18","bezahlt":0,"raten":[{"id":87,"nr":1,"betrag":"50,00","faellig_am":"2026-09-15","ticket_am":"2026-08-15","ticket_id":null,"ticket_status":null,"ticket_closed_at":null},{"id":88,"nr":2,"betrag":"50,00","faellig_am":"2026-10-15","ticket_am":"2026-08-15","ticket_id":null,"ticket_status":null,"ticket_closed_at":null},{"id":89,"nr":3,"betrag":"50,00","faellig_am":"2026-11-15","ticket_am":"2026-08-15","ticket_id":null,"ticket_status":null,"ticket_closed_at":null}]}]}
''';

  const antwortAngenommen = r'''
{"success":true,"message":"Angenommen \u2014 ab jetzt wird an jede Rate erinnert.","id":18,"status":"angenommen","vorher":"angeboten","beantwortet_am":"2026-08-15","erinnerungen_stillgelegt":0}
''';

  const antwortAbgelehnt = r'''
{"success":true,"message":"Vermerkt. 3 offene Erinnerung(en) stillgelegt.","id":18,"status":"abgelehnt","vorher":"angenommen","beantwortet_am":"2026-08-15","erinnerungen_stillgelegt":3}
''';

  const ratenplanStart = r'''
{"success":true,"ok":false,"fehler":null,"gesamt":"507,46","gesamt_cent":50746,"erste_am":"2026-09-01","vorschlaege":[{"monate":6,"rate":"84,58","rate_cent":8458},{"monate":10,"rate":"50,75","rate_cent":5075},{"monate":12,"rate":"42,29","rate_cent":4229},{"monate":18,"rate":"28,20","rate_cent":2820},{"monate":24,"rate":"21,15","rate_cent":2115}]}
''';

  const ratenplanRechnen = r'''
{"success":true,"ok":true,"fehler":null,"anzahl":11,"voll":10,"rate_cent":5000,"schluss_cent":746,"erste_am":"2026-09-01","letzte_am":"2027-07-01","raten":[{"nr":1,"cent":5000,"faellig_am":"2026-09-01","betrag":"50,00"},{"nr":2,"cent":5000,"faellig_am":"2026-10-01","betrag":"50,00"},{"nr":3,"cent":5000,"faellig_am":"2026-11-01","betrag":"50,00"},{"nr":4,"cent":5000,"faellig_am":"2026-12-01","betrag":"50,00"},{"nr":5,"cent":5000,"faellig_am":"2027-01-01","betrag":"50,00"},{"nr":6,"cent":5000,"faellig_am":"2027-02-01","betrag":"50,00"},{"nr":7,"cent":5000,"faellig_am":"2027-03-01","betrag":"50,00"},{"nr":8,"cent":5000,"faellig_am":"2027-04-01","betrag":"50,00"},{"nr":9,"cent":5000,"faellig_am":"2027-05-01","betrag":"50,00"},{"nr":10,"cent":5000,"faellig_am":"2027-06-01","betrag":"50,00"},{"nr":11,"cent":746,"faellig_am":"2027-07-01","betrag":"7,46"}],"gesamt":"507,46","gesamt_cent":50746,"rate":"50,00","schluss":"7,46"}
''';

  const ratenplanListe = r'''
{"success":true,"items":[]}
''';

  const akteneinsichtVorlagen = r'''
{"success":true,"vorlagen":{"anfrage":{"titel":"Erstanfrage \u2014 Unterlagen und Stillhalten","hinweis":"Bestreitet die Forderung, fordert alle Unterlagen an und bittet um Stillhalten. Frist: vier Wochen.","frist_tage":28,"betreff":"Aktenzeichen: DUMP EIN 9\/26 - Musterstrom AG, 12345 Musterstadt - Unterlagen und Stillhalten","text":"Sehr geehrte Damen und Herren,\n\nwir vertreten die Interessen unseres Mitglieds Frau Muster Paula, geboren am 01.01.1970. Die unterschriebene Vollmacht unseres Mitglieds liegt als Anlage bei.\n\nDie Forderung wird dem Grunde und der H\u00f6he nach bestritten. Unser Mitglied ist Privatperson im Sinne des \u00a7 43d Abs. 5 BRAO.\n\nWir bitten Sie nach \u00a7 43d Abs. 2 BRAO um Mitteilung, in wessen Person die Forderung entstanden ist, sowie um Darlegung der wesentlichen Umst\u00e4nde des Vertragsschlusses. Dar\u00fcber hinaus bitten wir um \u00dcbersendung s\u00e4mtlicher Unterlagen zu diesem Vorgang:\n\n  1. Vertragsunterlagen: Antrag bzw. Vertragsurkunde, einbezogene AGB\n     und Preisblatt, Datum des Vertragsschlusses\n  2. Nachweis der Belieferung: Z\u00e4hlernummer, Z\u00e4hlerst\u00e4nde und\n     Ablesedaten sowie s\u00e4mtliche Verbrauchsabrechnungen\n  3. alle Rechnungen und Mahnungen nebst Zustellnachweis\n  4. vollst\u00e4ndige Forderungsaufstellung: Hauptforderung, Zinsen mit\n     Berechnung nach \u00a7 43d Abs. 1 Nr. 3 BRAO, Inkassokosten nach Art,\n     H\u00f6he und Entstehungsgrund sowie alle Zahlungen unseres Mitglieds\n  5. sofern die Forderung abgetreten wurde, die Abtretungsurkunde\n     (\u00a7 410 BGB); andernfalls den Nachweis Ihrer Beauftragung\n  6. den Schriftverkehr mit dem Mahngericht, soweit vorhanden\n\nWir setzen hierf\u00fcr eine Frist bis zum 12.09.2026.\n\nBis zur Vorlage und Pr\u00fcfung dieser Unterlagen bitten wir, von weiteren Beitreibungsma\u00dfnahmen abzusehen, keine Meldung an Auskunfteien vorzunehmen \u2014 die Forderung ist bestritten und nicht tituliert \u2014 und keine weiteren Schritte im Mahnverfahren einzuleiten.\n\nUnser Ziel ist eine einvernehmliche L\u00f6sung. Sobald uns die Unterlagen vorliegen, melden wir uns mit einem konkreten Vorschlag. Ein Schuldanerkenntnis wird bis dahin nicht abgegeben.\n\nMit freundlichen Gr\u00fc\u00dfen"},"erinnerung":{"titel":"Erinnerung \u2014 Frist ist abgelaufen","hinweis":"Erinnert an die unbeantwortete Anfrage und setzt eine weitere Frist von zwei Wochen.","frist_tage":14,"betreff":"Aktenzeichen: DUMP EIN 9\/26 - Musterstrom AG, 12345 Musterstadt - Erinnerung","text":"Sehr geehrte Damen und Herren,\n\nmit Schreiben vom (Datum der Anfrage) haben wir die Forderung bestritten und um \u00dcbersendung der Unterlagen sowie um Auskunft nach \u00a7 43d Abs. 2 BRAO gebeten. Eine Antwort ist bis heute nicht eingegangen.\n\n\u00a7 43d Abs. 2 BRAO verpflichtet Sie zur unverz\u00fcglichen Mitteilung in Textform. Wir erinnern daran und setzen eine weitere Frist bis zum 29.08.2026.\n\nDie Forderung bleibt bis zur Vorlage der Nachweise bestritten. Wir bitten weiterhin, von Beitreibungsma\u00dfnahmen und von einer Meldung an Auskunfteien abzusehen.\n\nUnser Angebot einer einvernehmlichen L\u00f6sung bleibt bestehen.\n\nMit freundlichen Gr\u00fc\u00dfen"},"fristsetzung":{"titel":"Fristsetzung \u2014 letzte Aufforderung","hinweis":"Letzte Frist, mit Hinweis auf die Rechtsanwaltskammer als Berufsaufsicht. Keine Drohung mit Gericht.","frist_tage":14,"betreff":"Aktenzeichen: DUMP EIN 9\/26 - Musterstrom AG, 12345 Musterstadt - Fristsetzung","text":"Sehr geehrte Damen und Herren,\n\nunser Schreiben vom (Datum der Anfrage) und unsere Erinnerung vom (Datum der Erinnerung) sind unbeantwortet geblieben.\n\nWir fordern Sie letztmals auf, die Auskunft nach \u00a7 43d Abs. 2 BRAO zu erteilen und die angeforderten Unterlagen bis zum 29.08.2026 vorzulegen.\n\nOhne diese Nachweise bleibt die Forderung dem Grunde und der H\u00f6he nach bestritten; ein Schuldanerkenntnis wird nicht abgegeben und Zahlungen werden nicht geleistet. Nach fruchtlosem Fristablauf wird unser Mitglied die Rechtsanwaltskammer Koeln als zust\u00e4ndige Berufsaufsicht um Vermittlung ersuchen.\n\nWir weisen darauf hin, dass unser Angebot einer einvernehmlichen L\u00f6sung weiterhin gilt; es setzt lediglich voraus, dass die Grundlage der Forderung nachvollziehbar ist.\n\nMit freundlichen Gr\u00fc\u00dfen"}},"empfaenger":"kanzlei@example.invalid","absender":"icd@icd360s.de","kanzlei":"DUMP Kanzlei Einsicht","vollmacht_gesendet_am":null,"anhang":null,"bisher":[]}
''';

  const korrMailStatus = r'''
{"success":true,"items":[{"id":33,"message_id":"<dump-antwort-probe@icd360s.de>","status":"sent","queue_id":"DUMP0A0514D7","antwort":"250 2.0.0 OK  1786604642 - gsmtp","relay":"mx.example.invalid[93.184.216.34]:25","zugestellt_am":"2026-08-15 21:23:35"}]}
''';

  const vollmachtMailVorlagen = r'''
{"success":true,"vorlagen":{"einreichen":{"titel":"Vollmacht einreichen","hinweis":"Der Regelfall: als Ansprechpartner in die Akte aufgenommen werden und den Schriftwechsel mitbekommen.","betreff":"Aktenzeichen: DUMP 42\/26 - Vollmacht Paula","text":"Sehr geehrte Damen und Herren,\n\nals Anlage \u00fcbersenden wir Ihnen die unterzeichnete Vollmacht unseres Mitglieds Frau Muster Paula, geboren am 01.01.1970.\n\nICD360S e.V. begleitet unser Mitglied in dieser Angelegenheit. Wir bitten Sie daher, uns als Ansprechpartner in Ihre Akte aufzunehmen und den weiteren Schriftwechsel auch an uns zu richten. F\u00fcr R\u00fcckfragen erreichen Sie uns unter +49 731 80159736 oder icd@icd360s.de.\n\nEine Rechtsberatung erbringen wir nicht; das Mandat besteht allein zwischen Ihnen und unserem Mitglied.\n\nMit freundlichen Gr\u00fc\u00dfen\n\nAnlage\nVollmacht (unterschrieben und gesiegelt)"},"sachstand":{"titel":"Vollmacht einreichen und Sachstand erfragen","hinweis":"Zus\u00e4tzlich die Bitte um eine kurze Mitteilung, wie die Sache steht.","betreff":"Aktenzeichen: DUMP 42\/26 - Vollmacht Paula - Bitte um Sachstand","text":"Sehr geehrte Damen und Herren,\n\nals Anlage \u00fcbersenden wir Ihnen die unterzeichnete Vollmacht unseres Mitglieds Frau Muster Paula, geboren am 01.01.1970.\n\nICD360S e.V. begleitet unser Mitglied in dieser Angelegenheit. Wir bitten Sie daher, uns als Ansprechpartner in Ihre Akte aufzunehmen, den weiteren Schriftwechsel auch an uns zu richten und uns den aktuellen Sachstand kurz mitzuteilen. F\u00fcr R\u00fcckfragen erreichen Sie uns unter +49 731 80159736 oder icd@icd360s.de.\n\nEine Rechtsberatung erbringen wir nicht; das Mandat besteht allein zwischen Ihnen und unserem Mitglied.\n\nMit freundlichen Gr\u00fc\u00dfen\n\nAnlage\nVollmacht (unterschrieben und gesiegelt)"},"akteneinsicht":{"titel":"Vollmacht einreichen und Akteneinsicht erbitten","hinweis":"Zus\u00e4tzlich die Bitte um Ablichtungen aus der Handakte (\u00a7 50 Abs. 2 BRAO) \u2014 im Namen des Mitglieds.","betreff":"Aktenzeichen: DUMP 42\/26 - Vollmacht Paula - Bitte um Akteneinsicht","text":"Sehr geehrte Damen und Herren,\n\nals Anlage \u00fcbersenden wir Ihnen die unterzeichnete Vollmacht unseres Mitglieds Frau Muster Paula, geboren am 01.01.1970.\n\nICD360S e.V. begleitet unser Mitglied in dieser Angelegenheit. Wir bitten Sie daher, uns als Ansprechpartner in Ihre Akte aufzunehmen und den weiteren Schriftwechsel auch an uns zu richten. Namens und im Auftrag unseres Mitglieds bitten wir zudem um Einsicht in die Handakte und um \u00dcbersendung von Ablichtungen der wesentlichen Schriftst\u00fccke (\u00a7 50 Abs. 2 BRAO). F\u00fcr R\u00fcckfragen erreichen Sie uns unter +49 731 80159736 oder icd@icd360s.de.\n\nEine Rechtsberatung erbringen wir nicht; das Mandat besteht allein zwischen Ihnen und unserem Mitglied.\n\nMit freundlichen Gr\u00fc\u00dfen\n\nAnlage\nVollmacht (unterschrieben und gesiegelt)"}},"empfaenger":"kanzlei@example.invalid","kanzlei":"DUMP Kanzlei Muster PartG mbB","absender":"icd@icd360s.de","anhang":"Vollmacht_DUMP-42-26_Paula.pdf","bereit":false,"unterschrieben":0,"noetig":0}
''';

  const listKorrespondenz = r'''
{"success":true,"items":[{"id":33,"datum":"2026-07-12","richtung":"ausgehend","medium":"email","erledigt":0,"betreff":"Vollmacht und Bitte um Sachstandsmitteilung \u2014 DUMP 42\/26","text":"Sehr geehrte Damen und Herren, \u2026","gespraechspartner":"DUMP Kanzlei Muster PartG mbB","notizen":null,"mail_message_id":"<dump-antwort-probe@icd360s.de>","mail_status":"sent","mail_queue_id":"DUMP0A0514D7","mail_antwort":"250 2.0.0 OK  1786604642 - gsmtp","mail_relay":"mx.example.invalid[93.184.216.34]:25","mail_zugestellt_am":"2026-08-15 21:23:35","mail_gesendet_am":"2026-08-15 21:23:35","created_at":"2026-08-15 21:23:35","anhaenge":0},{"id":32,"datum":"2026-07-10","richtung":"eingehend","medium":"bea","erledigt":0,"betreff":"Sachstand","text":"Text mit Umlauten: \u00e4\u00f6\u00fc\u00df","gespraechspartner":null,"notizen":null,"mail_message_id":null,"mail_status":null,"mail_queue_id":null,"mail_antwort":null,"mail_relay":null,"mail_zugestellt_am":null,"mail_gesendet_am":null,"created_at":"2026-08-15 21:23:35","anhaenge":0}]}
''';

  const listVollmachtenLeer = r'''{"success":true,"items":[]}''';

  const fehlerEnum = r'''
{"success":false,"message":"Ungueltiger Wert \"gibt_es_nicht\" — erlaubt sind: kein_mandat, mandat_erteilt, in_bearbeitung, aussergerichtlich, mahnverfahren, klageverfahren, vergleich, ruht, beendet, mandat_niedergelegt"}
''';

  Map<String, dynamic> j(String s) => jsonDecode(s.trim()) as Map<String, dynamic>;

  group('Antwortform: Nutzdaten stehen in der Wurzel', () {
    test('list_aktenzeichen liefert items OHNE data-Dach', () {
      final res = j(listAktenzeichen);
      // Der Fehler, den es zu verhindern gilt: erst res['data'] auspacken.
      expect(res.containsKey('data'), isFalse,
          reason: 'jsonResponse() mischt in die Wurzel — es gibt kein data-Dach');
      final items = raListe(res);
      expect(items, hasLength(1));
      expect(items.first['aktenzeichen'], 'DUMP 42/26');
    });

    test('get_mandat hat exists in der Wurzel UND ein echtes data', () {
      final res = j(getMandat);
      expect(res['exists'], isTrue, reason: 'exists steht oben, nicht unter data');
      final daten = raKarte(res, 'data');
      expect(daten['ra_aktenzeichen'], '142/26 MU');
      // Die Kanzlei hängt eine Ebene tiefer und wird direkt gelesen.
      final kanzlei = Map<String, dynamic>.from(daten['kanzlei'] as Map);
      expect(kanzlei['firmenname'], 'DUMP Kanzlei Muster PartG mbB');
      expect(kanzlei['bea_safe_id'], 'DE.DUMP.0001');
    });

    test('raListe und raKarte lesen BEIDE Formen', () {
      // Wurzel …
      expect(raListe({'items': [{'a': 1}]}), hasLength(1));
      // … und Dach, falls ein Endpunkt es je so schickt.
      expect(raListe({'data': {'items': [{'a': 1}, {'b': 2}]}}), hasLength(2));
      expect(raKarte({'k': {'x': 1}}, 'k')['x'], 1);
      expect(raKarte({'data': {'k': {'x': 2}}}, 'k')['x'], 2);
    });

    test('eine leere Liste ist kein Absturz und kein null', () {
      expect(raListe(j(listVollmachtenLeer)), isEmpty);
      expect(raListe({'success': true}), isEmpty);
      expect(raKarte({'success': true}, 'data'), isEmpty);
    });

    test('eine Liste, wo eine Map erwartet wird, wirft NICHT', () {
      // Genau der Speedtest-Fehler: PHP kodiert ein lückenloses Array als
      // Liste, der Client las es als Map, `as Map?` warf statt null zu
      // geben, und im Release-Build blieb eine graue Fläche.
      expect(raKarte({'stufen': <dynamic>[]}, 'stufen'), isEmpty);
      expect(raListe({'stufen': <String, dynamic>{}}, 'stufen'), isEmpty);
    });
  });

  group('Mahnverfahren und Fristen', () {
    test('stufen ist ein Objekt, fristen eine Liste', () {
      final res = j(getMahnverfahren);
      expect(res['stufen'], isA<Map>(), reason: 'String-Schlüssel → PHP kodiert als Objekt');
      expect(res['fristen'], isA<List>());
      expect((res['stufen'] as Map), hasLength(10));
    });

    test('die drei Fristen tragen Norm, Datum und Dringlichkeit', () {
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      expect(fristen.map((f) => f['schluessel']),
          containsAll(['widerspruch', 'einspruch', 'mb_wirkung']));

      final einspruch = fristen.firstWhere((f) => f['schluessel'] == 'einspruch');
      expect(einspruch['datum'], '2026-08-17');
      expect(einspruch['notfrist'], isTrue);
      expect(einspruch['norm'], contains('§ 339 Abs. 1 ZPO'));

      final widerspruch = fristen.firstWhere((f) => f['schluessel'] == 'widerspruch');
      expect(widerspruch['dringlichkeit'], 'abgelaufen');
      // Bei erlassenem Vollstreckungsbescheid ist der Widerspruch nach
      // § 694 Abs. 1 ZPO endgültig weg — das muss der Hinweis auch sagen.
      expect(widerspruch['hinweis'], contains('§ 694 Abs. 1 ZPO'));
    });

    test('nur der Einspruch ist Notfrist', () {
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      final notfristen = fristen.where((f) => f['notfrist'] == true).map((f) => f['schluessel']);
      expect(notfristen, ['einspruch'],
          reason: '§ 701 und § 692 sind keine Notfristen — wer sie so kennzeichnet, '
              'macht die Kennzeichnung wertlos');
    });

    test('die Reihenfolge stellt das Dringende nach vorn, nicht das Älteste', () {
      // ⚠️ Reine Datumssortierung wäre falsch, und man sieht es erst am
      // gerenderten Bild: die am 15.06. abgelaufene Widerspruchsfrist, gegen
      // die es nichts mehr zu tun gibt, stand über der Notfrist, die in drei
      // Tagen abläuft. Das Wichtigste stand an zweiter Stelle.
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      expect(fristen.map((f) => f['schluessel']).toList(),
          ['einspruch', 'mb_wirkung', 'widerspruch']);
      expect(fristen.first['dringlichkeit'], 'bald');
      expect(fristen.last['dringlichkeit'], 'abgelaufen',
          reason: 'was vorbei und keine Notfrist ist, gehört ans Ende');
    });

    test('der Vorbehalt zur Fristenrechnung fehlt nie', () {
      final res = j(getMahnverfahren);
      expect(raWert(res['vorbehalt']), contains('§ 222 Abs. 2 ZPO'));
      expect(raWert(res['vorbehalt']), contains('landesrechtliche Feiertage'));
    });

    test('Wahrheitswerte kommen als 0/1, nicht als true/false', () {
      // Deshalb prüft die Oberfläche überall `== 1 || == true` — ein reiner
      // `as bool` läge hier daneben.
      final d = raKarte(j(getMahnverfahren), 'data');
      expect(d['zustellung_ausland'], 0);
      expect(d['erledigt'], 0);
      expect(d['zustellung_ausland'] is bool, isFalse);
    });
  });

  group('Listeneinträge tragen die Zusammenfassung für die Akte', () {
    test('Mahnstufe, offene Fristen und Vollmacht stehen am Eintrag', () {
      final a = raListe(j(listAktenzeichen)).first;
      expect(a['mahn_stufe'], 'vb_zugestellt');
      expect(a['hat_mahnverfahren'], isTrue);
      expect(a['fristen_offen'], 2);
      expect(a['vollmacht_aktiv'], isFalse);
    });

    test('fristen_offen zählt nur, was drängt', () {
      // Drei Fristen, aber nur zwei sind heute/bald/abgelaufen — die dritte
      // läuft erst im Dezember. Eine Zahl, die auch ferne Termine mitzählt,
      // wird nach einer Woche ignoriert.
      final fristen = raListe(j(getMahnverfahren), 'fristen');
      final draengend = fristen
          .where((f) => ['heute', 'bald', 'abgelaufen'].contains(f['dringlichkeit']))
          .length;
      expect(fristen, hasLength(3));
      expect(draengend, 2);
      expect(raListe(j(listAktenzeichen)).first['fristen_offen'], draengend);
    });
  });

  group('Verschlüsselte Felder überleben den Weg', () {
    test('Umlaute kommen unversehrt zurück', () {
      final k = raListe(j(listKorrespondenz))
          .firstWhere((e) => raWert(e['betreff']) == 'Sachstand');
      expect(k['text'], 'Text mit Umlauten: äöüß');
      expect(k['betreff'], 'Sachstand');
    });
  });

  group('ENUM-Kopplung Client ↔ Server', () {
    test('der Server nennt bei Ablehnung genau unsere Mandatsstatus', () {
      // ⚠️ Das PHP liegt in keinem Repository. Diese Prüfung ist die einzige
      // Stelle, an der ein Auseinanderlaufen von Datenbankspalte, `ENUMS`
      // im Endpunkt und der Liste im Client überhaupt auffallen kann.
      final message = raWert(j(fehlerEnum)['message']);
      expect(j(fehlerEnum)['success'], isFalse);
      for (final wert in RaEnums.mandatStatus) {
        expect(message, contains(wert),
            reason: '$wert fehlt in der Serverliste — Client und Server '
                'sind auseinandergelaufen');
      }
      // Und andersherum: der Server nennt nichts, was der Client nicht kennt.
      final serverListe = message.split('erlaubt sind:').last.split(',').map((e) => e.trim()).toList();
      expect(serverListe.toSet(), RaEnums.mandatStatus.toSet());
    });

    test('gelieferte Werte liegen alle in den bekannten Mengen', () {
      final a = raListe(j(listAktenzeichen)).first;
      expect(RaEnums.aktenzeichenStatus, contains(a['status']));
      expect(RaEnums.mahnStufe, contains(a['mahn_stufe']));

      final m = raKarte(j(getMahnverfahren), 'data');
      expect(RaEnums.mahnRolle, contains(m['rolle']));
      expect(RaEnums.mahnStufe, contains(m['stufe']));
      expect(RaEnums.widerspruchUmfang, contains(m['widerspruch_umfang']));

      final k = raListe(j(listKorrespondenz)).first;
      expect(RaEnums.korrRichtung, contains(k['richtung']));
      expect(RaEnums.korrMedium, contains(k['medium']));

      expect(RaEnums.mandatStatus, contains(raKarte(j(getMandat), 'data')['status']));
    });

    test('die Stufenliste des Servers deckt sich mit RaEnums.mahnStufe', () {
      final stufen = (j(getMahnverfahren)['stufen'] as Map).keys.map((e) => e.toString()).toList();
      expect(stufen.toSet(), RaEnums.mahnStufe.toSet());
    });
  });

  group('Leseexemplar in der Sprache des Mitglieds', () {
    // Echte Antworten vom 15.08.2026, Mitglied mit preferred_language='ro'.
    const createMitUebersetzung = r'''
{"success":true,"message":"Vollmacht erzeugt","id":11,"pdf_filename":"ra_vollmacht_akz14_20260815_000051_a63873.pdf","pdf_sha256":"4e4bc53598ce518585e5d7cebe80fab3a2fb0357eb36c3e1c826f3a623d1c78c","pdf_url":"/api/admin/vertrag_ra_vollmacht_pdf.php?id=11","uebersetzung_sprache":"ro","uebersetzung_url":"/api/admin/vertrag_ra_vollmacht_pdf.php?id=11&typ=uebersetzung","uebersetzung_moeglich":true,"mitglied_sprache":"ro"}
''';

    const listMitUebersetzung = r'''
{"success":true,"items":[{"id":11,"status":"draft","valid_from":"2026-08-15","valid_until":null,"pdf_filename":"ra_vollmacht_akz14_20260815_000051_a63873.pdf","pdf_sha256":"4e4bc53598ce518585e5d7cebe80fab3a2fb0357eb36c3e1c826f3a623d1c78c","pdf_uebersetzung_filename":"ra_vollmacht_akz14_20260815_000051_5956fd_ro.pdf","uebersetzung_sprache":"ro","uebermittelt_am":null,"uebermittelt_weg":null,"widerrufen_am":null,"widerruf_grund":null,"notizen":null,"created_at":"2026-08-15 00:00:51","firmenname":"Anwaltskanzlei Mumm","anwalt_name":"Monika Mumm, Rechtsanwältin","pdf_url":"/api/admin/vertrag_ra_vollmacht_pdf.php?id=11","uebersetzung_url":"/api/admin/vertrag_ra_vollmacht_pdf.php?id=11&typ=uebersetzung","status_effektiv":"draft"}]}
''';

    test('beide Fassungen kommen mit eigener Adresse zurück', () {
      final res = j(createMitUebersetzung);
      expect(res['uebersetzung_sprache'], 'ro');
      expect(raWert(res['pdf_url']), isNot(contains('typ=')),
          reason: 'ohne typ kommt die deutsche Fassung — sie ist die verbindliche');
      expect(raWert(res['uebersetzung_url']), contains('typ=uebersetzung'));
    });

    test('die Liste trägt die Sprache mit, damit der Menüpunkt nicht rät', () {
      final v = raListe(j(listMitUebersetzung)).first;
      expect(v['uebersetzung_sprache'], 'ro');
      expect(raWert(v['pdf_uebersetzung_filename']), endsWith('_ro.pdf'));
      expect(raWert(v['uebersetzung_url']), contains('typ=uebersetzung'));
    });

    test('ohne Übersetzung bleiben die Felder leer statt zu fehlen', () {
      // Der ältere Datensatz aus der ersten Fassung: keine Spalten für die
      // Übersetzung befüllt. raHat() muss darauf false sagen, sonst stünde
      // im Menü ein Eintrag, der ins Leere führt.
      final v = raListe(j(listVollmachtenLeer));
      expect(v, isEmpty);
      expect(raHat(null), isFalse);
      expect(raHat(''), isFalse);
    });

    test('die Sprachliste ist mit der des Servers gekoppelt', () {
      // ⚠️ Der Server liefert ["de","ro","en","ru","uk"] — Deutsch ist das
      // Original, nicht eine Übersetzung, deshalb steht es im Client nicht
      // in der Liste der Leseexemplare. Die Grenze kommt vom Zeichensatz:
      // cp1250/cp1251/cp1252/cp1254 sind vorhanden, Arabisch nicht — dort
      // fehlt nicht der Font, sondern Rechts-nach-links und die
      // kontextabhängigen Buchstabenformen.
      const serverSprachen = ['de', 'ro', 'en', 'ru', 'uk', 'tr'];
      expect(raUebersetzungsSprachen.toSet(),
          serverSprachen.toSet().difference({'de'}),
          reason: 'Client und Server sind auseinandergelaufen — beide Listen '
              'ändern, sonst bietet der Bildschirm eine Sprache an, für die '
              'kein PDF entsteht');
      for (final s in raUebersetzungsSprachen) {
        expect(raSpracheName(s), isNot(s.toUpperCase()),
            reason: '$s hat keinen ausgeschriebenen Namen');
      }
    });

    test('die eine Sprache ohne Leseexemplar wird benannt, nicht verschwiegen', () {
      // ar kommt bei einem Mitglied vor, bekommt aber kein Leseexemplar.
      // Die Sprache muss einen lesbaren Namen haben, damit der Bildschirm
      // sagen kann, warum es nichts gibt.
      expect(raSpracheName('ar'), 'Arabisch');
      expect(raUebersetzungsSprachen, isNot(contains('ar')),
          reason: 'Arabisch braucht RTL und Buchstabenverbindung, nicht nur '
              'einen Zeichensatz — FPDF kann beides nicht');
      // Türkisch ist seit 15.08.2026 dabei.
      expect(raSpracheName('tr'), 'Türkisch');
      expect(raUebersetzungsSprachen, contains('tr'));
      expect(raSpracheName(''), 'ohne Angabe');
    });
  });

  group('Datumsformate', () {
    test('ISO wird deutsch angezeigt', () {
      expect(raDatumDe('2026-08-14'), '14.08.2026');
      expect(raDatumDe('2026-08-03'), '03.08.2026');
      expect(raDatumDe('2026-08-14 13:38:18'), '14.08.2026');
    });

    test('leer bleibt leer — kein erfundenes Datum auf einem Fristenblatt', () {
      expect(raDatumDe(null), '');
      expect(raDatumDe(''), '');
      expect(raDatumDe('0000-00-00'), '');
      expect(raDatumDe('   '), '');
    });

    test('Unlesbares verschwindet nicht still', () {
      expect(raDatumDe('demnächst'), 'demnächst');
    });

    test('raIso liefert genau das, was der Server annimmt', () {
      expect(raIso(DateTime(2026, 8, 14)), '2026-08-14');
      expect(raIso(DateTime(2026, 1, 2)), '2026-01-02');
      expect(raIso(null), '');
      // ⚠️ Der Server weist alles andere mit HTTP 400 ab, auch das deutsche
      // Format: '01.07.2026' würde in MariaDB zu 0000-00-00 und sähe dann
      // aus wie „kein Datum erfasst".
      expect(raIso(DateTime(2026, 7, 1)), isNot('01.07.2026'));
    });
  });

  group('raWert / raHat', () {
    test('null, Zahlen und Leerraum', () {
      expect(raWert(null), '');
      expect(raWert('  x  '), 'x');
      expect(raWert(2), '2');
      expect(raHat(null), isFalse);
      expect(raHat('   '), isFalse);
      expect(raHat(0), isTrue, reason: 'die Zahl 0 ist ein Wert, kein leeres Feld');
    });
  });

  group('Vollmacht per E-Mail an die Kanzlei', () {
    test('drei Anschreiben, jedes mit Titel, Hinweis, Betreff und Text', () {
      final j = jsonDecode(vollmachtMailVorlagen) as Map<String, dynamic>;
      final v = j['vorlagen'] as Map<String, dynamic>;
      expect(v.keys.toList(), ['einreichen', 'sachstand', 'akteneinsicht'],
          reason: 'die Reihenfolge ist die Reihenfolge im Auswahlband, und '
              'der Regelfall steht vorn — er ist vorausgewählt');
      for (final k in v.keys) {
        final e = v[k] as Map<String, dynamic>;
        for (final feld in ['titel', 'hinweis', 'betreff', 'text']) {
          expect(raHat(e[feld]), isTrue, reason: '$k: $feld fehlt');
        }
      }
    });

    test('das Aktenzeichen steht VORNE im Betreff', () {
      // In einer Kanzlei wird nach Aktenzeichen sortiert und gesucht. Ein
      // Betreff, der mit „Vollmacht und Bitte um …" beginnt, geht in der
      // Liste zwischen hundert anderen Vollmachten unter.
      final v = (jsonDecode(vollmachtMailVorlagen) as Map<String, dynamic>)['vorlagen']
          as Map<String, dynamic>;
      for (final k in v.keys) {
        expect(raWert((v[k] as Map<String, dynamic>)['betreff']),
            startsWith('Aktenzeichen: '),
            reason: '$k: das Aktenzeichen gehört an den Anfang');
      }
    });

    test('jeder Brief endet mit Grußformel und Anlagenvermerk', () {
      // ⚠️ Der Anlagenvermerk steht im TEXT, nicht hinter der Signatur: dort
      // folgt der Trenner „-- ", und viele Programme klappen alles danach
      // ein. Ein Vermerk, den der Empfänger nicht sieht, nützt nichts.
      final v = (jsonDecode(vollmachtMailVorlagen) as Map<String, dynamic>)['vorlagen']
          as Map<String, dynamic>;
      for (final k in v.keys) {
        final text = raWert((v[k] as Map<String, dynamic>)['text']);
        expect(text, contains('Mit freundlichen Grüßen'), reason: k);
        expect(text.trimRight(),
            endsWith('Anlage\nVollmacht (unterschrieben und gesiegelt)'),
            reason: '$k: der Anlagenvermerk gehört ans Ende, unter die Grußformel');
        expect(text.lastIndexOf('Anlage'), greaterThan(text.indexOf('Mit freundlichen Grüßen')),
            reason: k);
      }
    });

    test('keine geratene Anrede an die Kanzlei', () {
      // Die Kanzleitabelle hat kein Geschlechtsfeld. „Sehr geehrter Herr" an
      // eine Anwältin ist der Fehler, den man nicht mehr einholt. Das „Frau"
      // bzw. „Herrn" vor dem MITGLIED ist etwas anderes: es kommt aus
      // users.geschlecht und wird nicht geraten — fehlt der Wert, steht dort
      // nur der Name.
      final roh = vollmachtMailVorlagen;
      expect(roh.contains('Sehr geehrter Herr'), isFalse);
      expect(roh.contains('Sehr geehrte Frau'), isFalse);
      expect(roh.contains('Sehr geehrte Damen und Herren'), isTrue);
    });

    test('jede Vorlage klärt, dass wir nicht rechtsberaten', () {
      final v = (jsonDecode(vollmachtMailVorlagen) as Map<String, dynamic>)['vorlagen']
          as Map<String, dynamic>;
      for (final k in v.keys) {
        expect(
            raWert((v[k] as Map<String, dynamic>)['text'])
                .contains('Eine Rechtsberatung erbringen wir nicht'),
            isTrue,
            reason: '$k: ohne diesen Satz sieht die Anfrage aus wie jemand, '
                'der sich in ein Mandat drängt (§ 2 Abs. 1 RDG)');
      }
    });

    test('bereit/unterschrieben/noetig sagen, WARUM der Knopf nicht geht', () {
      final j = jsonDecode(vollmachtMailVorlagen) as Map<String, dynamic>;
      expect(j.containsKey('bereit'), isTrue);
      expect(j.containsKey('unterschrieben'), isTrue);
      expect(j.containsKey('noetig'), isTrue);
      // Frisch erzeugt, niemand hat unterschrieben.
      expect(j['bereit'], isFalse);
      expect(j['noetig'], 0);
    });

    test('Absender ist das Vereinspostfach, Empfänger die Kanzlei', () {
      final j = jsonDecode(vollmachtMailVorlagen) as Map<String, dynamic>;
      expect(raWert(j['absender']), contains('@'));
      expect(raWert(j['empfaenger']), contains('@'));
      expect(raWert(j['anhang']).endsWith('.pdf'), isTrue);
    });
  });

  group('Zustellstand in der Korrespondenz', () {
    test('ein Ausgang trägt Status, Warteschlange und Antwortcode', () {
      final items = raListe(jsonDecode(listKorrespondenz) as Map<String, dynamic>);
      final ausgang = items.firstWhere((e) => raWert(e['richtung']) == 'ausgehend');
      expect(raWert(ausgang['medium']), 'email');
      expect(raHat(ausgang['mail_message_id']), isTrue);
      expect(raWert(ausgang['mail_status']), 'sent');
      expect(raHat(ausgang['mail_queue_id']), isTrue);
      expect(raWert(ausgang['mail_antwort']), startsWith('250'),
          reason: 'der Antwortcode des Zielservers ist die eigentliche Auskunft');
    });

    test('eine handgetippte Zeile täuscht KEINEN Zustellstand vor', () {
      // ⚠️ Ohne Message-ID darf der Bildschirm nichts anzeigen. Sonst stünde
      // ein grüner Haken unter einem Vorgang, den niemand nachgesehen hat.
      final items = raListe(jsonDecode(listKorrespondenz) as Map<String, dynamic>);
      final eingang = items.firstWhere((e) => raWert(e['richtung']) == 'eingehend');
      expect(eingang['mail_message_id'], isNull);
      expect(eingang['mail_status'], isNull);
      expect(raHat(eingang['mail_message_id']), isFalse);
    });

    test('jeder Vorgang meldet, wie viele Anhänge er hat', () {
      // ⚠️ Ohne dieses Feld stünde im geöffneten Vorgang immer „Keine
      // Anhänge" — auch bei einer Mail, mit der die Vollmacht hinausging.
      final items = raListe(jsonDecode(listKorrespondenz) as Map<String, dynamic>);
      for (final e in items) {
        expect(e.containsKey('anhaenge'), isTrue);
        expect(int.tryParse(raWert(e['anhaenge'])), isNotNull,
            reason: 'anhaenge muss eine Zahl sein, nicht null');
      }
    });

    test('korr_mail_status liefert je Zeile den Stand', () {
      final items = raListe(jsonDecode(korrMailStatus) as Map<String, dynamic>);
      expect(items, isNotEmpty);
      final z = items.first;
      for (final feld in ['id', 'message_id', 'status', 'queue_id', 'antwort']) {
        expect(z.containsKey(feld), isTrue, reason: '$feld fehlt');
      }
      expect(raWert(z['status']), 'sent');
    });
  });

  group('Akteneinsicht bei der Kanzlei der Gegenseite', () {
    Map<String, dynamic> vor() =>
        (jsonDecode(akteneinsichtVorlagen) as Map<String, dynamic>)['vorlagen']
            as Map<String, dynamic>;

    test('drei Stufen in der Reihenfolge der Eskalation', () {
      expect(vor().keys.toList(), ['anfrage', 'erinnerung', 'fristsetzung']);
    });

    test('NICHT § 50 BRAO — das wäre der falsche Anspruch', () {
      // § 50 BRAO ist der Handakten-Anspruch gegen den EIGENEN Anwalt.
      // Gegenüber der Kanzlei, die für den Gläubiger einzieht, gibt es ihn
      // nicht; wer ihn dort geltend macht, bekommt zu Recht eine Absage.
      expect(akteneinsichtVorlagen.contains('§ 50'), isFalse);
      expect(raWert(vor()['anfrage']?['text']), contains('§ 43d Abs. 2 BRAO'));
    });

    test('die Erstanfrage räumt vier Wochen ein', () {
      expect(vor()['anfrage']?['frist_tage'], 28);
      expect(vor()['erinnerung']?['frist_tage'], 14);
      expect(vor()['fristsetzung']?['frist_tage'], 14);
    });

    test('bestreitet, bittet um Stillhalten, gibt kein Anerkenntnis', () {
      final t = raWert(vor()['anfrage']?['text']);
      expect(t, contains('dem Grunde und der Höhe nach bestritten'));
      expect(t, contains('von weiteren Beitreibungsmaßnahmen abzusehen'));
      expect(t, contains('keine Meldung an Auskunfteien'));
      expect(t, contains('Schuldanerkenntnis wird bis dahin nicht abgegeben'));
      expect(t, contains('einvernehmliche Lösung'));
    });

    test('fordert alle sechs Gruppen von Unterlagen an', () {
      final t = raWert(vor()['anfrage']?['text']);
      for (final stichwort in [
        'Vertragsurkunde',
        'Zählerstände',
        'Mahnungen',
        'Forderungsaufstellung',
        'Abtretungsurkunde',
        'Mahngericht',
      ]) {
        expect(t, contains(stichwort), reason: '$stichwort fehlt in der Liste');
      }
    });

    test('die Kammer kommt aus der Kanzleiakte, nicht aus dem Code', () {
      expect(raWert(vor()['fristsetzung']?['text']),
          contains('Rechtsanwaltskammer'));
    });

    test('ohne vorherigen Versand hängt die Vollmacht an', () {
      final j = jsonDecode(akteneinsichtVorlagen) as Map<String, dynamic>;
      expect(j['vollmacht_gesendet_am'], isNull);
      expect(raWert(vor()['anfrage']?['text']), contains('liegt als Anlage bei'));
    });

    test('der Betreff nennt Aktenzeichen und Gläubiger', () {
      for (final k in vor().keys) {
        expect(raWert((vor()[k] as Map)['betreff']), startsWith('Aktenzeichen: '));
      }
    });
  });

  group('Ratenzahlung', () {
    test('ohne Wunschrate: Gesamtsumme aus der Akte plus Vorschläge', () {
      final j = jsonDecode(ratenplanStart) as Map<String, dynamic>;
      expect(j['ok'], isFalse, reason: 'ohne Rate gibt es noch keinen Plan');
      expect(raWert(j['gesamt']), '507,46');
      expect((j['vorschlaege'] as List).length, 5);
    });

    test('507,46 € zu 50 €: elf Raten, Schlussrate ist der REST', () {
      // ⚠️ Nicht elf volle Raten — dann zahlte das Mitglied 42,54 € zu viel.
      final j = jsonDecode(ratenplanRechnen) as Map<String, dynamic>;
      expect(j['ok'], isTrue);
      expect(j['anzahl'], 11);
      expect(j['voll'], 10);
      expect(raWert(j['schluss']), '7,46');
      expect(raWert(j['letzte_am']), '2027-07-01');
    });

    test('die einzelnen Raten summieren sich auf die Gesamtsumme', () {
      final j = jsonDecode(ratenplanRechnen) as Map<String, dynamic>;
      var cent = 0;
      for (final r in (j['raten'] as List)) {
        cent += int.tryParse(raWert((r as Map)['cent'])) ?? 0;
      }
      expect(cent, j['gesamt_cent'],
          reason: 'ein Rundungsfehler wäre eine falsche Zahl in einem Angebot '
              'an eine Kanzlei');
    });

    test('jede Rate trägt Nummer, Betrag und Fälligkeit', () {
      final raten = (jsonDecode(ratenplanRechnen) as Map<String, dynamic>)['raten'] as List;
      for (final r in raten) {
        final m = r as Map;
        expect(raHat(m['nr']), isTrue);
        expect(raHat(m['betrag']), isTrue);
        expect(raWert(m['faellig_am']), matches(r'^\d{4}-\d{2}-\d{2}$'));
      }
    });

    test('leere Liste ist eine Liste, kein Objekt', () {
      // Dieselbe Falle wie im Speedtest: PHP macht aus einem leeren Array `[]`,
      // aus einem gefüllten mit Lücken ein Objekt. `as Map?` auf einer Liste
      // gibt nicht null zurück, sondern wirft.
      expect(raListe(jsonDecode(ratenplanListe) as Map<String, dynamic>), isEmpty);
    });
  });

  group('IBAN nur fürs Auge gruppieren', () {
    test('Vierergruppen nach ISO 13616', () {
      expect(raIbanLesbar('DE23360100430999684438'),
          'DE23 3601 0043 0999 6844 38');
    });

    test('schon gruppierte Eingabe wird nicht doppelt zerlegt', () {
      expect(raIbanLesbar('DE23 3601 0043 0999 6844 38'),
          'DE23 3601 0043 0999 6844 38');
    });

    test('Kleinschreibung wird zu Großschreibung', () {
      expect(raIbanLesbar('de23360100430999684438'), startsWith('DE23 '));
    });

    test('leer bleibt leer', () => expect(raIbanLesbar(''), ''));

    test('kurze Reste werfen nicht', () {
      // ⚠️ Die letzte Gruppe ist bei DE zweistellig — eine feste
      // Vierer-Schnittweite liefe über das Ende hinaus.
      expect(raIbanLesbar('DE12345'), 'DE12 345');
    });
  });

  group('Antwort der Gegenseite auf das Ratenangebot', () {
    Map<String, dynamic> plan(String roh) =>
        raListe(jsonDecode(roh) as Map<String, dynamic>).first;

    test('solange niemand geantwortet hat, wird NICHT erinnert', () {
      // ⚠️ Das ist die wichtigste Zeile dieser Datei. „angeboten" heißt: das
      // Angebot ist raus, es gibt noch keine Vereinbarung. Wer trotzdem
      // erinnert wird und zahlt, leistet auf eine bestrittene Forderung —
      // und liefert womöglich das Anerkenntnis nach § 212 Abs. 1 Nr. 1 BGB,
      // ohne die Ratenvereinbarung dafür zu bekommen.
      final p = plan(planWartend);
      expect(raWert(p['status']), 'angeboten');
      expect(p['erinnert'], isFalse);
      expect(p['beantwortet_am'], isNull);
    });

    test('die Wartezeit kommt fertig gerechnet vom Server', () {
      final p = plan(planWartend);
      expect(p['tage_wartend'], 5,
          reason: 'der Client rechnet nichts nach — sonst zwei Wahrheiten');
    });

    test('nach der Annahme wird erinnert, mit Datum und Notiz', () {
      final p = plan(planAngenommen);
      expect(raWert(p['status']), 'angenommen');
      expect(p['erinnert'], isTrue);
      expect(raHat(p['beantwortet_am']), isTrue);
      expect(raWert(p['antwort_notiz']), 'Bestaetigung per Mail');
      expect(p['tage_wartend'], isNull, reason: 'gewartet wird nicht mehr');
    });

    test('die Annahme sagt, was sie auslöst', () {
      final j = jsonDecode(antwortAngenommen) as Map<String, dynamic>;
      expect(j['success'], isTrue);
      expect(raWert(j['message']), contains('erinnert'));
      expect(raHat(j['beantwortet_am']), isTrue);
    });

    test('eine Ablehnung legt die offenen Erinnerungen stumm', () {
      // Stillgelegt, nicht gelöscht: was schon ein Ticket hat, bleibt Teil
      // des Vorgangs und nachlesbar.
      final j = jsonDecode(antwortAbgelehnt) as Map<String, dynamic>;
      expect(raWert(j['status']), 'abgelehnt');
      expect(j['erinnerungen_stillgelegt'], 3);
      expect(raWert(j['message']), contains('stillgelegt'));
    });

    test('der Zahlweg überlebt die Statusänderung', () {
      expect(raWert(plan(planAngenommen)['zahlweise']), 'dauerauftrag');
    });
  });

  group('Postnachweis: Dienstleister und Beweiswert', () {
    Map<String, dynamic> j() => jsonDecode(postDienstleister) as Map<String, dynamic>;

    test('vierzehn Dienste, Brief und Paket getrennt', () {
      final d = raListe(j());
      expect(d, hasLength(14));
      expect(d.where((x) => raWert(x['art']) == 'brief'), hasLength(5),
          reason: 'Briefdienste sind der Regelfall für Schriftsätze');
      expect(d.where((x) => raWert(x['art']) == 'kurier'), hasLength(2));
    });

    test('nur wer wirklich verfolgt, wird als verfolgbar geführt', () {
      // ⚠️ Sieben Dienste bieten keine Verfolgung mit Nummer in der Adresse.
      // Eine erfundene Adresse wäre schlimmer als keine: ein toter Link sieht
      // aus wie ein Fehler unserer App, nicht wie eine fehlende Auskunft.
      final d = raListe(j());
      final verfolgbar = d.where((x) => raWert(x['verfolgbar']) == '1');
      expect(verfolgbar, hasLength(7));
      // PIN, Postcon, Citipost, mail alliance und die drei Sammeleinträge nicht.
      final pin = d.firstWhere((x) => raWert(x['name']).contains('PIN'));
      expect(raWert(pin['verfolgbar']), isNot('1'));
    });

    test('neun Versandarten, fünf davon starker Nachweis', () {
      final a = raListe(j(), 'versandarten');
      expect(a, hasLength(9));
      expect(a.where((x) => raWert(x['beweis']) == 'stark'), hasLength(5));
      expect(a.map((x) => raWert(x['schluessel'])), contains('einschreiben_rueckschein'));
    });

    test('🔴 das Einwurf-Einschreiben ist als SCHWACH geführt', () {
      // ⚠️ Das ist die wichtigste Zeile dieser Datei. Bis zum 07.05.2026 galt
      // das Einwurf-Einschreiben als der übliche Zugangsnachweis; das BAG hat
      // den Anscheinsbeweis gekippt (2 AZR 184/25), weil der Zusteller im
      // Scan-Verfahren die Auslieferung bestätigt, BEVOR er einwirft. Wer sich
      // im Fristenstreit darauf verlässt, steht mit leeren Händen da.
      // Kippt jemand diese Einstufung zurück auf „stark", schlägt hier fehl.
      final ee = raListe(j(), 'versandarten')
          .firstWhere((x) => raWert(x['schluessel']) == 'einwurf_einschreiben');
      expect(raWert(ee['beweis']), 'schwach');
      expect(raWert(ee['hinweis']), contains('2 AZR 184/25'));
      expect(raWert(ee['hinweis']), contains('07.05.2026'));
      expect(raWert(ee['hinweis']), contains('Nicht als alleiniger Nachweis'));
    });

    test('das Fax warnt vor dem Formularzwang der Mahngerichte', () {
      final fax = raListe(j(), 'versandarten')
          .firstWhere((x) => raWert(x['schluessel']) == 'fax');
      expect(raWert(fax['hinweis']), contains('NICHT per Fax'));
    });

    test('der Hinweis nennt die Grenze: Weg ja, Inhalt nein', () {
      // Eine Sendungsnummer beweist nie, WAS im Umschlag lag. Wer das nicht
      // liest, legt keine Kopie des Schriftsatzes dazu — und hat im Streit
      // einen Beleg über einen leeren Umschlag.
      expect(raWert(j()['hinweis']), contains('nie ihren Inhalt'));
    });
  });

  group('Nachschlagewerk der Mahngerichte', () {
    test('zwölf Gerichte für sechzehn Länder', () {
      // Die Länder haben die Verfahren nach § 689 Abs. 3 ZPO gebündelt —
      // ein Gericht je Land wäre die falsche Erwartung.
      expect(raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>).length, 12);
    });

    test('der Hinweis nennt die Falle beim Namen', () {
      // ⚠️ Zuständig ist das Gericht am Sitz des ANTRAGSTELLERS, nicht am
      // Wohnort des Mitglieds. Ein Widerspruch beim falschen Gericht wahrt
      // die Frist nicht — deshalb steht der Satz im Suchdialog und nicht in
      // einer Hilfeseite.
      final j = jsonDecode(mahngerichteAlle) as Map<String, dynamic>;
      expect(raWert(j['hinweis']), contains('§ 689 Abs. 2 ZPO'));
      expect(raWert(j['hinweis']), contains('Sitz des Antragstellers'));
      expect(raWert(j['hinweis']), contains('Mahnbescheid'));
    });

    test('jedes Gericht trägt Anschrift und Zuständigkeit', () {
      for (final g in raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)) {
        expect(raHat(g['name']), isTrue);
        expect(raHat(g['adresse']), isTrue, reason: raWert(g['name']));
        expect(raHat(g['zustaendigkeit']), isTrue, reason: raWert(g['name']));
        expect(raHat(g['bundesland']), isTrue, reason: raWert(g['name']));
      }
    });

    test('NRW hat zwei, getrennt nach OLG-Bezirk', () {
      final nrw = raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)
          .where((g) => raWert(g['bundesland']) == 'Nordrhein-Westfalen');
      expect(nrw.length, 2);
    });

    test('die Suche greift auch auf den OLG-Bezirk', () {
      // „Hamm" steht nur in der Zuständigkeit, nicht im Namen — eine Suche
      // allein über den Namen fände nichts.
      final t = raListe(jsonDecode(mahngerichteHamm) as Map<String, dynamic>);
      expect(t.length, 1);
      expect(raWert(t.first['name']), contains('Hagen'));
    });

    test('kein Gericht ohne Telefon, Fax und E-Mail', () {
      // Ein halb gefülltes Verzeichnis ist schlimmer als keines: wer eine
      // Faxnummer sucht und keine findet, glaubt, das Gericht habe keine.
      for (final g in raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)) {
        expect(raHat(g['telefon']), isTrue, reason: raWert(g['name']));
        expect(raHat(g['fax']), isTrue, reason: raWert(g['name']));
        expect(raHat(g['email']), isTrue, reason: raWert(g['name']));
      }
    });

    test('jede Vorwahl passt zum Ort — bis auf zwei erklärte Ausnahmen', () {
      // ⚠️ Das ist die einzige Prüfung, die einen ZAHLENDREHER findet. Ein
      // Abgleich mit der Quelle hilft dort nicht: die Quelle ist richtig, der
      // Fehler entsteht beim Abtippen. Eine falsche Ortsnetzkennzahl fällt
      // dagegen sofort auf.
      const ort = {
        'Stuttgart': '0711', 'Coburg': '09561', 'Wedding': '030',
        'Bremen': '0421', 'Hamburg-Altona': '040', 'Hünfeld': '06652',
        'Uelzen': '0581', 'Hagen': '02331', 'Euskirchen': '02251',
        'Mayen': '02651', 'Aschersleben': '03925', 'Schleswig': '04621',
      };
      // ⚠️ Zwei Faxnummern liegen bewusst in einem FREMDEN Ortsnetz: Bayern
      // und Hessen bündeln den Faxeingang zentral (Amberg bzw. Wiesbaden).
      // Sieht nach Tippfehler aus, ist keiner — wer sie „korrigiert", macht
      // sie kaputt.
      const faxAusnahme = {'Coburg': '09621', 'Hünfeld': '0611'};

      for (final g in raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)) {
        final name = raWert(g['name']);
        final stadt = ort.keys.firstWhere((k) => name.contains(k), orElse: () => '');
        expect(stadt, isNotEmpty, reason: 'unbekanntes Gericht: $name');

        final tel = raWert(g['telefon']).split(' ').first;
        expect(tel, ort[stadt], reason: '$name: Telefonvorwahl');

        final fax = raWert(g['fax']).split(' ').first;
        expect(fax, faxAusnahme[stadt] ?? ort[stadt], reason: '$name: Faxvorwahl');
      }
    });

    test('Hamburgs Fax nennt die Geschäftsstelle, nicht nur die EDV', () {
      // Drei Faxnummern betreffen dort das Mahngericht. Wer zu einem
      // laufenden Verfahren schreibt, will die Geschäftsstelle (-83290) —
      // gespeichert war einmal nur die Systemverwaltung (-83265).
      final h = raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)
          .firstWhere((g) => raWert(g['name']).contains('Hamburg'));
      final f = raWert(h['fax']);
      expect(f, contains('-83290'));
      expect(f, contains('Geschäftsstelle'));
      expect(f, contains('Poststelle'), reason: 'unbeschriftet wählt jemand die falsche');
    });

    test('Sprechzeiten sagen immer, WESSEN Zeiten es sind', () {
      // ⚠️ „Mo–Fr 09:00–12:00" ist zweideutig: bei Hünfeld, Uelzen, Hagen und
      // Hamburg sind es die Zeiten des ganzen Amtsgerichts, die Mahnabteilung
      // veröffentlicht keine eigenen. Wer dann dort anruft, greift ins Leere.
      // Ohne das Etikett sieht beides gleich verbindlich aus.
      for (final g in raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)) {
        final z = raWert(g['oeffnungszeiten']);
        if (z.isEmpty) continue; // Aschersleben veröffentlicht nichts
        expect(z.startsWith('Mahnabteilung:') || z.startsWith('Gericht allgemein:'), isTrue,
            reason: '${raWert(g['name'])}: „$z" nennt keinen Träger');
      }
    });

    test('eine vorübergehende Einschränkung trägt ihr Datum', () {
      // Stuttgart ist seit 29.06.2026 eingeschränkt erreichbar. Ohne das Datum
      // liest sich das in einem Jahr wie ein Dauerzustand — und niemand käme
      // auf die Idee nachzusehen.
      final s = raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)
          .firstWhere((g) => raWert(g['name']).contains('Stuttgart'));
      final z = raWert(s['oeffnungszeiten']);
      expect(z, contains('vorübergehend'));
      expect(z, matches(RegExp(r'\d{2}\.\d{2}\.\d{4}')),
          reason: 'ohne Datum ist die Einschränkung nicht nachprüfbar');
    });

    test('die E-Mail-Adresse kommt nie ohne die Warnung', () {
      // ⚠️ Der teuerste Irrtum in diesem Verfahren: den Widerspruch an die
      // E-Mail-Adresse schicken, die auf der Karte steht. Er wäre unwirksam,
      // die Frist liefe weiter, und niemand bekäme eine Fehlermeldung.
      final j = jsonDecode(mahngerichteAlle) as Map<String, dynamic>;
      final e = raWert(j['einreichung']);
      expect(e, isNotEmpty, reason: 'Adressen ohne diesen Satz sind eine Falle');
      expect(e, contains('nicht wirksam'));
      expect(e, contains('§ 130a ZPO'));
      expect(e, contains('Telefax'));
      expect(e, contains('Postweg'));
    });

    test('das Wedding trägt den Sonderfall ohne deutschen Gerichtsstand', () {
      final w = raListe(jsonDecode(mahngerichteAlle) as Map<String, dynamic>)
          .firstWhere((g) => raWert(g['name']).contains('Wedding'));
      expect(raWert(w['zustaendigkeit']), contains('§ 689 Abs. 2 Satz 2'));
    });
  });
}
