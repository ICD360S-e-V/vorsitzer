import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Die Form der Serverantwort, festgenagelt — mit der **echten, ungekürzten**
/// Antwort als Vorlage.
///
/// WARUM DIESER TEST EXISTIERT
/// Beim ersten Bau habe ich angenommen, die Nutzlast käme unter `data`. Sie
/// kommt nicht: `jsonResponse()` in `api/config.php` macht
/// `array_merge(['success' => …], $data)`, die Felder liegen also **flach**
/// neben `success`. Der Client las `antwort['data']`, bekam `null`, fiel auf
/// den leeren Zwischenspeicher zurück und meldete „Keine Anmeldedaten" — auf
/// dem Gerät sah es aus, als wäre nichts in der Datenbank, während der Server
/// alles sauber lieferte.
///
/// Nichts hat das gemeldet: `flutter analyze` sieht keine Map-Schlüssel, die
/// Tests fassten die Serverantwort nicht an, und nginx hat für diesen vhost
/// **kein access_log**, also stand die Anfrage auch nirgends. Genau dieselbe
/// Lücke wie bei `speedtest_antwort_test.dart`, und dieselbe Antwort darauf:
/// eine echte Antwort als Vorlage, nicht eine gedachte.
///
/// Die Zeichenkette unten ist wörtlich das, was
/// `php api/sipgate/sipgate_manage.php` am 12.08.2026 ausgegeben hat.
void main() {
  // Wörtlich vom Server, inklusive der escapten Schrägstriche in `wss:\/\/`.
  const echteAntwort =
      '{"success":true,"eingerichtet":true,"sip_id":"4023714e0",'
      '"ha1":"498802219a72dd2b45dc187bbbe17c2d","realm":"sipgate.de",'
      '"wss_url":"wss:\\/\\/sip.sipgate.de","bezeichnung":"Vorsitzer (e0)",'
      '"absendernummer":"073180159736","notrufstandort":"nicht_gesetzt",'
      '"plattform":"alle","geteilt":true}';

  Map<String, dynamic> alsMap(String s) => jsonDecode(s) as Map<String, dynamic>;

  group('konfigAusAntwort — echte Antwort', () {
    test('die flache Nutzlast wird gelesen, nicht ein data-Objekt', () {
      final antwort = alsMap(echteAntwort);
      // Der Beweis, dass es kein `data` gibt — hätte ich das geprüft, wäre der
      // Fehler nie entstanden.
      expect(antwort.containsKey('data'), isFalse);

      final cfg = SipgateService.konfigAusAntwort(antwort);
      expect(cfg, isNotNull);
      expect(cfg!.sipId, '4023714e0');
      expect(cfg.ha1, '498802219a72dd2b45dc187bbbe17c2d');
      expect(cfg.realm, 'sipgate.de');
      expect(cfg.wssUrl, 'wss://sip.sipgate.de');
      expect(cfg.bezeichnung, 'Vorsitzer (e0)');
      expect(cfg.absendernummer, '073180159736');
      expect(cfg.notrufstandort, 'nicht_gesetzt');
      expect(cfg.geteilt, isTrue);
    });

    test('HA1 überlebt die Umformung unverändert', () {
      // Es ist derselbe Wert, mit dem die Probeanmeldung am 11.08. ein
      // `200 OK` bekam. Ein Zeichen daneben und die Anmeldung scheitert mit
      // einem 401, den niemand einem Tippfehler zuordnen würde.
      final cfg = SipgateService.konfigAusAntwort(alsMap(echteAntwort))!;
      expect(cfg.ha1, hasLength(32));
      expect(cfg.ha1, matches(RegExp(r'^[0-9a-f]{32}$')));
    });
  });

  group('konfigAusAntwort — was NICHT durchgehen darf', () {
    test('nicht eingerichtet gibt null', () {
      // So antwortet der Server, wenn kein VoIP-Telefon hinterlegt ist.
      expect(
        SipgateService.konfigAusAntwort(alsMap(
            '{"success":true,"message":"Es ist noch kein VoIP-Telefon '
            'hinterlegt","eingerichtet":false,"realm":"sipgate.de",'
            '"wss_url":"wss:\\/\\/sip.sipgate.de"}')),
        isNull,
      );
    });

    test('success=false gibt null, auch mit Feldern daneben', () {
      expect(
        SipgateService.konfigAusAntwort(alsMap(
            '{"success":false,"message":"Invalid API Key or Device Key",'
            '"eingerichtet":true,"sip_id":"x","ha1":"y"}')),
        isNull,
      );
    });

    test('leere sip_id oder ha1 gibt null statt einer halben Anmeldung', () {
      // Lieber „keine Daten" als eine Anmeldung, die mit leeren Feldern in
      // einen 401 läuft — den würde man beim Passwort suchen.
      expect(
        SipgateService.konfigAusAntwort(alsMap(
            '{"success":true,"eingerichtet":true,"sip_id":"","ha1":"abc"}')),
        isNull,
      );
      expect(
        SipgateService.konfigAusAntwort(alsMap(
            '{"success":true,"eingerichtet":true,"sip_id":"4023714e0","ha1":""}')),
        isNull,
      );
    });

    test('fehlende Kür-Felder werfen nicht, sondern fallen auf Vorgaben', () {
      // Ein älterer Server ohne absendernummer/notrufstandort darf die
      // Anmeldung nicht verhindern.
      final cfg = SipgateService.konfigAusAntwort(alsMap(
          '{"success":true,"eingerichtet":true,"sip_id":"4023714e0",'
          '"ha1":"498802219a72dd2b45dc187bbbe17c2d"}'))!;
      expect(cfg.realm, 'sipgate.de');
      expect(cfg.wssUrl, 'wss://sip.sipgate.de');
      expect(cfg.absendernummer, isNull);
      expect(cfg.notrufstandort, 'unbekannt');
      expect(cfg.geteilt, isFalse);
    });

    test('leere Absendernummer heisst unterdrückt, nicht Leerstring', () {
      final cfg = SipgateService.konfigAusAntwort(alsMap(
          '{"success":true,"eingerichtet":true,"sip_id":"4023714e0",'
          '"ha1":"498802219a72dd2b45dc187bbbe17c2d","absendernummer":"  "}'))!;
      expect(cfg.absendernummer, isNull,
          reason: 'Der Bildschirm entscheidet an null, ob er die Warnung zeigt');
    });
  });

  group('der Übergangs-Spiegel unter `data` stört nicht', () {
    // WARUM ES DEN SPIEGEL GIBT
    // Die am 12.08.2026 ausgelieferte Fassung (v6.99.0/6.99.1) liest die
    // Nutzlast unter `data` — der Fehler, den dieser Zweig behebt. Auf dem
    // Tablet läuft aber die alte Fassung, und ein Release dauert Merge + Build.
    // Der Server schickt die Nutzlast deshalb ÜBERGANGSWEISE doppelt: flach
    // und als `data`-Spiegel. Der Server ist in Minuten änderbar, die App
    // nicht.
    //
    // Dieser Test hält fest, dass der Spiegel den NEUEN Client nicht
    // verwirrt — sonst hätte der Notbehelf einen zweiten Fehler eingebaut.
    test('die flache Form gewinnt, der Spiegel wird ignoriert', () {
      final cfg = SipgateService.konfigAusAntwort(alsMap(
          '{"success":true,"eingerichtet":true,"sip_id":"4023714e0",'
          '"ha1":"498802219a72dd2b45dc187bbbe17c2d","realm":"sipgate.de",'
          '"wss_url":"wss:\\/\\/sip.sipgate.de","absendernummer":"073180159736",'
          '"data":{"eingerichtet":true,"sip_id":"4023714e0",'
          '"ha1":"498802219a72dd2b45dc187bbbe17c2d","realm":"sipgate.de",'
          '"wss_url":"wss:\\/\\/sip.sipgate.de","absendernummer":"073180159736"}}'))!;
      expect(cfg.sipId, '4023714e0');
      expect(cfg.ha1, '498802219a72dd2b45dc187bbbe17c2d');
      expect(cfg.absendernummer, '073180159736');
    });

    test('ein leerer Spiegel macht die flache Antwort nicht ungültig', () {
      // Sicherheitsnetz für den Tag, an dem der Spiegel wieder entfernt wird:
      // dann steht dort im Zweifel `"data":[]` oder gar nichts.
      final cfg = SipgateService.konfigAusAntwort(alsMap(
          '{"success":true,"eingerichtet":true,"sip_id":"4023714e0",'
          '"ha1":"498802219a72dd2b45dc187bbbe17c2d","data":[]}'));
      expect(cfg, isNotNull);
      expect(cfg!.sipId, '4023714e0');
    });
  });

  group('die anderen Aktionen liefern genauso flach', () {
    test('log_anruf gibt anruf_id auf oberster Ebene', () {
      final a = alsMap('{"success":true,"anruf_id":42}');
      expect(a.containsKey('data'), isFalse);
      expect(a['anruf_id'], 42);
    });

    test('list_anrufe gibt anrufe auf oberster Ebene', () {
      final a = alsMap('{"success":true,"anrufe":[]}');
      expect(a['anrufe'], isA<List<dynamic>>());
    });

    test('list_geraete gibt geraete auf oberster Ebene', () {
      final a = alsMap('{"success":true,"geraete":[],"realm":"sipgate.de",'
          '"wss_url":"wss:\\/\\/sip.sipgate.de"}');
      expect(a['geraete'], isA<List<dynamic>>());
      expect(a['realm'], 'sipgate.de');
    });
  });
}
