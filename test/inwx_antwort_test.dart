import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/inwx_screen.dart';

/// Antworten von api/vereinverwaltung/inwx_manage.php, aufgezeichnet am
/// 08.08.2026 gegen das laufende INWX-Konto — die FORM ist echt, die WERTE
/// sind ersetzt.
///
/// 🔴 Die Werte sind bewusst erfunden, und das muss so bleiben. Bis zum
/// 24.08.2026 stand hier die echte Aufzeichnung, und dieses Repo ist
/// öffentlich: damit lagen 16 Tage lang die Service-PIN des Registrar-Kontos
/// (sie legitimiert am Telefon bei INWX), Kunden- und Kontonummer, Name und
/// Privatanschrift des Inhabers sowie die Login-IPs auf GitHub — neben dem
/// Feld `zwei_fa: false`, das gleich mitteilte, dass keine zweite Hürde
/// wartet. An dieser Domain hängen Web, Mail, WebSocket und die Auslieferung
/// beider Apps.
///
/// ⚠️ Wer diese Datei neu aufzeichnet, zeichnet damit auch wieder echte
/// Kontodaten auf. Nach jedem Neuaufnehmen sind mindestens zu ersetzen:
/// `service_pin`, `kundennummer`, `konto_id`, `username`/`api.user`,
/// `inhaber`, `anschrift`, `letzte_ip` und die IPs in `aktivitaeten`,
/// Rechnungs- und Kontakt-Nummern. Die DNS-Einträge dürfen echt bleiben —
/// die stehen ohnehin für jeden im öffentlichen DNS.
///
/// ⚠️ Der Sinn ist NICHT, die Zahlen zu prüfen, sondern die FORM. PHP kennt
/// nur einen Array-Typ: `['a'=>1]` kodiert `json_encode` als Objekt, `[]`
/// dagegen als Liste. Ein `as Map` auf einer Liste liefert nicht null,
/// sondern wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026
/// in der Produktion beim Aufbau hängen und zeigte nur eine graue Fläche.
/// Weder `flutter analyze` noch die Widget-Tests sehen so etwas, weil keiner
/// davon die echte Serverantwort anfasst.

const String _getAll = r'''
{"success":true,"data":{"api.doku_url":"https://account.inwx.de/de/help/apidoc","api.endpoint":"https://api.domrobot.com/jsonrpc/","api.user":"kunde-muster","firma.akkreditierung":"ICANN, DENIC, EURid, SWITCH, ES-NIC","firma.billing_email":"billing@inwx.com","firma.branche":"Domain-Registrar / DNS / Hosting","firma.datenschutz":"IITR Datenschutz GmbH, Marienplatz 2, 80331 Muenchen — email@iitr.de","firma.firma_name":"INWX GmbH","firma.geschaeftsfuehrer":"Mario Peschel","firma.hauptzentrale_email":"info@inwx.com","firma.hauptzentrale_fax":"+49 30 983 212 90","firma.hauptzentrale_land":"Deutschland","firma.hauptzentrale_ort":"Berlin","firma.hauptzentrale_plz":"10969","firma.hauptzentrale_strasse":"Prinzessinnenstr. 30","firma.hauptzentrale_telefon":"+49 30 983 21 20","firma.impressum_url":"https://www.inwx.de/de/aboutus/imprint","firma.quelle":"Impressum inwx.de, abgerufen 08.08.2026","firma.rechtsform":"GmbH","firma.registergericht":"Amtsgericht Berlin-Charlottenburg","firma.registernummer":"HRB 237141 B","firma.support_email":"support@inwx.com","firma.support_telefon":"+49 30 983 21 21 21","firma.ust_id":"DE814537105","firma.website":"https://www.inwx.de","zugang.url":"https://www.inwx.de/de/customer/signin","api.pass_gesetzt":"1","api.totp_gesetzt":""},"leistungen":[{"id":1,"kategorie":"domain","bezeichnung":"Domain icd360s.de","objekt":"icd360s.de","status":"aktiv","kosten":"","intervall":"jaehrlich","beginn_datum":"2025-08-14","ablauf_datum":"2026-08-14","tage_bis_ablauf":6,"auto_renew":true,"notiz":"Aus INWX-Konto übernommen.\nNameserver: ns.inwx.de, ns2.inwx.de, ns3.inwx.eu\nTransfer-Lock: ja","quelle":"api"}]}
''';

const String _apiStatus = r'''
{"success":true,"verbunden":true,"konto":{"username":"kunde-muster","kundennummer":"100000","org":"ICD360S e.V","email":"inwx@icd360s.de","zahlungsart":"Prepaid","waehrung":"EUR","zwei_fa":false,"renewal_mode":"AUTORENEW","letzter_login":"2026-08-08"},"guthaben":{"total":5.97,"available":0,"locked":0,"credit_limit":0,"waehrung":"EUR"}}
''';

