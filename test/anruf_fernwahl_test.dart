import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/anruf_gateway_service.dart';
import 'package:icd_anruf/icd_anruf.dart';

/// Prüfungen rund um den ferngesteuerten Anruf, die ohne Gerät auskommen.
///
/// Das eigentliche Wählen lässt sich nur auf dem Telefon prüfen. Was sich hier
/// prüfen lässt, sind die drei Stellen, an denen dieses Feature still falsch
/// werden kann: eine Fähigkeitsmeldung, die „bereit" sagt, ohne es zu sein;
/// ein Ergebniscode, den der Server nicht kennt; und eine Antwortform, die der
/// Client anders liest, als PHP sie schickt.
void main() {
  group('AnrufFaehigkeiten', () {
    test('leere Meldung heißt: kann nichts', () {
      const f = AnrufFaehigkeiten();
      expect(f.telefonie, isFalse);
      expect(f.waehltVonAllein, isFalse);
    });

    test('fehlende Schlüssel gelten als nein, nicht als ja', () {
      // Eine ältere Installation ohne das Plugin schickt eine unvollständige
      // Map. Würde ein fehlender Schlüssel als „true" gelesen, meldete das
      // Gerät Bereitschaft, die es nicht hat.
      final f = AnrufFaehigkeiten.vonKanal(<Object?, Object?>{'telefonie': true});
      expect(f.telefonie, isTrue);
      expect(f.anrufrecht, isFalse);
      expect(f.overlay, isFalse);
      expect(f.waehltVonAllein, isFalse);
    });

    test('ohne Overlay ist das Gerät NICHT selbstständig', () {
      // Der Kern der Sache: Android verwirft den Anruf aus dem Hintergrund
      // stumm. Telefonie und Anrufrecht allein reichen also nicht, und diese
      // Zusage darf die Oberfläche nie geben.
      final f = AnrufFaehigkeiten.vonKanal(<Object?, Object?>{
        'telefonie': true,
        'anrufrecht': true,
        'overlay': false,
        'vollbild': true,
      });
      expect(f.waehltVonAllein, isFalse);
    });

    test('mit Overlay ist es selbstständig', () {
      final f = AnrufFaehigkeiten.vonKanal(<Object?, Object?>{
        'telefonie': true,
        'anrufrecht': true,
        'overlay': true,
      });
      expect(f.waehltVonAllein, isTrue);
    });

    test('nur Wahrheitswerte zählen, nicht „truthy"', () {
      // MethodChannel liefert dynamisch typisierte Werte. Ein String "false"
      // ist kein true — sonst wäre jede kaputte Antwort eine Bereitmeldung.
      final f = AnrufFaehigkeiten.vonKanal(<Object?, Object?>{
        'telefonie': 'true',
        'anrufrecht': 1,
        'overlay': 'ja',
      });
      expect(f.telefonie, isFalse);
      expect(f.anrufrecht, isFalse);
      expect(f.overlay, isFalse);
    });
  });

  group('Ergebniscodes', () {
    /// Was `api/anruf/queue.php` in `case 'report'` als gültig durchlässt.
    /// Wörtlich aus dem Endpunkt abgeschrieben, nicht aus dem Gedächtnis.
    const serverErlaubt = {
      'gewaehlt',
      'bestaetigung_noetig',
      'keine_berechtigung',
      'kein_telefon',
      'notruf',
      'ungueltig',
      'fehler',
    };

    test('jeder Code des Clients wird vom Server angenommen', () {
      // Ein umbenannter Code fällt sonst erst in Produktion auf: der Server
      // antwortet mit 400, das Telefon hat aber längst gewählt, und der
      // Auftrag bleibt für immer auf „claimed" stehen.
      const clientCodes = {
        IcdAnrufErgebnis.gewaehlt,
        IcdAnrufErgebnis.bestaetigungNoetig,
        IcdAnrufErgebnis.keineBerechtigung,
        IcdAnrufErgebnis.keinTelefon,
        IcdAnrufErgebnis.notruf,
        IcdAnrufErgebnis.ungueltig,
        IcdAnrufErgebnis.fehler,
      };
      expect(clientCodes, equals(serverErlaubt));
    });

    test('nur „gewaehlt" ist ein Erfolg', () {
      // bestaetigung_noetig heißt: es liegt eine Benachrichtigung, gewählt ist
      // NICHTS. Wer das als Erfolg zählt, hört auf nachzufragen, obwohl es an
      // ihm liegt.
      expect(IcdAnrufErgebnis.gewaehlt, isNot(IcdAnrufErgebnis.bestaetigungNoetig));
    });
  });

  group('AnrufGatewayLauf', () {
    test('leerer Durchlauf hat nichts getan und ist trotzdem in Ordnung', () {
      const lauf = AnrufGatewayLauf();
      expect(lauf.didSomething, isFalse);
      expect(lauf.note, isNull);
    });

    test('eine liegengebliebene Zeile zählt als „etwas getan"', () {
      // Sonst stünde in der Dauerbenachrichtigung „bereit", obwohl am Telefon
      // eine unbeantwortete Anrufmeldung liegt.
      const lauf = AnrufGatewayLauf(liegengeblieben: 1);
      expect(lauf.didSomething, isTrue);
    });

    test('note verdrängt die Zahlen in der Anzeige', () {
      const lauf = AnrufGatewayLauf(note: 'Anruf-Gateway ist aus');
      expect(lauf.toString(), 'Anruf-Gateway ist aus');
    });
  });

  group('AnrufFernErgebnis', () {
    test('nur gewaehlt gilt als erfolgreich', () {
      for (final stand in AnrufFernStand.values) {
        final e = AnrufFernErgebnis(stand, 'x');
        expect(e.erfolgreich, stand == AnrufFernStand.gewaehlt,
            reason: 'Stand $stand');
      }
    });

    test('„schlaeft" ist ein eigener Zustand, nicht „kein Gerät"', () {
      // Der Unterschied ist der ganze Punkt der Korrektur vom 08.08.: das
      // Telefon LÄUFT, es macht nur eine Schlafpause, und der Auftrag gilt
      // weiter. Würde das wieder mit keinGeraet zusammenfallen, käme der
      // tel:-Rückfall dazu — und sobald das Telefon aufwacht, wählt es
      // ebenfalls. Ein Klick, zwei Anrufe.
      expect(AnrufFernStand.values, contains(AnrufFernStand.schlaeft));
      expect(AnrufFernStand.schlaeft, isNot(AnrufFernStand.keinGeraet));
      expect(const AnrufFernErgebnis(AnrufFernStand.schlaeft, 'x').erfolgreich,
          isFalse);
    });
  });
}
