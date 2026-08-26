import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/bussgeld_vorfall_dialog.dart';

/// Die Frist ist die einzige Zahl in diesem Reiter, an der etwas haengt:
/// laeuft sie ab, ist der Bussgeldbescheid rechtskraeftig. Deshalb steht sie
/// hier unter Test und nicht nur im Kopf.
void main() {
  group('Einspruchsfrist § 67 Abs. 1 OWiG', () {
    test('zwei Wochen nach Zustellung, gerechnet ab dem Zugang', () {
      // Zustellung Montag 17.08.2026 -> Montag 31.08.2026
      expect(bussgeldFristVorschlag(DateTime(2026, 8, 17)), DateTime(2026, 8, 31));
    });

    test('das Datum AUF dem Bescheid ist nicht der Fristbeginn', () {
      // Derselbe Vorgang: Bescheid vom 10.08., zugegangen am 17.08.
      // Wer vom Bescheiddatum rechnet, kaeme auf den 24.08. - eine Woche zu
      // frueh, also sieben Tage Einspruchszeit verschenkt.
      final ausBescheid = bussgeldFristVorschlag(DateTime(2026, 8, 10));
      final ausZugang = bussgeldFristVorschlag(DateTime(2026, 8, 17));
      expect(ausBescheid, isNot(ausZugang));
      expect(ausZugang.difference(ausBescheid).inDays, 7);
    });

    test('Fristende auf Samstag rueckt auf Montag (§ 43 Abs. 2 StPO)', () {
      // Zugang Samstag 15.08.2026 -> +14 = Samstag 29.08. -> Montag 31.08.
      final f = bussgeldFristVorschlag(DateTime(2026, 8, 15));
      expect(f.weekday, DateTime.monday);
      expect(f, DateTime(2026, 8, 31));
    });

    test('Fristende auf Sonntag rueckt auf Montag', () {
      // Zugang Sonntag 16.08.2026 -> +14 = Sonntag 30.08. -> Montag 31.08.
      final f = bussgeldFristVorschlag(DateTime(2026, 8, 16));
      expect(f.weekday, DateTime.monday);
      expect(f, DateTime(2026, 8, 31));
    });

    test('faellt das Ende auf einen Werktag, wird nichts verschoben', () {
      for (final tag in [
        DateTime(2026, 8, 17), // Mo -> Mo
        DateTime(2026, 8, 18), // Di -> Di
        DateTime(2026, 8, 19), // Mi -> Mi
        DateTime(2026, 8, 20), // Do -> Do
        DateTime(2026, 8, 21), // Fr -> Fr
      ]) {
        final f = bussgeldFristVorschlag(tag);
        expect(f.difference(tag).inDays, kBussgeldFristTage,
            reason: 'Werktag ${tag.weekday} darf nicht verschoben werden');
        expect(f.weekday, tag.weekday);
      }
    });

    test('die Frist wird nie verkuerzt, nur nach hinten geschoben', () {
      // Ueber ein ganzes Jahr: das Ergebnis liegt nie vor Zugang + 14 Tagen.
      var d = DateTime(2026, 1, 1);
      while (d.isBefore(DateTime(2027, 1, 1))) {
        final f = bussgeldFristVorschlag(d);
        // ⚠️ Der Abstand wird in UTC gemessen. Zwei lokale Mitternachte
        // liegen ueber der Zeitumstellung nur 335 statt 336 Stunden
        // auseinander - der Test haette sonst dieselbe Falle gemeldet, die
        // er in der Funktion gerade abstellt.
        final abstand = DateTime.utc(f.year, f.month, f.day)
            .difference(DateTime.utc(d.year, d.month, d.day)).inDays;
        expect(abstand, greaterThanOrEqualTo(kBussgeldFristTage),
            reason: 'verkuerzt bei $d');
        expect(abstand, lessThanOrEqualTo(kBussgeldFristTage + 2),
            reason: 'mehr als ein Wochenende geschoben bei $d');
        expect(f.weekday, isNot(DateTime.saturday));
        expect(f.weekday, isNot(DateTime.sunday));
        d = DateTime(d.year, d.month, d.day + 1);
      }
    });

    test('Uhrzeit im Zugangsdatum verschiebt das Ergebnis nicht', () {
      // showDatePicker liefert Mitternacht, ein aus dem Server geparstes
      // Datum kann eine Uhrzeit tragen. Beides muss denselben Tag ergeben.
      expect(bussgeldFristVorschlag(DateTime(2026, 8, 17, 23, 59)),
             bussgeldFristVorschlag(DateTime(2026, 8, 17)));
    });
  });

  group('Aufzaehlungen des Vorfalls', () {
    test('jede Art hat einen deutschen Text', () {
      for (final e in kBussgeldArten.entries) {
        expect(e.value.trim(), isNotEmpty, reason: 'Art ${e.key} ohne Beschriftung');
      }
    });

    test('Schluessel decken sich mit dem ENUM der Datenbank', () {
      // ⚠️ Diese Liste steht auch im ENUM von user_bussgeld_vorfaelle.art.
      // Laufen die beiden auseinander, kuerzt MariaDB einen unbekannten Wert
      // stillschweigend auf '' - der Vorfall haette dann gar keine Art mehr.
      expect(kBussgeldArten.keys.toSet(), {
        'anhoerungsbogen', 'zeugenfragebogen', 'verwarnung', 'bussgeldbescheid',
        'kostenbescheid', 'mahnung', 'vollstreckung', 'sonstiges',
      });
      expect(kBussgeldStatus.keys.toSet(), {
        'offen', 'frist_laeuft', 'einspruch_eingelegt', 'rechtskraeftig',
        'eingestellt', 'bezahlt', 'abgeschlossen',
      });
      expect(kFristArten.keys.toSet(), {'einspruch', 'anhoerung', 'zahlung', 'sonstige'});
      expect(kEinspruchWege.keys.toSet(),
             {'post', 'fax', 'niederschrift', 'elektronisch', 'sonstige'});
    });
  });
}
