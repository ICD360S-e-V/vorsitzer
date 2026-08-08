import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/screens/inwx_screen.dart';

/// Echte Antworten von api/vereinverwaltung/inwx_manage.php, aufgezeichnet
/// am 08.08.2026 gegen das laufende INWX-Konto (Kundennummer 235519).
///
/// ⚠️ Der Sinn ist NICHT, die Zahlen zu prüfen, sondern die FORM. PHP kennt
/// nur einen Array-Typ: `['a'=>1]` kodiert `json_encode` als Objekt, `[]`
/// dagegen als Liste. Ein `as Map` auf einer Liste liefert nicht null,
/// sondern wirft — genau daran blieb der Speedtest-Bildschirm am 05.08.2026
/// in der Produktion beim Aufbau hängen und zeigte nur eine graue Fläche.
/// Weder `flutter analyze` noch die Widget-Tests sehen so etwas, weil keiner
/// davon die echte Serverantwort anfasst.

const String _getAll = r'''
{"success":true,"data":{"api.doku_url":"https://account.inwx.de/de/help/apidoc","api.endpoint":"https://api.domrobot.com/jsonrpc/","api.user":"icd360sev","firma.akkreditierung":"ICANN, DENIC, EURid, SWITCH, ES-NIC","firma.billing_email":"billing@inwx.com","firma.branche":"Domain-Registrar / DNS / Hosting","firma.datenschutz":"IITR Datenschutz GmbH, Marienplatz 2, 80331 Muenchen — email@iitr.de","firma.firma_name":"INWX GmbH","firma.geschaeftsfuehrer":"Mario Peschel","firma.hauptzentrale_email":"info@inwx.com","firma.hauptzentrale_fax":"+49 30 983 212 90","firma.hauptzentrale_land":"Deutschland","firma.hauptzentrale_ort":"Berlin","firma.hauptzentrale_plz":"10969","firma.hauptzentrale_strasse":"Prinzessinnenstr. 30","firma.hauptzentrale_telefon":"+49 30 983 21 20","firma.impressum_url":"https://www.inwx.de/de/aboutus/imprint","firma.quelle":"Impressum inwx.de, abgerufen 08.08.2026","firma.rechtsform":"GmbH","firma.registergericht":"Amtsgericht Berlin-Charlottenburg","firma.registernummer":"HRB 237141 B","firma.support_email":"support@inwx.com","firma.support_telefon":"+49 30 983 21 21 21","firma.ust_id":"DE814537105","firma.website":"https://www.inwx.de","zugang.url":"https://www.inwx.de/de/customer/signin","api.pass_gesetzt":"1","api.totp_gesetzt":""},"leistungen":[{"id":1,"kategorie":"domain","bezeichnung":"Domain icd360s.de","objekt":"icd360s.de","status":"aktiv","kosten":"","intervall":"jaehrlich","beginn_datum":"2025-08-14","ablauf_datum":"2026-08-14","tage_bis_ablauf":6,"auto_renew":true,"notiz":"Aus INWX-Konto übernommen.\nNameserver: ns.inwx.de, ns2.inwx.de, ns3.inwx.eu\nTransfer-Lock: ja","quelle":"api"}]}
''';

const String _apiStatus = r'''
{"success":true,"verbunden":true,"konto":{"username":"icd360sev","kundennummer":"235519","org":"ICD360S e.V","email":"inwx@icd360s.de","zahlungsart":"Prepaid","waehrung":"EUR","zwei_fa":false,"renewal_mode":"AUTORENEW","letzter_login":"2026-08-08"},"guthaben":{"total":5.97,"available":0,"locked":0,"credit_limit":0,"waehrung":"EUR"}}
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
{"success":true,"verbunden":true,"konto":{"username":"icd360sev","kundennummer":"235519","konto_id":"312509","org":"ICD360S e.V","inhaber":"Ionut-Claudiu Duinea","anschrift":"Elsa-Brandstrom-str. 13, 89231 Neu-Ulm, DE","telefon":"+49.111111111111","fax":"","website":"https://icd360s.de","email":"inwx@icd360s.de","email_rechnung":"inwx@icd360s.de","zahlungsart":"Prepaid","waehrung":"EUR","ust_satz":"19.00","zwei_fa":false,"renewal_mode":"AUTORENEW","rechnung_pdf":true,"sammelrechnung":false,"reseller":"no","kunde_seit":"2025-08-14","letzter_login":"2026-08-08 11:39","logins":336,"letzte_ip":"2a0a:c980:4:24::","service_pin":"868868"},"guthaben":{"total":5.97,"available":0,"locked":0,"credit_limit":0,"waehrung":"EUR"},"rechnungen":[{"nummer":"2025073725","datum":"2025-08-31","brutto":5.97,"netto":5.02,"art":"Invoice","hat_xml":true}],"rechnungen_anzahl":1,"bewegungen":[{"zeitpunkt":"2025-08-31 02:00","betrag":-5.97,"art":"Invoice","details":"2025073725","erstattbar":false},{"zeitpunkt":"2025-08-14 22:26","betrag":5.97,"art":"Payment","details":"Credit card","erstattbar":true}],"bewegungen_anzahl":2,"bewegungen_seit":"2025-08-14","aktivitaeten":[{"zeitpunkt":"2025-10-24 22:11","domain":"icd360s.de","vorgang":"UPDATE NOTIFY","preis":0,"rechnung":"","wer":"System / Registry","ip":"","text":"DNSSEC update successful","log_id":"48922235"},{"zeitpunkt":"2025-10-24 22:05","domain":"icd360s.de","vorgang":"DNSSEC DEACTIVATION REQUESTED","preis":0,"rechnung":"","wer":"icd360sev","ip":"2a0a:c980:4:18::","text":"","log_id":"48922217"}],"aktivitaeten_anzahl":19,"aktivitaeten_summe":5.97}
''';

