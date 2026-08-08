import 'dart:convert';

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