const String _apiDomains = r'''
{"success":true,"domains":[{"domain":"icd360s.de","status":"OK","registriert":"2025-08-14","ablauf":"2026-08-14","renewal_mode":"AUTORENEW","transferlock":true,"nameserver":["ns.inwx.de","ns2.inwx.de","ns3.inwx.eu"],"period":"1Y"}],"anzahl":1}
''';

/// Kein einziger Datensatz: PHP macht daraus `[]`, nicht `{}`.
const String _getAllLeer = r'''
{"success":true,"data":[],"leistungen":[]}
''';

/// Echte Antwort von `api_konto`, gekürzt auf die ersten Protokolleinträge.
const String _apiKonto = r'''
{"success":true,"verbunden":true,"konto":{"username":"kunde-muster","kundennummer":"100000","konto_id":"200000","org":"ICD360S e.V","inhaber":"Max Mustermann","anschrift":"Musterstr. 1, 12345 Musterstadt, DE","telefon":"+49.111111111111","fax":"","website":"https://icd360s.de","email":"inwx@icd360s.de","email_rechnung":"inwx@icd360s.de","zahlungsart":"Prepaid","waehrung":"EUR","ust_satz":"19.00","zwei_fa":false,"renewal_mode":"AUTORENEW","rechnung_pdf":true,"sammelrechnung":false,"reseller":"no","kunde_seit":"2025-08-14","letzter_login":"2026-08-08 11:39","logins":336,"letzte_ip":"2001:db8::1","service_pin":"000000"},"guthaben":{"total":5.97,"available":0,"locked":0,"credit_limit":0,"waehrung":"EUR"},"rechnungen":[{"nummer":"2020000001","datum":"2025-08-31","brutto":5.97,"netto":5.02,"art":"Invoice","hat_xml":true}],"rechnungen_anzahl":1,"bewegungen":[{"zeitpunkt":"2025-08-31 02:00","betrag":-5.97,"art":"Invoice","details":"2020000001","erstattbar":false},{"zeitpunkt":"2025-08-14 22:26","betrag":5.97,"art":"Payment","details":"Credit card","erstattbar":true}],"bewegungen_anzahl":2,"bewegungen_seit":"2025-08-14","aktivitaeten":[{"zeitpunkt":"2025-10-24 22:11","domain":"icd360s.de","vorgang":"UPDATE NOTIFY","preis":0,"rechnung":"","wer":"System / Registry","ip":"","text":"DNSSEC update successful","log_id":"48922235"},{"zeitpunkt":"2025-10-24 22:05","domain":"icd360s.de","vorgang":"DNSSEC DEACTIVATION REQUESTED","preis":0,"rechnung":"","wer":"kunde-muster","ip":"2001:db8::2","text":"","log_id":"48922217"}],"aktivitaeten_anzahl":19,"aktivitaeten_summe":5.97}
''';

/// Nicht verbunden: hier ist `fehler` eine ZEICHENKETTE.
const String _apiKontoOffline = r'''
{"success":true,"verbunden":false,"fehler":"Login abgelehnt: Authorization error (Code 2200)"}
''';

/// Echte `api_dns`-Antwort, auf 5 der 38 Einträge gekürzt (je einer pro
/// geprüfter Eigenschaft), Schlüsselmaterial gekürzt.
const String _apiDns = r'''
{"success":true,"verbunden":true,"zonen":["icd360s.de"],"zone":{"domain":"icd360s.de","ro_id":"1000000","typ":"MASTER","anzahl":38,"records":[{"id":"2203163207","name":"icd360s.de","typ":"A","inhalt":"51.195.4.85","ttl":300,"prio":0},{"id":"2227312181","name":"icd360s.de","typ":"AAAA","inhalt":"2001:41d0:700:3ff0::1","ttl":300,"prio":0},{"id":"2108639387","name":"icd360s.de","typ":"CAA","inhalt":"0 issue \"letsencrypt.org\"","ttl":300,"prio":0},{"id":"2109129724","name":"icd360s.de","typ":"MX","inhalt":"mail.icd360s.de","ttl":300,"prio":10},{"id":"2111981415","name":"icd360s.de","typ":"TXT","inhalt":"v=spf1 ip4:135.125.128.33 -all","ttl":3600,"prio":0}],"dnssec_aktiv":[{"key_tag":"5756","algorithmus":"13","flags":"257","angelegt":"2025-10-24 20:05:18"}],"dnssec_abgeloest":4,"hinweise":[{"stufe":"info","text":"Übrig gebliebener ACME-Nachweis: _acme-challenge.mail.icd360s.de — wird nur während der Zertifikatsausstellung gebraucht."}]}}
''';