/// Nicht verbunden: hier ist `fehler` eine ZEICHENKETTE.
const String _apiKontoOffline = r'''
{"success":true,"verbunden":false,"fehler":"Login abgelehnt: Authorization error (Code 2200)"}
''';

/// Echte `api_dns`-Antwort, auf 5 der 38 Einträge gekürzt (je einer pro
/// geprüfter Eigenschaft), Schlüsselmaterial gekürzt.
const String _apiDns = r'''
{"success":true,"verbunden":true,"zonen":["icd360s.de"],"zone":{"domain":"icd360s.de","ro_id":"1307445","typ":"MASTER","anzahl":38,"records":[{"id":"2203163207","name":"icd360s.de","typ":"A","inhalt":"51.195.4.85","ttl":300,"prio":0},{"id":"2227312181","name":"icd360s.de","typ":"AAAA","inhalt":"2001:41d0:700:3ff0::1","ttl":300,"prio":0},{"id":"2108639387","name":"icd360s.de","typ":"CAA","inhalt":"0 issue \"letsencrypt.org\"","ttl":300,"prio":0},{"id":"2109129724","name":"icd360s.de","typ":"MX","inhalt":"mail.icd360s.de","ttl":300,"prio":10},{"id":"2111981415","name":"icd360s.de","typ":"TXT","inhalt":"v=spf1 ip4:135.125.128.33 -all","ttl":3600,"prio":0}],"dnssec_aktiv":[{"key_tag":"5756","algorithmus":"13","flags":"257","angelegt":"2025-10-24 20:05:18"}],"dnssec_abgeloest":4,"hinweise":[{"stufe":"info","text":"Übrig gebliebener ACME-Nachweis: _acme-challenge.mail.icd360s.de — wird nur während der Zertifikatsausstellung gebraucht."}]}}
''';

/// Der Preis- und Kontaktteil von `api_konto`, echt.
const String _apiKontoPreise = r'''
{"success":true,"verbunden":true,"guthaben":{"total":5.97,"available":0,"locked":0,"credit_limit":0,"waehrung":"EUR"},"tlds":["de"],"preise":[{"tld":"de","waehrung":"EUR","verlaengerung":4.6529,"verlaengerung_brutto":5.54,"ust_satz":19,"neuanlage":5.9738,"transfer":4.6529,"wiederherstellung":28.4529,"zeitraum":"1"}],"preisaenderungen":[],"kontakte":[{"id":"893573","typ":"ORG","name":"Ionut-Claudiu Duinea","org":"ICD360S e.V i.G","anschrift":"Elsa-Brandstrom-str. 13, 89231 Neu-Ulm, DE","telefon":"+49.111111111111","email":"verein@i3c6d0s.com","verwendet":1,"nur_lesen":false,"geprueft":"CONFIRMED","kontakt_geprueft":"NOT-VERIFIED"},{"id":"1","typ":"ROLE","name":"Hostmaster Of The Day","org":"INWX GmbH","anschrift":"Prinzessinnenstr. 30, 10969 Berlin, DE","telefon":"+49.309832120","email":"hostmaster@inwx.de","verwendet":0,"nur_lesen":true,"geprueft":"NONE","kontakt_geprueft":"NOT-VERIFIED"}],"nic_handles":[{"handle":"DENIC-330-HANDLE-893573","domain":"icd360s.de","status":"OK"}],"meldungen_offen":0,"neuigkeiten":[{"id":"3752","datum":"2026-08-04","titel":"Preisanpassung","text":"Aufgrund gestiegener Kosten im Einkauf und unserer bereits sehr günstigen Preise, müssen wir die Gebühren für einige Domainendungen leider anpassen."}]}
''';

/// Verbunden, aber eine Teilabfrage ging schief: hier ist `fehler` eine LISTE.
const String _apiKontoTeilfehler = r'''
{"success":true,"verbunden":true,"konto":{"username":"icd360sev","waehrung":"EUR"},"rechnungen":[],"rechnungen_anzahl":0,"fehler":["accounting.log: Authorization error","domain.log: Parameter value syntax error"]}
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
      expect(k['kundennummer'], '235519');
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

  group('api_konto', () {
    test('Konto, Guthaben, Rechnungen, Bewegungen und Protokoll werden gelesen', () {
      final r = jsonDecode(_apiKonto) as Map<String, dynamic>;

      final k = inwxAlsMap(r['konto'])!;
      expect(k['kundennummer'], '235519');
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
      expect(akt[1]['wer'], 'icd360sev');
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
