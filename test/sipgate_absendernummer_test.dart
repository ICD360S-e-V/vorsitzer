import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';

/// Was der Angerufene sieht, ist die eine Angabe auf diesem Bildschirm, die
/// eine Aussage über die Aussenwirkung JEDES Anrufs trifft: mit unterdrückter
/// Nummer nehmen viele Ämter und Praxen gar nicht ab und können nicht
/// zurückrufen.
///
/// Bis hierher hiess `null` schlicht „unterdrückt". Auf zwei Wegen entstand
/// dieses `null` aber, ohne dass es jemand gesagt hätte:
///
///  * aus dem Zwischenspeicher angemeldet, weil der Server beim Start nicht
///    erreichbar war — dort lagen nur SIP-ID und HA1
///  * eine Antwort eines älteren Servers, die den Schlüssel gar nicht kennt
///
/// In beiden Fällen behauptete der Bildschirm etwas Falsches, und zwar genau
/// dort, wo es jemanden dazu bringt, den Fehler bei der Verbindung zu suchen.
void main() {
  group('drei Zustände, nicht zwei', () {
    test('eine bekannte Nummer wird angezeigt', () {
      expect(
        sipgateAbsenderAnzeige(bekannt: true, nummer: '073180159736'),
        SipgateAbsenderAnzeige.nummer,
      );
    });

    test('ausdrücklich leer heisst unterdrückt', () {
      // Nur DIESER Fall darf den Satz über die Ämter nach sich ziehen.
      expect(
        sipgateAbsenderAnzeige(bekannt: true, nummer: null),
        SipgateAbsenderAnzeige.unterdrueckt,
      );
      expect(
        sipgateAbsenderAnzeige(bekannt: true, nummer: ''),
        SipgateAbsenderAnzeige.unterdrueckt,
      );
      expect(
        sipgateAbsenderAnzeige(bekannt: true, nummer: '   '),
        SipgateAbsenderAnzeige.unterdrueckt,
      );
    });

    test('nicht bekannt heisst unbekannt, nie unterdrückt', () {
      expect(
        sipgateAbsenderAnzeige(bekannt: false, nummer: null),
        SipgateAbsenderAnzeige.unbekannt,
      );
    });

    test('unbekannt schlägt sogar eine mitgegebene Nummer', () {
      // Sollte je eine Nummer neben `bekannt: false` stehen, ist sie nicht
      // belegt — dann lieber „unbekannt" als eine Zahl, auf die sich jemand
      // verlässt.
      expect(
        sipgateAbsenderAnzeige(bekannt: false, nummer: '073180159736'),
        SipgateAbsenderAnzeige.unbekannt,
      );
    });
  });

  group('konfigAusAntwort — fehlender Schlüssel ist nicht leerer Wert', () {
    Map<String, dynamic> antwort(String felder) => <String, dynamic>{
          'success': true,
          'eingerichtet': true,
          'sip_id': '1234567e0',
          'ha1': '00112233445566778899aabbccddeeff',
          ...?_extra[felder],
        };

    test('eine echte Antwort mit Nummer gilt als bekannt', () {
      final cfg = SipgateService.konfigAusAntwort(antwort('nummer'))!;
      expect(cfg.absendernummer, '073180159736');
      expect(cfg.absendernummerBekannt, isTrue);
    });

    test('ein leeres Feld gilt als bekannt und heisst unterdrückt', () {
      final cfg = SipgateService.konfigAusAntwort(antwort('leer'))!;
      expect(cfg.absendernummer, isNull);
      expect(cfg.absendernummerBekannt, isTrue);
      expect(
        sipgateAbsenderAnzeige(
          bekannt: cfg.absendernummerBekannt,
          nummer: cfg.absendernummer,
        ),
        SipgateAbsenderAnzeige.unterdrueckt,
      );
    });

    test('ein älterer Server ohne das Feld gilt als UNbekannt', () {
      // Derselbe Fall, den `sipgate_antwort_test.dart` schon festhält („darf
      // die Anmeldung nicht verhindern") — nur dass daraus bisher stillschweigend
      // „unterdrückt" wurde.
      final cfg = SipgateService.konfigAusAntwort(antwort('ohne'))!;
      expect(cfg.absendernummer, isNull);
      expect(cfg.absendernummerBekannt, isFalse);
      expect(
        sipgateAbsenderAnzeige(
          bekannt: cfg.absendernummerBekannt,
          nummer: cfg.absendernummer,
        ),
        SipgateAbsenderAnzeige.unbekannt,
      );
    });
  });

  group('der Zustand kann die Nummer wieder loswerden', () {
    test('unbekannt und unterdrückt sind unterscheidbare Zustände', () {
      const unbekannt = SipgateZustand(absendernummerBekannt: false);
      const unterdrueckt = SipgateZustand(absendernummerBekannt: true);
      expect(unbekannt.absendernummer, unterdrueckt.absendernummer); // beide null
      expect(
        sipgateAbsenderAnzeige(
          bekannt: unbekannt.absendernummerBekannt,
          nummer: unbekannt.absendernummer,
        ),
        isNot(sipgateAbsenderAnzeige(
          bekannt: unterdrueckt.absendernummerBekannt,
          nummer: unterdrueckt.absendernummer,
        )),
        reason: 'sonst wäre die ganze Unterscheidung wirkungslos',
      );
    });
  });
}

const Map<String, Map<String, dynamic>> _extra = {
  'nummer': {'absendernummer': '073180159736'},
  'leer': {'absendernummer': ''},
  'ohne': <String, dynamic>{},
};