/// Der Preis- und Kontaktteil von `api_konto`, echt.
const String _apiKontoPreise = r'''
{"success":true,"verbunden":true,"guthaben":{"total":5.97,"available":0,"locked":0,"credit_limit":0,"waehrung":"EUR"},"tlds":["de"],"preise":[{"tld":"de","waehrung":"EUR","verlaengerung":4.6529,"verlaengerung_brutto":5.54,"ust_satz":19,"neuanlage":5.9738,"transfer":4.6529,"wiederherstellung":28.4529,"zeitraum":"1"}],"preisaenderungen":[],"kontakte":[{"id":"100001","typ":"ORG","name":"Max Mustermann","org":"ICD360S e.V i.G","anschrift":"Musterstr. 1, 12345 Musterstadt, DE","telefon":"+49.111111111111","email":"verein@muster.invalid","verwendet":1,"nur_lesen":false,"geprueft":"CONFIRMED","kontakt_geprueft":"NOT-VERIFIED"},{"id":"1","typ":"ROLE","name":"Hostmaster Of The Day","org":"INWX GmbH","anschrift":"Prinzessinnenstr. 30, 10969 Berlin, DE","telefon":"+49.309832120","email":"hostmaster@inwx.de","verwendet":0,"nur_lesen":true,"geprueft":"NONE","kontakt_geprueft":"NOT-VERIFIED"}],"nic_handles":[{"handle":"DENIC-330-HANDLE-100001","domain":"icd360s.de","status":"OK"}],"meldungen_offen":0,"neuigkeiten":[{"id":"3752","datum":"2026-08-04","titel":"Preisanpassung","text":"Aufgrund gestiegener Kosten im Einkauf und unserer bereits sehr günstigen Preise, müssen wir die Gebühren für einige Domainendungen leider anpassen."}]}
''';

/// Verbunden, aber eine Teilabfrage ging schief: hier ist `fehler` eine LISTE.
const String _apiKontoTeilfehler = r'''
{"success":true,"verbunden":true,"konto":{"username":"kunde-muster","waehrung":"EUR"},"rechnungen":[],"rechnungen_anzahl":0,"fehler":["accounting.log: Authorization error","domain.log: Parameter value syntax error"]}
''';

