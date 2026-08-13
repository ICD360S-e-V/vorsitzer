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

  group('sipAusgang — die Absage im Klartext', () {
    // Der Fall vom 12.08.2026, 19:07: der Bildschirm sagte „Fehler", im
    // Verlauf stand `Unavailable`. Die echte Antwort war
    // `480 Temporarily Unavailable, Reason: Q.850;cause=19` — niemand hat
    // abgenommen. Das ist kein Fehler, das ist ein Telefonat.
    test('480 heisst: niemand hat abgenommen, nicht Fehler', () {
      final a = SipgateService.sipAusgang(480, 'Temporarily Unavailable');
      expect(a.status, 'verpasst');
      expect(a.text, contains('Niemand hat abgenommen'));
      expect(a.text, contains('480'), reason: 'Der Code muss mit, sonst muss '
          'man ihn wieder von Hand nachmessen');
    });

    test('408 und 487 zählen genauso als nicht erreicht', () {
      expect(SipgateService.sipAusgang(408, null).status, 'verpasst');
      expect(SipgateService.sipAusgang(487, null).status, 'verpasst');
    });

    test('besetzt und abgelehnt sind unterscheidbar', () {
      expect(SipgateService.sipAusgang(486, null).text, contains('Besetzt'));
      expect(SipgateService.sipAusgang(600, null).status, 'abgelehnt');
      expect(SipgateService.sipAusgang(603, null).text, contains('abgelehnt'));
    });

    test('eine nicht vergebene Rufnummer sagt das auch', () {
      expect(SipgateService.sipAusgang(404, null).text, contains('nicht vergeben'));
      expect(SipgateService.sipAusgang(484, null).text, contains('nicht vergeben'));
    });

    test('403 verweist auf Guthaben und Absendernummer', () {
      // Der Fall, den man sonst beim Netz sucht: sipgate lässt den Anruf nicht
      // zu. Der Hinweis muss sagen, WO man nachsieht.
      final a = SipgateService.sipAusgang(403, 'Forbidden');
      expect(a.status, 'fehler');
      expect(a.text, contains('Guthaben'));
    });

    test('ohne Code bleibt wenigstens der Grund stehen', () {
      expect(SipgateService.sipAusgang(null, 'Connection Error').text,
          'Connection Error');
      expect(SipgateService.sipAusgang(null, null).text, 'Unbekannter Fehler');
    });

    test('ein unbekannter Code wird durchgereicht, nicht verschluckt', () {
      // Lieber „SIP 503" als „Fehler": das eine kann man nachschlagen.
      expect(SipgateService.sipAusgang(503, 'Service Unavailable').text,
          contains('503'));
    });
  });

  group('Dauer lesbar machen', () {
    test('die Uhr für das laufende Gespräch', () {
      expect(SipgateService.dauerUhr(0), '00:00');
      expect(SipgateService.dauerUhr(7), '00:07');
      // Zwei Stellen bei den Minuten, damit die Zahl beim Wechsel von 9 auf 10
      // nicht springt und die Knöpfe daneben verrutschen.
      expect(SipgateService.dauerUhr(9 * 60), '09:00');
      expect(SipgateService.dauerUhr(10 * 60), '10:00');
      expect(SipgateService.dauerUhr(187), '03:07');
      expect(SipgateService.dauerUhr(3600), '1:00:00');
      expect(SipgateService.dauerUhr(3735), '1:02:15');
    });

    test('in Worten für Verlauf und Abschlussmeldung', () {
      // „03:07" muss man entschlüsseln, „3 Min. 7 Sek." liest man.
      expect(SipgateService.dauerLesbar(0), '0 Sek.');
      expect(SipgateService.dauerLesbar(42), '42 Sek.');
      expect(SipgateService.dauerLesbar(60), '1 Min.');
      expect(SipgateService.dauerLesbar(187), '3 Min. 7 Sek.');
      expect(SipgateService.dauerLesbar(600), '10 Min.');
      // Ab einer Stunde fallen die Sekunden weg — dort zählt sie niemand.
      expect(SipgateService.dauerLesbar(3600), '1 Std.');
      expect(SipgateService.dauerLesbar(3735), '1 Std. 2 Min.');
    });

    test('eine negative Dauer wirft nicht', () {
      // Kann durch eine Uhrzeitkorrektur des Systems mitten im Gespräch
      // entstehen; ein Absturz wäre dafür ein hoher Preis.
      expect(SipgateService.dauerUhr(-5), '00:00');
      expect(SipgateService.dauerLesbar(-5), '0 Sek.');
    });
  });

  group('Wer ruft an — die Anzeige des Anrufers', () {
    // ⚠️ Gegen das echte INVITE gebaut, nicht gegen eine Annahme. sipgate
    // schickt bei einem Anruf aus dem Telefonnetz:
    //   From: "073180159736" <sip:073180159736@sipgate.de>
    // Der Anrufer steht also im `From` — als Anzeigename UND als Benutzerteil.
    // Kein `P-Asserted-Identity`, kein `Remote-Party-ID`.

    test('eine deutsche Nummer wird lesbar getrennt', () {
      expect(SipgateService.anruferAnzeige('073180159736'), '0731 80159736');
      expect(SipgateService.anruferAnzeige('016094482053'), '0160 94482053');
    });

    test('E.164 bleibt unangetastet', () {
      expect(SipgateService.anruferAnzeige('+4971112345'), '+4971112345');
    });

    test('eine unterdrückte Nummer heisst nicht „anonymous"', () {
      // Sonst steht dort das englische Protokollwort als Name des Anrufers.
      for (final a in ['anonymous', 'Anonymous', 'unknown', 'restricted', '']) {
        expect(SipgateService.anruferAnzeige(a), 'Unbekannter Anrufer',
            reason: a);
        expect(SipgateService.anruferAnonym(a), isTrue, reason: a);
      }
      expect(SipgateService.anruferAnonym('073180159736'), isFalse);
    });

    test('zu kurz zum Trennen bleibt ungetrennt', () {
      // Falsch zu trennen ist schlimmer als nicht zu trennen.
      expect(SipgateService.anruferAnzeige('116117'), '116117');
      expect(SipgateService.anruferAnzeige('0731'), '0731');
    });

    test('anzeige: ein Name, der nur die Nummer wiederholt, zählt nicht', () {
      // Genau der Fall aus dem echten INVITE — Anzeigename == Nummer.
      const g = SipgateGespraech(
        nummer: '073180159736',
        name: '073180159736',
        eingehend: true,
        stand: SipgateGespraechStand.klingelt,
      );
      expect(g.anzeige, '0731 80159736',
          reason: 'sonst steht die ungetrennte Nummer auf dem Bildschirm');
    });

    test('anzeige: ein echter Name hat Vorrang', () {
      const g = SipgateGespraech(
        nummer: '+4971112345',
        name: 'Jobcenter Stuttgart',
        eingehend: true,
        stand: SipgateGespraechStand.klingelt,
      );
      expect(g.anzeige, 'Jobcenter Stuttgart');
    });

    test('anzeige: „anonymous" als Name wird nicht zum Namen', () {
      const g = SipgateGespraech(
        nummer: 'anonymous',
        name: 'anonymous',
        eingehend: true,
        stand: SipgateGespraechStand.klingelt,
      );
      expect(g.anzeige, 'Unbekannter Anrufer');
    });
  });

  group('Vollbild-Anrufbildschirm: geprüft, nicht angenommen', () {
    // ⚠️ Dieselbe Falle wie bei BLUETOOTH_CONNECT: `USE_FULL_SCREEN_INTENT`
    // steht seit der Fernwahl im Manifest, aber seit Android 14 bekommt sie
    // automatisch nur, wer als Telefonie- oder Weckerapp gilt, und der Play
    // Store zieht sie anderen ab. Das Tablet hat Play Services — also kein
    // theoretischer Fall.
    test('unbekannt ist NICHT dasselbe wie verboten', () {
      // Vor der ersten Abfrage und auf Nicht-Android ist der Wert `null`.
      // Daraus eine Warnung zu machen hiesse, sie immer zu zeigen — und eine
      // Warnung, die immer da steht, wird nicht gelesen.
      const vorAbfrage = SipgateZustand();
      expect(vorAbfrage.vollbildErlaubt, isNull);

      const verboten = SipgateZustand(vollbildErlaubt: false);
      const erlaubt = SipgateZustand(vollbildErlaubt: true);
      expect(verboten.vollbildErlaubt, isFalse);
      expect(erlaubt.vollbildErlaubt, isTrue);
    });

    test('der Zustand trägt beide Berechtigungen getrennt', () {
      // Bluetooth entscheidet, WO man den Anruf hört; Vollbild, OB man ihn
      // sieht. Zwei verschiedene Fehler mit zwei verschiedenen Abhilfen —
      // sie in ein Feld zu legen hiesse, dem Nutzer die falsche zu nennen.
      const z = SipgateZustand(
        bluetoothRecht: 'dauerhaft_abgelehnt',
        vollbildErlaubt: false,
      );
      expect(z.bluetoothRecht, 'dauerhaft_abgelehnt');
      expect(z.vollbildErlaubt, isFalse);
    });
  });

  group('Drei Berechtigungen, drei verschiedene Folgen', () {
    // ⚠️ Alle drei standen im Manifest und keine wurde je abgefragt.
    // „Deklariert ist nicht erteilt" — dreimal derselbe Fehler, dreimal eine
    // andere Wirkung. Sie in ein Feld zu legen hiesse, dem Nutzer die falsche
    // Abhilfe zu nennen.
    test('jede hat ein eigenes Feld und einen eigenen Zustand', () {
      const z = SipgateZustand(
        bluetoothRecht: 'abgelehnt',      // Ton im falschen Lautsprecher
        vollbildErlaubt: false,           // kein Anrufbildschirm
        benachrichtigungenErlaubt: false, // gar keine Anzeige
      );
      expect(z.bluetoothRecht, 'abgelehnt');
      expect(z.vollbildErlaubt, isFalse);
      expect(z.benachrichtigungenErlaubt, isFalse);
    });

    test('nicht abgefragt bleibt null und ist keine Warnung', () {
      // Sonst stünden auf einem frisch geöffneten Bildschirm drei Warnungen,
      // von denen keine zutrifft — und ab dann liest man keine mehr.
      const z = SipgateZustand();
      expect(z.vollbildErlaubt, isNull);
      expect(z.benachrichtigungenErlaubt, isNull);
      expect(z.bluetoothRecht, 'unbekannt');
    });
  });

  group('Anrufer-Verzeichnis: die Antwort des Servers', () {
    // Gegen die echte Antwort gebaut. Gemessen am 13.08.2026: 744 Nummern aus
    // 51 Tabellen, Nachschlagen in 0,1 ms.
    test('ein eindeutiger Treffer wird zum Namen', () {
      final a = alsMap('{"success":true,"gefunden":true,"mehrdeutig":false,'
          '"anzeige":"Rathaus-Apotheke, Ulm",'
          '"treffer":[{"bezeichnung":"Rathaus-Apotheke, Ulm",'
          '"kategorie":"apotheke","quelle":"apotheke_datenbank"}]}');
      expect(a['gefunden'], isTrue);
      expect(a['anzeige'], 'Rathaus-Apotheke, Ulm');
      expect(a['mehrdeutig'], isFalse);
    });

    test('mehrere Treffer werden als solche gekennzeichnet', () {
      // Der echte Fall: die Zentrale des Arbeitsgerichts Ulm gehört zu fünf
      // Einträgen. Einen davon auszuwählen hiesse raten — und bei einem Anruf
      // über Gesundheitsdaten ist ein falscher Name mit Zuversicht schlimmer
      // als gar keiner.
      final a = alsMap('{"success":true,"gefunden":true,"mehrdeutig":true,'
          '"anzeige":"Arbeitsgericht Ulm (+4 weitere)","treffer":[]}');
      expect(a['mehrdeutig'], isTrue);
      expect(a['anzeige'], contains('+4 weitere'));
    });

    test('nicht gefunden ist kein Fehler', () {
      // Die Nummer steht ja trotzdem auf dem Bildschirm.
      final a = alsMap('{"success":true,"gefunden":false,"treffer":[]}');
      expect(a['success'], isTrue);
      expect(a['gefunden'], isFalse);
      expect(a['anzeige'], isNull);
    });

    test('anzeige aus dem Verzeichnis gilt als echter Name', () {
      // Damit `SipgateGespraech.anzeige` ihn NICHT als „Name == Nummer"
      // verwirft und durch die Rufnummernformatierung schickt.
      const g = SipgateGespraech(
        nummer: '073180159736',
        name: 'Rathaus-Apotheke, Ulm',
        eingehend: true,
        stand: SipgateGespraechStand.klingelt,
      );
      expect(g.anzeige, 'Rathaus-Apotheke, Ulm');
    });
  });

  group('istEchterName — sonst steht die Nummer zweimal da', () {
    // ⚠️ sipgate setzt bei Anrufen aus dem Telefonnetz den Anzeigenamen GLEICH
    // der Nummer. Nachgemessen im echten INVITE:
    //   From: "073180159736" <sip:073180159736@sipgate.de>
    // Wer den blind übernimmt, schreibt in den Verlauf
    // „073180159736 · 0731 80159736" — und verdeckt damit den echten Namen,
    // sobald die Anrufererkennung ihn nachreicht.
    test('die Nummer als Anzeigename ist kein Name', () {
      expect(SipgateService.istEchterName('073180159736', '073180159736'), isFalse);
      // Auch in anderer Schreibweise: es zählen die Ziffern.
      expect(SipgateService.istEchterName('0731 80159736', '073180159736'), isFalse);
      expect(SipgateService.istEchterName('+4973180159736', '073180159736'), isFalse);
    });

    test('ein Name aus der Anrufererkennung zählt', () {
      expect(SipgateService.istEchterName('Rathaus-Apotheke, Ulm', '073180159736'), isTrue);
      expect(SipgateService.istEchterName('Ionut-Claudiu Duinea', '016094482053'), isTrue);
    });

    test('anonymous und leer sind keine Namen', () {
      expect(SipgateService.istEchterName('anonymous', 'anonym'), isFalse);
      expect(SipgateService.istEchterName('', '073180159736'), isFalse);
      expect(SipgateService.istEchterName(null, '073180159736'), isFalse);
      expect(SipgateService.istEchterName('   ', '073180159736'), isFalse);
    });

    test('ein Name MIT Ziffern bleibt ein Name', () {
      // „Praxis Dr. Meier 2" darf nicht daran scheitern, dass eine Zahl
      // darin vorkommt — verglichen werden die Ziffern ALS GANZES.
      expect(SipgateService.istEchterName('Praxis Dr. Meier 2', '073180159736'), isTrue);
      expect(SipgateService.istEchterName('Amtsgericht Ulm — Abteilung 3', '0731189-0'), isTrue);
    });
  });
}
