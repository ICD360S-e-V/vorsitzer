import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';
import 'package:icd360sev_vorsitzer/services/voice_call_service.dart';

/// Rufnummern und Notrufsperre für die sipgate-Telefonie.
///
/// WARUM DAS EIN EIGENER TEST IST
/// Dieselbe Umschreibung steht ein zweites Mal in
/// `api/sipgate/sipgate_lib.php` (`sipgateNummerE164`), weil der Server das
/// protokolliert, was gewählt wurde. Laufen die beiden auseinander, steht im
/// Verlauf eine andere Nummer als im Gespräch — und das merkt niemand, bis
/// jemand einem Anruf nachgehen will. Die Fälle hier sind zeichengleich mit
/// `sipgateSelbsttest()`.
void main() {
  group('SipgateService.normalisieren', () {
    test('deutsche Schreibweisen werden zu E.164', () {
      // Genau die Fälle aus sipgateSelbsttest() auf dem Server.
      expect(SipgateService.normalisieren('0711 / 123 456-78'), '+4971112345678');
      expect(SipgateService.normalisieren('+49 711 123456'), '+49711123456');
      expect(SipgateService.normalisieren('004971112345'), '+4971112345');
      expect(SipgateService.normalisieren('016087654321'), '+4916087654321');
    });

    test('Kurznummern bleiben unangetastet', () {
      // ⚠️ Der eigentliche Grund für diesen Test: aus 116117 darf NIEMALS
      // +49116117 werden. Das ist keine wählbare Rufnummer, und der ärztliche
      // Bereitschaftsdienst ist genau die Nummer, die im Ernstfall gehen muss.
      expect(SipgateService.normalisieren('116117'), '116117');
      expect(SipgateService.normalisieren('115'), '115');
      // Sechs Stellen mit führender Null sind noch keine Ortsnummer.
      expect(SipgateService.normalisieren('012345'), '012345');
    });

    test('Steuercodes gehen unverändert durch', () {
      // *31# unterdrückt bei sipgate die Absendernummer für einen Anruf.
      expect(SipgateService.normalisieren('*31#'), '*31#');
      expect(SipgateService.normalisieren('#43#'), '#43#');
    });

    test('nichts Wählbares gibt null', () {
      expect(SipgateService.normalisieren(''), isNull);
      expect(SipgateService.normalisieren('   '), isNull);
      expect(SipgateService.normalisieren('Mo–Fr'), isNull);
      expect(SipgateService.normalisieren('12'), isNull); // zu kurz
    });

    test('Beiwerk aus Behördenkarten fällt weg', () {
      expect(SipgateService.normalisieren('Tel. 0711 123456'), '+49711123456');
      expect(SipgateService.normalisieren('0711123456 (Zentrale)'), '+49711123456');
    });
  });

  group('SipgateService.istNotruf', () {
    test('die vier echten Notrufe werden erkannt', () {
      for (final n in ['110', '112', '911', '999']) {
        expect(SipgateService.istNotruf(n), isTrue, reason: n);
      }
    });

    test('115 und 116117 sind keine Notrufe', () {
      // Behördennummer und ärztlicher Bereitschaftsdienst. Sie über sipgate zu
      // wählen ist harmlos und soll gehen.
      expect(SipgateService.istNotruf('115'), isFalse);
      expect(SipgateService.istNotruf('116117'), isFalse);
    });

    test('eine Nummer mit Vorwahl ist kein Notruf', () {
      // +49110 ist eine gewöhnliche Rufnummer — die Vorwahl macht sie dazu.
      expect(SipgateService.istNotruf('+49110'), isFalse);
      expect(SipgateService.istNotruf('0110'), isFalse);
    });
  });

  group('Gesprächszustand', () {
    test('Dauer ist 0, solange nicht verbunden', () {
      const g = SipgateGespraech(
        nummer: '+4971112345',
        eingehend: false,
        stand: SipgateGespraechStand.waehlt,
      );
      expect(g.dauerSekunden, 0);
    });

    test('kopie() behält Nummer, Name und Richtung', () {
      const g = SipgateGespraech(
        nummer: '+4971112345',
        name: 'Jobcenter',
        eingehend: true,
        stand: SipgateGespraechStand.klingelt,
      );
      final k = g.kopie(stand: SipgateGespraechStand.verbunden, stumm: true);
      expect(k.nummer, g.nummer);
      expect(k.name, 'Jobcenter');
      expect(k.eingehend, isTrue);
      expect(k.stand, SipgateGespraechStand.verbunden);
      expect(k.stumm, isTrue);
    });
  });

  group('Kein fremder STUN-Server', () {
    // WARUM DAS GEPRÜFT WIRD
    // `UaSettings.iceServers` in sip_ua ist mit einem öffentlichen STUN-Server
    // von Google vorbelegt. Wer das Feld nicht ersetzt, verrät bei jedem Anruf
    // an einen Fremden, wann von welcher Adresse telefoniert wird — und merkt
    // nichts davon, weil das Gespräch trotzdem funktioniert. Deshalb hängt es
    // hier an einem Test und nicht an einem Kommentar.

    test('iceListeBauen nimmt nur, was der eigene Server liefert', () {
      final liste = SipgateService.iceListeBauen(<String, dynamic>{
        'uris': <String>[
          'stun:turn.icd360s.de:3478',
          'turn:turn.icd360s.de:3478?transport=udp',
          'turns:turn.icd360s.de:5349?transport=tcp',
        ],
        'username': 'abc',
        'password': 'geheim',
      });

      expect(liste.length, 3);
      // STUN ohne Zugangsdaten — die braucht es dort nicht, und was nicht
      // gebraucht wird, wird auch nicht verschickt.
      expect(liste[0], {'urls': 'stun:turn.icd360s.de:3478'});
      expect(liste[1]['username'], 'abc');
      expect(liste[1]['credential'], 'geheim');
      expect(liste[2]['urls'], contains('turns:'));

      // Jeder Eintrag zeigt auf unsere eigene Anlage.
      for (final e in liste) {
        expect(e['urls'], contains('turn.icd360s.de'));
      }
    });

    test('urls ist NIE eine Liste, auch nicht über sipgate', () {
      // Dieselbe Zusage wie in test/ice_server_form_test.dart, hier für den
      // sipgate-Weg. `sip_ua` benutzt dieselbe flutter_webrtc-Brücke, deren
      // Desktop-Seite aus einer Liste nur die LETZTE URI behält.
      final liste = SipgateService.iceListeBauen(<String, dynamic>{
        'uris': <String>[
          'turn:turn.icd360s.de:3478?transport=udp',
          'turn:turn.icd360s.de:3478?transport=tcp',
        ],
        'username': 'abc',
        'password': 'geheim',
      });
      for (final e in liste) {
        expect(e['urls'], isA<String>());
      }
    });

    test('die Obergrenze der nativen Seite wird eingehalten', () {
      // Die native Seite schreibt ice_servers[i] ohne Bereichsprüfung. Weil
      // iceListeBauen an iceServerEintraege delegiert, gilt die Grenze hier
      // mit — dieser Test hält genau das fest, damit ein späteres
      // „vereinfachen" nicht die Delegation entfernt.
      final liste = SipgateService.iceListeBauen(<String, dynamic>{
        'uris': List<String>.generate(
            20, (i) => 'turn:turn.icd360s.de:3478?transport=udp&n=\$i'),
        'username': 'abc',
        'password': 'geheim',
      });
      expect(liste.length, lessThanOrEqualTo(VoiceCallService.maxIceServer));
    });

    test('ohne eigene Zugangsdaten bleibt die Liste LEER, nicht voreingestellt', () {
      // Der entscheidende Fall: fällt unser coturn aus, darf NICHT der
      // Standard von sip_ua einspringen. Leer heißt „kein STUN", und sipgate
      // liefert im SDP einen öffentlichen Host-Kandidaten — das Gespräch kommt
      // meist auch so zustande.
      expect(SipgateService.iceListeBauen(null), isEmpty);
      expect(SipgateService.iceListeBauen(<String, dynamic>{}), isEmpty);
      expect(SipgateService.iceListeBauen(<String, dynamic>{'uris': <String>[]}), isEmpty);
    });

    test('in lib/ steht kein fremder STUN-Server im Code', () {
      final verboten = RegExp(
        r'stun\.l\.google|stun\d?\.google|19302|stun\.services\.mozilla|'
        r'stunprotocol\.org|stun\.cloudflare|global\.stun\.twilio',
        caseSensitive: false,
      );
      final treffer = <String>[];
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final zeilen = f.readAsLinesSync();
        for (var i = 0; i < zeilen.length; i++) {
          final z = zeilen[i];
          // Kommentare dürfen den Namen nennen — dort steht ja gerade die
          // Begründung, warum er nicht benutzt wird.
          final rein = z.trimLeft();
          if (rein.startsWith('//') || rein.startsWith('*')) continue;
          if (verboten.hasMatch(z)) treffer.add('${f.path}:${i + 1}: ${z.trim()}');
        }
      }
      expect(treffer, isEmpty,
          reason: 'Fremder STUN-Server im Code:\n${treffer.join('\n')}');
    });

    test('jede UaSettings im Projekt setzt iceServers selbst', () {
      // Ein zweites `UaSettings()` ohne eigene Liste holt den Google-Standard
      // zurück, ohne dass irgendwo etwas rot wird.
      var bauten = 0;
      var zuweisungen = 0;
      for (final f in Directory('lib').listSync(recursive: true)) {
        if (f is! File || !f.path.endsWith('.dart')) continue;
        final t = f.readAsStringSync();
        bauten += RegExp(r'UaSettings\s*\(').allMatches(t).length;
        zuweisungen += RegExp(r'\.\.?iceServers\s*=').allMatches(t).length;
      }
      expect(bauten, greaterThan(0), reason: 'UaSettings nicht mehr gefunden — Test veraltet?');
      expect(zuweisungen, greaterThanOrEqualTo(bauten),
          reason: 'Es gibt $bauten UaSettings, aber nur $zuweisungen iceServers-Zuweisungen '
              '— eine davon benutzt den Google-Standard von sip_ua.');
    });
  });

  group('VoIP nur auf dem Tablet', () {
    // Die Tests laufen auf dem Linux-Host, also auf genau der Plattform, die
    // sich NICHT registrieren soll. Das macht die Festlegung hier prüfbar,
    // ohne ein Gerät zu brauchen.
    setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

    test('plattformFaehig ist außerhalb von Android false', () {
      expect(
        SipgateService().plattformFaehig,
        isFalse,
        reason: 'Der Rechner soll sich nicht bei sipgate anmelden — er schickt '
            'den Auftrag ans Tablet. Zwei Registrierungen auf derselben SIP-ID '
            'wären Parallelruf an einem Gerät ohne Headset.',
      );
    });

    test('die Automatik ist außerhalb von Android aus', () async {
      // Auf Android ist die Vorgabe an (die Registrierung IST die Funktion),
      // hier muss sie aus sein — sonst würde der Rechner beim Start doch
      // versuchen, sich anzumelden.
      expect(await SipgateService().autoAktiv(), isFalse);
    });

    test('ein gespeicherter Wert schlägt die Vorgabe', () async {
      SharedPreferences.setMockInitialValues(
          <String, Object>{'sipgate_auto_registrieren': true});
      expect(await SipgateService().autoAktiv(), isTrue,
          reason: 'Die Vorgabe darf eine bewusste Wahl nicht überschreiben');
    });

    test('der Wahlweg vom Rechner ist standardmäßig die SIM', () async {
      // Bewusst NICHT sipgate: das wäre ein anderer Anschluss mit einer
      // anderen Absendernummer und anderen Kosten, still umgestellt.
      expect(await SipgateService.wahlwegFuerRechner(), 'sim');
      await SipgateService.setWahlwegFuerRechner('sipgate');
      expect(await SipgateService.wahlwegFuerRechner(), 'sipgate');
      // Unsinn fällt auf die SIM zurück, statt in die Datenbank zu wandern.
      await SipgateService.setWahlwegFuerRechner('quatsch');
      expect(await SipgateService.wahlwegFuerRechner(), 'sim');
    });
  });

  group('Notrufliste bleibt in allen Kopien gleich', () {
    // Die Liste steht fünfmal im Projekt: PhoneCallService, MainActivity,
    // IcdAnrufPlugin, anruf/queue.php und hier. Die PHP-Seite kann dieser Test
    // nicht sehen (Serverdateien liegen nicht im Repo), die Dart- und
    // Kotlin-Seite schon — und genau dort ist eine Abweichung am
    // wahrscheinlichsten, weil die Dateien nichts voneinander wissen.
    final erwartet = {'110', '112', '911', '999'};

    // Der Abschluss wird mitgegeben, weil Dart die Menge in `{…}` schreibt und
    // Kotlin sie inline als `setOf(…)` — ein gemeinsamer Trenner wie `;` gibt
    // es nicht, und ein Fenster fester Länge würde die nächste Zahl im Text
    // mitlesen.
    Set<String> ausQuelle(String pfad, String anker, String abschluss) {
      final datei = File(pfad);
      expect(datei.existsSync(), isTrue, reason: '$pfad fehlt');
      final text = datei.readAsStringSync();
      final start = text.indexOf(anker);
      expect(start, greaterThan(-1), reason: '„$anker" nicht in $pfad gefunden');
      final ende = text.indexOf(abschluss, start);
      expect(ende, greaterThan(start), reason: '„$abschluss" fehlt nach $anker in $pfad');
      final abschnitt = text.substring(start, ende);
      return RegExp(r'''["'](\d{3,6})["']''')
          .allMatches(abschnitt)
          .map((m) => m.group(1)!)
          .toSet();
    }

    test('PhoneCallService trägt dieselben vier Nummern', () {
      expect(ausQuelle('lib/services/phone_call_service.dart', '_notrufe =', '}'), erwartet);
    });

    test('SipgateService trägt dieselben vier Nummern', () {
      expect(ausQuelle('lib/services/sipgate_service.dart', '_notrufe =', '}'), erwartet);
    });

    test('IcdAnrufPlugin trägt dieselben vier Nummern', () {
      expect(
        ausQuelle(
          'packages/icd_anruf/android/src/main/kotlin/de/icd360sev/icd_anruf/IcdAnrufPlugin.kt',
          'setOf("110"',
          ')',
        ),
        erwartet,
      );
    });
  });
}
