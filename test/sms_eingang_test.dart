import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/sms_service.dart';

/// Die Übersetzung der Plattform-Antwort in Objekte ist die Stelle, an der
/// sich ein Tippfehler im Schlüsselnamen als „keine neuen Nachrichten"
/// tarnt — und niemand merkt es, weil ein leerer Posteingang völlig normal
/// aussieht. Deshalb hängt der ganze Lesepfad an diesen Fällen.
void main() {
  Map<String, dynamic> antwort({
    String lage = 'bereit',
    List<Map<String, Object?>> nachrichten = const [],
    bool abgeschnitten = false,
    String? fehler,
  }) =>
      {
        'lage': lage,
        'nachrichten': nachrichten,
        'abgeschnitten': abgeschnitten,
        if (fehler != null) 'fehler': fehler,
      };

  group('Eingegangene SMS lesen', () {
    test('übernimmt Text, Zeitpunkt, Geräte-ID und zugeordnete Nummer', () {
      final v = SmsVerlauf.ausRoh(antwort(nachrichten: [
        {
          'geraet_id': 4711,
          'nummer': '+491761234567',
          'text': 'Bună ziua, am primit scrisoarea',
          'empfangen_ms': 1786300000000,
        },
      ]));

      expect(v.lage, SmsLeseLage.bereit);
      expect(v.gelesen, isTrue);
      expect(v.nachrichten, hasLength(1));
      expect(v.nachrichten.single.text, 'Bună ziua, am primit scrisoarea');
      expect(v.nachrichten.single.geraetId, 4711);
      // Die Nummer, die gepasst hat — nicht die Schreibweise aus dem
      // Posteingang. Danach ordnet der Server dem Mitglied zu.
      expect(v.nachrichten.single.nummer, '+491761234567');
      expect(
        v.nachrichten.single.empfangen,
        DateTime.fromMillisecondsSinceEpoch(1786300000000),
      );
    });

    test('ohne Geräte-ID wird die SMS verworfen — sie wäre bei jedem '
        'Durchgang erneut neu', () {
      // Die _id aus dem Android-Posteingang ist der einzige Schutz gegen
      // Doppelimport: zwei SMS derselben Sekunde mit gleichem Text sind sonst
      // nicht auseinanderzuhalten.
      final v = SmsVerlauf.ausRoh(antwort(nachrichten: [
        {'nummer': '+49176', 'text': 'ohne id', 'empfangen_ms': 1786300000000},
        {'geraet_id': 0, 'nummer': '+49176', 'text': 'id null', 'empfangen_ms': 1786300000000},
        {'geraet_id': 9, 'nummer': '+49176', 'text': 'gut', 'empfangen_ms': 1786300000000},
      ]));

      expect(v.nachrichten.map((e) => e.text), ['gut']);
    });

    test('ohne zugeordnete Nummer wird die SMS verworfen — sie landete sonst '
        'beim falschen Mitglied', () {
      final v = SmsVerlauf.ausRoh(antwort(nachrichten: [
        {'geraet_id': 5, 'text': 'ohne Nummer', 'empfangen_ms': 1},
        {'geraet_id': 6, 'nummer': '', 'text': 'leere Nummer', 'empfangen_ms': 1},
        {'geraet_id': 7, 'nummer': '+49176', 'text': 'gut', 'empfangen_ms': 1},
      ]));

      expect(v.nachrichten.map((e) => e.text), ['gut']);
    });

    test('leerer Posteingang ist kein Fehler', () {
      final v = SmsVerlauf.ausRoh(antwort());

      expect(v.lage, SmsLeseLage.bereit);
      expect(v.nachrichten, isEmpty);
    });

    test('fehlende Nachrichtenliste wirft nicht', () {
      final v = SmsVerlauf.ausRoh({'lage': 'bereit'});

      expect(v.nachrichten, isEmpty);
      expect(v.abgeschnitten, isFalse);
    });
  });

  group('Zustände, die NICHT als „nichts Neues" durchgehen dürfen', () {
    // Genau hier lag die Falle, für die es die Diagnose überhaupt gibt: bei
    // MODE_IGNORED liefert die Abfrage null Zeilen, ohne zu scheitern. Als
    // leerer Posteingang gemeldet, wartete man ewig auf Nachrichten, die nie
    // kommen können.
    test('vom Installer blockiert ist ein eigener Zustand', () {
      final v = SmsVerlauf.ausRoh(antwort(lage: 'vom_installer_blockiert'));

      expect(v.lage, SmsLeseLage.vomInstallerBlockiert);
      expect(v.gelesen, isFalse);
    });

    test('fehlende Berechtigung ist ein eigener Zustand', () {
      final v = SmsVerlauf.ausRoh(antwort(lage: 'keine_berechtigung'));

      expect(v.lage, SmsLeseLage.keineBerechtigung);
      expect(v.gelesen, isFalse);
    });

    test('Mitglied ohne Rufnummer ist ein eigener Zustand', () {
      final v = SmsVerlauf.ausRoh({'lage': 'keine_nummer'});

      expect(v.lage, SmsLeseLage.keineNummer);
      expect(v.gelesen, isFalse);
    });

    test('ein unbekannter Zustand gilt als Fehler, nicht als leer', () {
      final v = SmsVerlauf.ausRoh(antwort(lage: 'irgendwas_neues'));

      expect(v.lage, SmsLeseLage.fehler);
      expect(v.gelesen, isFalse);
    });

    test('Fehlertext wird durchgereicht', () {
      final v = SmsVerlauf.ausRoh(
          antwort(lage: 'fehler', fehler: 'security: denied'));

      expect(v.lage, SmsLeseLage.fehler);
      expect(v.fehler, 'security: denied');
    });
  });

  group('Abgeschnittene Ausbeute', () {
    // Verschwiegen käme der Rest nie an: der nächste Durchgang fragt ab dem
    // Zeitpunkt der letzten importierten SMS, und was dazwischen lag, wäre
    // für immer übersprungen.
    test('meldet, dass mehr bereitlag als geholt wurde', () {
      final v = SmsVerlauf.ausRoh(antwort(
        nachrichten: [
          {'geraet_id': 1, 'nummer': '+49176', 'text': 'a', 'empfangen_ms': 1},
        ],
        abgeschnitten: true,
      ));

      expect(v.abgeschnitten, isTrue);
    });
  });
}