void main() {
  group('get_all', () {
    test('die echte Antwort lässt sich vollständig lesen', () {
      final r = jsonDecode(_getAll) as Map<String, dynamic>;
      final data = inwxAlsMap(r['data'])!;
      expect(data['firma.firma_name'], 'INWX GmbH');
      expect(data['firma.registernummer'], 'HRB 237141 B');
      expect(data['firma.ust_id'], 'DE814537105');

      final leistungen = inwxListe(r['leistungen']);
      expect(leistungen, hasLength(1));
      expect(leistungen.first['objekt'], 'icd360s.de');
      expect(leistungen.first['tage_bis_ablauf'], 6);
      expect(leistungen.first['auto_renew'], isTrue);
    });

    test('das Konto-Passwort verlässt den Server nicht', () {
      final data = inwxAlsMap((jsonDecode(_getAll) as Map)['data'])!;
      expect(data.containsKey('api.pass'), isFalse);
      expect(data.containsKey('api.totp_secret'), isFalse);
      expect(data['api.pass_gesetzt'], '1');
    });

    test('ein leerer Datensatz kommt als LISTE an und wirft trotzdem nicht', () {
      // Genau der Fall, der den Speedtest-Bildschirm grau werden liess.
      final r = jsonDecode(_getAllLeer) as Map<String, dynamic>;
      expect(inwxAlsMap(r['data']), isNull);
      expect(inwxListe(r['leistungen']), isEmpty);
    });
  });

  group('api_status', () {
    test('Konto und Guthaben werden gelesen', () {
      final r = jsonDecode(_apiStatus) as Map<String, dynamic>;
      final k = inwxAlsMap(r['konto'])!;
      expect(k['kundennummer'], '100000');
      expect(k['zahlungsart'], 'Prepaid');

      final g = inwxAlsMap(r['guthaben'])!;
      // Prepaid mit total > 0, aber available == 0: die Auto-Verlängerung
      // hängt an 'available', nicht an 'total'. Wer 'total' anzeigt, meldet
      // Entwarnung, wo keine ist.
      expect(g['total'], 5.97);
      expect(g['available'], 0);
    });

    test('fehlt der Guthaben-Block, gibt es keine Ausnahme', () {
      final ohne = jsonDecode('{"success":true,"verbunden":true,"konto":{"username":"x"}}') as Map<String, dynamic>;
      expect(inwxAlsMap(ohne['guthaben']), isNull);
      expect(inwxAlsMap(ohne['konto'])!['username'], 'x');
    });
  });

  group('api_domains', () {
    test('Nameserver kommen als Liste, auch wenn nur eine Domain da ist', () {
      final r = jsonDecode(_apiDomains) as Map<String, dynamic>;
      final d = inwxListe(r['domains']);
      expect(d, hasLength(1));
      expect(d.first['nameserver'], isA<List<dynamic>>());
      expect((d.first['nameserver'] as List), hasLength(3));
      expect(d.first['transferlock'], isTrue);
    });

    test('der AuthInfo-Code wird nicht mitgeliefert', () {
      // Mit dem authCode ist die Domain transferierbar — er hat in unserer
      // Datenbank und erst recht nicht auf dem Bildschirm etwas verloren.
      final d = inwxListe((jsonDecode(_apiDomains) as Map)['domains']).first;
      expect(d.containsKey('authCode'), isFalse);
      expect(d.containsKey('authcode'), isFalse);
    });
  });

  group('inwxKritischsteFrist', () {
    test('nimmt die kleinste Frist einer laufenden Leistung', () {
      final f = inwxKritischsteFrist([
        {'status': 'aktiv', 'tage_bis_ablauf': 90},
        {'status': 'aktiv', 'tage_bis_ablauf': 6},
        {'status': 'aktiv', 'tage_bis_ablauf': 40},
      ]);
      expect(f, 6);
    });

    test('Gekündigtes und Abgelaufenes zählt nicht mit', () {
      final f = inwxKritischsteFrist([
        {'status': 'gekuendigt', 'tage_bis_ablauf': -400},
        {'status': 'abgelaufen', 'tage_bis_ablauf': -10},
        {'status': 'aktiv', 'tage_bis_ablauf': 50},
      ]);
      expect(f, 50);
    });

    test('ohne Ablaufdatum gibt es keine Warnung statt einer 0', () {
      expect(inwxKritischsteFrist([{'status': 'aktiv', 'tage_bis_ablauf': null}]), isNull);
      expect(inwxKritischsteFrist(const []), isNull);
    });

    test('die echte Antwort liefert 6 Tage', () {
      final r = jsonDecode(_getAll) as Map<String, dynamic>;
      expect(inwxKritischsteFrist(inwxListe(r['leistungen'])), 6);
    });
  });

  group('Tab „Rechnungen"', () {
    test('neueste zuerst, Rechnung ohne Datum hinten', () {
      final sortiert = inwxRechnungenSortiert([
        {'nummer': 'a', 'datum': '2024-03-01'},
        {'nummer': 'b', 'datum': ''},
        {'nummer': 'c', 'datum': '2026-01-15'},
        {'nummer': 'd', 'datum': '2024-12-31'},
      ]);
      expect(sortiert.map((r) => r['nummer']), ['c', 'd', 'a', 'b']);
    });

    test('leere Liste bleibt leer, Quelle bleibt unberührt', () {
      final quelle = [
        {'nummer': 'a', 'datum': '2024-03-01'},
        {'nummer': 'c', 'datum': '2026-01-15'},
      ];
      expect(inwxRechnungenSortiert([]), isEmpty);
      inwxRechnungenSortiert(quelle);
      // Die Liste im gemeinsamen Zustand darf sich nicht unter dem Konto-Tab
      // umsortieren, nur weil der Rechnungs-Tab sie anzeigt.
      expect(quelle.first['nummer'], 'a');
    });

    test('Summe zählt fehlende Beträge als 0, nicht als „keine Summe"', () {
      final liste = [
        {'brutto': 5.97, 'netto': 5.02},
        {'brutto': 11.9, 'netto': null},
        {'netto': 2.0},
      ];
      expect(inwxSummeFeld(liste, 'brutto'), closeTo(17.87, 0.001));
      expect(inwxSummeFeld(liste, 'netto'), closeTo(7.02, 0.001));
      expect(inwxSummeFeld([], 'brutto'), 0);
    });

    test('berechnet, aber noch ohne Rechnungsnummer — der reale Fall vom 11.08.2026', () {
      // Genau die Zeilen, die `domain.log` an dem Tag geliefert hat: die
      // Verlängerung kostete 4,65 netto und trug `invoice: null`. Ohne diesen
      // Filter sähe der Tab aus, als sei nie verlängert worden.
      final offen = inwxOffenePosten([
        {'zeitpunkt': '2026-08-13 09:15', 'domain': 'icd360s.de',
         'vorgang': 'REGISTRATION DATA REMINDER', 'preis': 0, 'rechnung': ''},
        {'zeitpunkt': '2026-08-11 10:15', 'domain': 'icd360s.de',
         'vorgang': 'RENEWAL SUCCESSFUL', 'preis': 4.65, 'rechnung': ''},
        {'zeitpunkt': '2026-08-11 10:15', 'domain': 'icd360s.de',
         'vorgang': 'RENEWAL REQUESTED', 'preis': 0, 'rechnung': ''},
        {'zeitpunkt': '2025-08-14 22:27', 'domain': 'icd360s.de',
         'vorgang': 'CREATE SUCCESSFUL', 'preis': 5.02, 'rechnung': '2020000001'},
      ]);
      expect(offen, hasLength(1));
      expect(offen.first['vorgang'], 'RENEWAL SUCCESSFUL');
      // ⚠️ Der Preis im Protokoll ist BRUTTO. Belegt an der Registrierung:
      // dort steht 5,02 nicht — dort steht 5,97, und 5,97 ist der
      // `afterTax`-Wert der Rechnung 2020000001 (netto 5,02). Die
      // Proformarechnung für August 2026 weist die 4,65 ebenfalls als
      // „Gesamt-Brutto" aus. Wer sie für netto hält, rechnet 19 % drauf und
      // behauptet eine Forderung, die es nicht gibt.
      expect(inwxSummeFeld(offen, 'preis'), closeTo(4.65, 0.001));
      // Kostenlose Vorgänge sind keine offenen Posten, sonst stünde das halbe
      // Protokoll als „unbezahlt" im Rechnungstab.
      expect(inwxOffenePosten([
        {'vorgang': 'UPDATE NOTIFY', 'preis': 0, 'rechnung': ''},
      ]), isEmpty);
    });

    test('Jahresüberschrift kommt aus dem ISO-Datum', () {
      final r = jsonDecode(_apiKonto) as Map<String, dynamic>;
      final erste = inwxRechnungenSortiert(inwxListe(r['rechnungen'])).first;
      expect((erste['datum'] as String).substring(0, 4), '2025');
    });
  });

  group('api_konto', () {
    test('Konto, Guthaben, Rechnungen, Bewegungen und Protokoll werden gelesen', () {
      final r = jsonDecode(_apiKonto) as Map<String, dynamic>;

      final k = inwxAlsMap(r['konto'])!;
      expect(k['kundennummer'], '100000');
      expect(k['zahlungsart'], 'Prepaid');
      expect(k['logins'], 336);

      final rechnungen = inwxListe(r['rechnungen']);
      expect(rechnungen, hasLength(1));
      // ⚠️ accounting.listInvoices liefert das Datum als blosse Zeichenkette.
      // Wer es durch strtotime()+gmdate() dreht, macht in Europe/Berlin aus
      // dem 31.08. den 30.08. — der Server reicht reine Datumsangaben deshalb
      // unveraendert durch.
      expect(rechnungen.first['datum'], '2025-08-31');
      expect(inwxDatumDeutsch(rechnungen.first['datum'] as String), '31.08.2025');
      // Der eigene Tab „Rechnungen" zeigt Summen und Jahreszahl aus genau
      // diesen Feldern — fehlt eines, bleibt der Tab still leer.
      expect(rechnungen.first['brutto'], 5.97);
      expect(rechnungen.first['netto'], 5.02);
      expect(rechnungen.first['hat_xml'], isTrue);
      // Gesamtzahl im Konto, nicht Laenge der Liste: weicht sie ab, schreibt
      // der Tab „… n insgesamt, die neuesten m sind gezeigt".
      expect(r['rechnungen_anzahl'], 1);

      final bewegungen = inwxListe(r['bewegungen']);
      expect(bewegungen, hasLength(2));
      // Einzahlung und Rechnung heben sich auf — genau deshalb ist
      // 'available' 0, obwohl 'total' 5,97 zeigt.
      final summe = bewegungen.fold<double>(0, (s, b) => s + (b['betrag'] as num).toDouble());
      expect(summe, closeTo(0, 0.001));
      expect(inwxAlsMap(r['guthaben'])!['available'], 0);

      final akt = inwxListe(r['aktivitaeten']);
      expect(akt, hasLength(2));
      expect(r['aktivitaeten_anzahl'], 19); // gezeigt wird nur ein Ausschnitt
      expect(akt.first['wer'], 'System / Registry');
      expect(akt[1]['wer'], 'kunde-muster');
      expect(akt[1]['ip'], isNotEmpty);
    });

    test('„fehler" ist mal Zeichenkette, mal Liste — beides darf nicht werfen', () {
      // Nicht verbunden -> Zeichenkette.
      final offline = jsonDecode(_apiKontoOffline) as Map<String, dynamic>;
      expect(offline['verbunden'], isFalse);
      expect(offline['fehler'], isA<String>());
      expect(offline['fehler'].toString(), contains('Login abgelehnt'));

      // Verbunden, aber Teilabfragen kaputt -> Liste.
      final teil = jsonDecode(_apiKontoTeilfehler) as Map<String, dynamic>;
      expect(teil['verbunden'], isTrue);
      expect(teil['fehler'], isA<List<dynamic>>());
      expect((teil['fehler'] as List).join(' · '), contains('domain.log'));
      // Und die fehlenden Abschnitte bleiben leer statt zu werfen.
      expect(inwxListe(teil['bewegungen']), isEmpty);
      expect(inwxListe(teil['aktivitaeten']), isEmpty);
      expect(inwxAlsMap(teil['guthaben']), isNull);
    });
  });

  group('api_dns', () {
    test('Zone, Einträge und DNSSEC werden gelesen', () {
      final r = jsonDecode(_apiDns) as Map<String, dynamic>;
      // Zonennamen sind blanke Zeichenketten, keine Objekte — inwxListe würde
      // hier eine leere Liste liefern, weil es nur Maps aufsammelt.
      expect(inwxTextListe(r['zonen']), ['icd360s.de']);
      expect(inwxListe(r['zonen']), isEmpty);

      final zone = inwxAlsMap(r['zone'])!;
      final records = inwxListe(zone['records']);
      expect(records, hasLength(5));
      expect(zone['anzahl'], 38);
      expect(inwxListe(zone['dnssec_aktiv']), hasLength(1));
      expect(zone['dnssec_abgeloest'], 4);
    });

    test('die Prüfungen schweigen, wenn die Zone in Ordnung ist', () {
      final zone = inwxAlsMap((jsonDecode(_apiDns) as Map)['zone'])!;
      final hinweise = inwxListe(zone['hinweise']);
      // Genau ein Hinweis, und zwar der übrig gebliebene ACME-Nachweis —
      // SPF, DKIM, DMARC, CAA und DNSSEC sind gesetzt und dürfen nicht
      // gemeldet werden.
      expect(hinweise, hasLength(1));
      expect(hinweise.first['stufe'], 'info');
      expect(hinweise.first['text'], contains('_acme-challenge'));
    });

    test('eine leere Zonenliste wirft nicht', () {
      final leer = jsonDecode('{"success":true,"verbunden":true,"zonen":[],"zone":null}') as Map<String, dynamic>;
      expect(inwxTextListe(leer['zonen']), isEmpty);
      expect(inwxAlsMap(leer['zone']), isNull);
    });

    test('inwxTextListe verträgt null, Unsinn und gemischte Einträge', () {
      expect(inwxTextListe(null), isEmpty);
      expect(inwxTextListe('kaputt'), isEmpty);
      expect(inwxTextListe(const {'a': 1}), isEmpty);
      expect(inwxTextListe(const ['a', null, '', 'b']), ['a', 'b']);
    });
  });

  group('Preise', () {
    test('brutto ist die Zahl, die vom Guthaben abgeht', () {
      final r = jsonDecode(_apiKontoPreise) as Map<String, dynamic>;
      final p = inwxListe(r['preise']).first;
      expect(p['verlaengerung'], 4.6529);
      // 4,6529 + 19 % = 5,54 — netto allein unterschätzt, was das Konto braucht.
      expect(p['verlaengerung_brutto'], 5.54);
      expect(inwxAlsMap(r['guthaben'])!['available'], 0);
    });

    test('ohne angekündigte Änderungen bleibt die Liste leer statt zu fehlen', () {
      final r = jsonDecode(_apiKontoPreise) as Map<String, dynamic>;
      expect(inwxListe(r['preisaenderungen']), isEmpty);
    });
  });

  group('Kontakte', () {
    test('unsere Handles sind von den INWX-Rollenkontakten unterscheidbar', () {
      final k = inwxListe((jsonDecode(_apiKontoPreise) as Map)['kontakte']);
      expect(k, hasLength(2));
      final unsere = k.where((x) => x['nur_lesen'] != true).toList();
      final fremde = k.where((x) => x['nur_lesen'] == true).toList();
      expect(unsere, hasLength(1));
      expect(fremde, hasLength(1));
      expect(fremde.first['org'], 'INWX GmbH');
      // Der Inhaber ist bestätigt, trägt aber eine Platzhalter-Rufnummer.
      expect(unsere.first['geprueft'], 'CONFIRMED');
      expect(unsere.first['telefon'], '+49.111111111111');
    });
  });

  group('inwxRecordPruefen', () {
    // ⚠️ Dieselben Fälle prüft der Selbsttest auf dem Server gegen
    // inwxRecordPruefen() in api/vereinverwaltung/inwx_lib.php. Die Regel
    // steht doppelt — hier für die sofortige Rückmeldung, dort verbindlich.
    // Läuft eine der beiden Seiten weg, fällt es hier auf.
    const zone = 'icd360s.de';

    List<String> p(String typ, String name, String inhalt, {int ttl = 300, int prio = 0}) =>
        inwxRecordPruefen(typ: typ, name: name, inhalt: inhalt, ttl: ttl, zone: zone, prio: prio);

    test('A und AAAA werden nicht verwechselt', () {
      expect(p('A', 'x.$zone', '2001:db8::1').first, contains('IPv4'));
      expect(p('AAAA', 'x.$zone', '1.2.3.4').first, contains('IPv6'));
      expect(p('A', 'x.$zone', '203.0.113.7'), isEmpty);
      expect(p('AAAA', 'x.$zone', '2001:db8::1'), isEmpty);
    });

    test('ein CNAME auf der Hauptdomain wird abgelehnt, auf einer Unterdomain nicht', () {
      // Er verdrängt MX, TXT und NS — Post und Delegierung wären sofort weg.
      expect(p('CNAME', zone, 'ziel.example.org'), isNotEmpty);
      expect(p('CNAME', 'x.$zone', 'ziel.example.org'), isEmpty);
    });

    test('der Name muss in der Zone liegen', () {
      expect(p('A', 'x.fremd.de', '1.2.3.4').first, contains('enden'));
      expect(p('A', zone, '1.2.3.4'), isEmpty);
      // Kein Teilstring-Treffer: „xicd360s.de" endet nicht auf „.icd360s.de".
      expect(p('A', 'xicd360s.de', '1.2.3.4'), isNotEmpty);
    });

    test('SOA bleibt INWX überlassen', () {
      expect(p('SOA', zone, 'irgendwas'), isNotEmpty);
    });

    test('TTL und leerer Wert', () {
      expect(p('A', 'x.$zone', '1.2.3.4', ttl: 5), isNotEmpty);
      expect(p('A', 'x.$zone', '1.2.3.4', ttl: 999999), isNotEmpty);
      expect(p('TXT', 'x.$zone', ''), isNotEmpty);
      expect(p('A', 'x.$zone', '1.2.3.4', ttl: 60), isEmpty);
    });

    test('ein unbekannter Typ bricht sofort ab, ohne Folgefehler', () {
      final f = p('QUATSCH', 'x.$zone', 'x');
      expect(f, hasLength(1));
      expect(f.first, contains('Unbekannter Eintragstyp'));
    });

    test('jeder erlaubte Typ des Servers steht auch im Client', () {
      // Spiegelt INWX_RECORD_TYPEN aus inwx_lib.php.
      expect(kInwxRecordTypen, contains('TLSA'));
      expect(kInwxRecordTypen, contains('CAA'));
      expect(kInwxRecordTypen.length, 26);
      expect(kInwxRecordTypen.toSet().length, kInwxRecordTypen.length);
    });

    test('die Verlängerungsmodi decken die drei Werte von INWX ab', () {
      expect(kInwxRenewalModi.keys.toSet(), {'AUTORENEW', 'AUTOEXPIRE', 'AUTODELETE'});
    });
  });

  group('Laufzeitband', () {
    String inTagen(int n) {
      final d = DateTime.now().add(Duration(days: n));
      return '${d.year.toString().padLeft(4, '0')}-'
             '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }

    test('inwxTageBis zählt vorwärts und rückwärts', () {
      expect(inwxTageBis(inTagen(6)), 6);
      expect(inwxTageBis(inTagen(0)), 0);
      // Abgelaufen muss negativ sein — sonst zeigt das Band „noch 0 Tage",
      // wo „seit 30 Tagen abgelaufen" stehen müsste.
      expect(inwxTageBis(inTagen(-30)), -30);
    });

    test('ohne oder mit unsinnigem Datum gibt es keine Zahl statt einer 0', () {
      expect(inwxTageBis(null), isNull);
      expect(inwxTageBis(''), isNull);
      expect(inwxTageBis('demnächst'), isNull);
    });

    test('der Balken zeigt die verbrauchte Mietzeit', () {
      // Ein Jahr Laufzeit, sechs Tage übrig -> fast voll.
      final a = inwxLaufzeitAnteil(von: inTagen(-359), bis: inTagen(6));
      expect(a, greaterThan(0.97));
      expect(a, lessThanOrEqualTo(1.0));
      // Frisch verlängert -> fast leer.
      expect(inwxLaufzeitAnteil(von: inTagen(-2), bis: inTagen(363)), lessThan(0.02));
    });

    test('ohne Anfangsdatum wird ein Jahr angenommen, nicht null geteilt', () {
      // domain.list liefert crDate mit; fehlt es doch, darf der Balken nicht
      // verschwinden und erst recht nicht werfen.
      final a = inwxLaufzeitAnteil(von: null, bis: inTagen(6));
      expect(a, greaterThan(0.97));
      expect(inwxLaufzeitAnteil(von: null, bis: null), 0);
      expect(inwxLaufzeitAnteil(von: inTagen(5), bis: inTagen(5)), 1);
    });

    test('abgelaufen bleibt bei voll, nicht über 1', () {
      expect(inwxLaufzeitAnteil(von: inTagen(-400), bis: inTagen(-35)), 1.0);
    });
  });

  group('Beschriftungen der Schreibaktionen', () {
    test('jede Aktion, die der Server protokolliert, hat einen deutschen Namen', () {
      // Spiegelt die $aktion-Werte aus api/vereinverwaltung/inwx_manage.php.
      // Fehlt eine, zeigt das Protokoll das rohe Kürzel.
      const serverSeitig = [
        'dns_anlegen', 'dns_aendern', 'dns_loeschen',
        'domain_update', 'kontakt_update', 'domain_renew', 'meldung_quittiert',
        'domain_geloescht', 'domain_hold_an', 'domain_hold_aus',
        'transfer_zugestimmt', 'transfer_abgelehnt', 'domain_uebergeben',
        'inhaberwechsel', 'authinfo_erzeugt', 'kontakt_geloescht',
        'erstattung', 'passwort_gewechselt',
      ];
      for (final a in serverSeitig) {
        expect(kInwxAktionLabel.containsKey(a), isTrue, reason: 'Beschriftung fehlt für „$a"');
      }
    });

    test('kein Label verweist auf eine Aktion, die es nicht gibt', () {
      expect(kInwxAktionLabel.length, 18);
    });
  });

  group('inwxVorgangFarbe', () {
    test('Gescheitertes hat Vorrang vor Erfolg', () {
      expect(inwxVorgangFarbe('TRANSFER FAILED'), Colors.red);
      expect(inwxVorgangFarbe('TRANSFER CANCELED'), Colors.red);
      // Zusammengesetzte Meldungen koennen beide Wörter tragen.
      expect(inwxVorgangFarbe('RENEW SUCCESSFUL BUT NOTIFY FAILED'), Colors.red);
    });

    test('die echten Vorgänge aus dem Konto bekommen sinnvolle Farben', () {
      expect(inwxVorgangFarbe('DNSSEC DEACTIVATION SUCCESSFUL'), Colors.green);
      expect(inwxVorgangFarbe('UPDATE REQUESTED'), Colors.blue);
      expect(inwxVorgangFarbe('UPDATE NOTIFY'), Colors.grey);
    });

    test('ein unbekannter Vorgang bekommt eine Farbe statt einer Ausnahme', () {
      // Das Vokabular der Registry ist offen — Unbekanntes muss durchlaufen.
      expect(inwxVorgangFarbe('IRGENDWAS GANZ NEUES'), Colors.blueGrey);
      expect(inwxVorgangFarbe(''), Colors.blueGrey);
    });
  });

  group('Katalog und Datum', () {
    test('jede Kategorie hat einen eindeutigen Schlüssel', () {
      final keys = kInwxKategorien.map((k) => k.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('„sonstige" steht am Ende und fängt Unbekanntes ab', () {
      // inwxKategorieFinden greift auf das letzte Element zurück.
      expect(kInwxKategorien.last.key, 'sonstige');
      expect(inwxKategorieFinden('gibtsnicht').key, 'sonstige');
      expect(inwxKategorieFinden(null).key, 'sonstige');
      expect(inwxKategorieFinden('ssl').label, 'SSL-Zertifikat');
    });

    test('der Katalog deckt jede Kategorie ab, die der Server kennt', () {
      // Muss mit INWX_KATEGORIEN in api/vereinverwaltung/inwx_lib.php
      // übereinstimmen — sonst zeigt die App „Sonstige" für etwas,
      // das der Server sauber gespeichert hat.
      const serverSeitig = [
        'domain', 'transfer', 'dns', 'dyndns', 'ssl', 'hosting', 'email',
        'whoisprivacy', 'registrylock', 'trustee', 'api', 'sonstige',
      ];
      expect(kInwxKategorien.map((k) => k.key).toList(), serverSeitig);
    });

    test('ISO-Datum wird deutsch, Unsinn bleibt unverändert', () {
      expect(inwxDatumDeutsch('2026-08-14'), '14.08.2026');
      expect(inwxDatumDeutsch(''), '');
      expect(inwxDatumDeutsch('demnächst'), 'demnächst');
    });
  });
}
