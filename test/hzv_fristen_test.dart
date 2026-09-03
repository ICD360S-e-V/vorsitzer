import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/hzv_fristen.dart';

/// Die beiden gesetzlichen Fristen der hausarztzentrierten Versorgung
/// (§ 73b SGB V) und die daraus abgeleiteten Hinweise.
///
/// ⚠️ Geprüft wird ausdrücklich AUCH, dass die Kündigungsfrist NICHT gerechnet
/// wird: sie steht im Vertrag der jeweiligen Kasse und weicht ab. Ein
/// gerechnetes Kündigungsdatum wäre für einen Teil der Kassen falsch — und
/// sähe dabei aus wie ein richtiges.
void main() {
  group('Widerrufsfrist — zwei Wochen ab Abgabe', () {
    test('genau 14 Tage, der 14. Tag zählt noch mit', () {
      expect(hzvWiderrufBis(DateTime(2026, 9, 3)), DateTime.utc(2026, 9, 17));
    });

    test('über einen Monatswechsel', () {
      expect(hzvWiderrufBis(DateTime(2026, 1, 25)), DateTime.utc(2026, 2, 8));
    });

    test('über die Sommerzeit-Umstellung bleiben es 14 Kalendertage', () {
      // 2026: Umstellung auf Sommerzeit am 29.03. In Ortszeit gerechnet wären
      // "+14 Tage" hier 13 Tage 23 Stunden und lägen einen Tag zu früh.
      expect(hzvWiderrufBis(DateTime(2026, 3, 22)), DateTime.utc(2026, 4, 5));
    });

    test('ohne Datum gibt es keine Frist', () {
      expect(hzvWiderrufBis(null), isNull);
    });
  });

  group('Mindestbindung — zwölf Monate ab Beginn', () {
    test('endet am Tag vor dem Jahrestag', () {
      expect(hzvBindungBis(DateTime(2026, 4, 1)), DateTime.utc(2027, 3, 31));
    });

    test('ein Schaltjahr verschiebt nichts (kein Duration(days: 365))', () {
      // 2028 ist ein Schaltjahr: mit 365 Tagen käme der 30.03. heraus.
      expect(hzvBindungBis(DateTime(2027, 4, 1)), DateTime.utc(2028, 3, 31));
    });

    test('Beginn am 29. Februar endet am 28. Februar', () {
      expect(hzvBindungBis(DateTime(2028, 2, 29)), DateTime.utc(2029, 2, 28));
    });

    test('hängt am Beginn, nicht an der Unterschrift', () {
      // Unterschrift im Januar, Beginn zum Quartal am 01.04. — gebunden ist bis
      // zum 31.03. des Folgejahres, nicht bis zum Januar.
      expect(hzvBindungBis(DateTime(2026, 4, 1))!.month, 3);
    });
  });

  group('Hinweise', () {
    Map<String, dynamic> t(Map<String, dynamic> m) => {
          'status': 'aktiv',
          'unterschrieben_am': '',
          'beginn_am': '',
          ...m,
        };

    test('Widerruf wird gemeldet, solange die Frist läuft', () {
      final h = hzvHinweise(
        t({'status': 'eingereicht', 'unterschrieben_am': '2026-09-01'}),
        heute: DateTime(2026, 9, 3),
      );
      expect(h, isNotEmpty);
      expect(h.first.text, contains('15.09.2026'));
      expect(h.first.art, HzvHinweisArt.info);
    });

    test('am letzten Tag steht das ausdrücklich da', () {
      final h = hzvHinweise(
        t({'status': 'eingereicht', 'unterschrieben_am': '2026-09-01'}),
        heute: DateTime(2026, 9, 15),
      );
      expect(h.first.text, contains('heute der letzte Tag'));
    });

    test('nach Fristablauf kein Widerrufs-Hinweis mehr', () {
      final h = hzvHinweise(
        t({'status': 'eingereicht', 'unterschrieben_am': '2026-09-01'}),
        heute: DateTime(2026, 9, 16),
      );
      expect(h.where((e) => e.text.contains('Widerruf')), isEmpty);
    });

    test('eine widerrufene Teilnahme bekommt keinen Widerrufs-Hinweis', () {
      final h = hzvHinweise(
        t({'status': 'widerrufen', 'unterschrieben_am': '2026-09-01', 'widerruf_am': '2026-09-05'}),
        heute: DateTime(2026, 9, 6),
      );
      expect(h.where((e) => e.text.contains('noch bis')), isEmpty);
    });

    test('Bindungsende wird 60 Tage vorher gemeldet, vorher nicht', () {
      final nah = hzvHinweise(t({'beginn_am': '2026-04-01'}), heute: DateTime(2027, 2, 15));
      expect(nah.any((e) => e.art == HzvHinweisArt.warnung && e.text.contains('31.03.2027')), isTrue);

      final fern = hzvHinweise(t({'beginn_am': '2026-04-01'}), heute: DateTime(2026, 10, 1));
      expect(fern.where((e) => e.text.contains('Mindestbindung endet')), isEmpty);
    });

    test('ein eingetragenes Bindungsende schlägt das gerechnete', () {
      // Das Begrüßungsschreiben der Kasse nennt ein Quartalsende.
      final h = hzvHinweise(
        t({'beginn_am': '2026-04-01', 'bindung_bis': '2027-06-30'}),
        heute: DateTime(2027, 5, 15),
      );
      expect(h.any((e) => e.text.contains('30.06.2027')), isTrue);
      expect(h.any((e) => e.text.contains('31.03.2027')), isFalse);
    });

    test('abgelaufene Bindung ist eine Auskunft, keine Warnung', () {
      final h = hzvHinweise(t({'beginn_am': '2020-01-01'}), heute: DateTime(2026, 9, 3));
      expect(h.single.art, HzvHinweisArt.info);
      expect(h.single.text, contains('abgelaufen'));
    });

    test('gekündigt ohne „wirksam zum" wird angemahnt', () {
      final h = hzvHinweise(
        t({'status': 'gekuendigt', 'kuendigung_am': '2026-09-01'}),
        heute: DateTime(2026, 9, 3),
      );
      expect(h.single.art, HzvHinweisArt.warnung);
      expect(h.single.text, contains('wirksam zum'));
    });

    test('widerrufen ohne Datum wird angemahnt', () {
      final h = hzvHinweise(t({'status': 'widerrufen'}), heute: DateTime(2026, 9, 3));
      expect(h.single.text, contains('Zwei-Wochen-Frist'));
    });

    test('kein Hinweis nennt je ein gerechnetes Kündigungsdatum', () {
      // Die Kündigungsfrist steht im Vertrag der Kasse. Sobald ein Hinweis ein
      // Datum als "kündigen bis" ausgäbe, wäre er für die Hälfte der Kassen
      // falsch — dieser Test hält den Verzicht fest.
      for (final heute in [DateTime(2026, 5, 1), DateTime(2027, 2, 20), DateTime(2027, 4, 5)]) {
        for (final h in hzvHinweise(t({'beginn_am': '2026-04-01'}), heute: heute)) {
          expect(h.text.contains('kündigen bis'), isFalse, reason: h.text);
          expect(h.text.contains('Kündigung bis'), isFalse, reason: h.text);
        }
      }
    });
  });

  group('Bezeichnungen', () {
    test('jeder Status der Auswahl hat eine Beschriftung', () {
      for (final k in hzvStatusReihenfolge) {
        expect(hzvStatusLabel[k], isNotNull, reason: k);
      }
      expect(hzvStatusReihenfolge.length, hzvStatusLabel.length);
    });

    test('Status, Abgabeort und Dokumentart decken sich mit dem Server-ENUM', () {
      // ⚠️ Die drei Listen stehen auch in krankenkasse_hzv_manage.php bzw.
      // krankenkasse_hzv_doc_upload.php (HZV_STATUS, HZV_ABGABE, HZV_DOK_TYPEN)
      // und in der Tabellendefinition. Das PHP liegt in keinem Repo — hier ist
      // die einzige Stelle, an der ein Auseinanderlaufen auffallen kann. Ein
      // unbekannter Wert fällt serverseitig still auf die Vorgabe zurück.
      expect(hzvStatusLabel.keys.toSet(),
          {'eingereicht', 'aktiv', 'widerrufen', 'gekuendigt', 'abgelehnt', 'beendet'});
      expect(hzvAbgabeOrtLabel.keys.toSet(), {'praxis', 'kasse', 'online', 'post', 'sonstige'});
      expect(hzvDokTypLabel.keys.toSet(),
          {'teilnahmeerklaerung', 'begruessung', 'bestaetigung', 'widerruf', 'kuendigung', 'sonstiges'});
    });

    test('laufend ist nur eingereicht und aktiv', () {
      expect(hzvLaeuft('eingereicht'), isTrue);
      expect(hzvLaeuft('aktiv'), isTrue);
      for (final s in ['widerrufen', 'gekuendigt', 'abgelehnt', 'beendet', null, '']) {
        expect(hzvLaeuft(s), isFalse, reason: '$s');
      }
    });
  });
}
