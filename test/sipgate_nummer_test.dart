import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

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
      expect(SipgateService.normalisieren('016094482053'), '+4916094482053');
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
