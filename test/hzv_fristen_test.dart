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

    // § 73b Abs. 3 SGB V: „Die Widerrufsfrist beginnt, wenn die Krankenkasse dem
    // Versicherten eine Belehrung über sein Widerrufsrecht schriftlich oder
    // elektronisch mitgeteilt hat, frühestens jedoch mit der Abgabe der
    // Teilnahmeerklärung." Also der SPÄTERE der beiden Tage.
    test('eine später erhaltene Belehrung schiebt die Frist nach hinten', () {
      expect(hzvWiderrufBis(DateTime(2026, 9, 1), DateTime(2026, 9, 10)),
          DateTime.utc(2026, 9, 24));
    });

    test('eine Belehrung VOR der Unterschrift verkürzt die Frist nicht', () {
      // „frühestens jedoch mit der Abgabe" — die Unterschrift gewinnt.
      expect(hzvWiderrufBis(DateTime(2026, 9, 1), DateTime(2026, 8, 20)),
          DateTime.utc(2026, 9, 15));
    });

    // Der belegte Regelfall aus dem echten Begruessungsschreiben der IKK classic:
    // Teilnahmeerklaerung in der Praxis unterschrieben, Belehrung erst Wochen
    // spaeter mit dem Brief der Kasse. Wer nur ab der Unterschrift rechnet,
    // meldet hier laengst „abgelaufen", waehrend die Frist noch laeuft.
    test('Belehrung im Begruessungsschreiben — Frist laeuft ab dessen Erhalt', () {
      final wBis = hzvWiderrufBis(DateTime(2026, 7, 20), DateTime(2026, 8, 19));
      expect(wBis, DateTime.utc(2026, 9, 2));
      // Gegenprobe: allein ab der Unterschrift waere schon der 03.08. der letzte Tag.
      expect(hzvWiderrufBis(DateTime(2026, 7, 20)), DateTime.utc(2026, 8, 3));
    });

    test('nur eine Belehrung, ohne erfasste Unterschrift, reicht auch', () {
      expect(hzvWiderrufBis(null, DateTime(2026, 9, 10)), DateTime.utc(2026, 9, 24));
    });

    test('der Beginn ist der spätere Tag, nicht der erste', () {
      expect(hzvWiderrufBeginn(DateTime(2026, 9, 1), DateTime(2026, 9, 10)),
          DateTime.utc(2026, 9, 10));
      expect(hzvWiderrufBeginn(DateTime(2026, 9, 1), null), DateTime.utc(2026, 9, 1));
      expect(hzvWiderrufBeginn(null, null), isNull);
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

    test('mit späterer Belehrung ist die Frist noch offen, wo sie sonst um wäre', () {
      final h = hzvHinweise(
        t({
          'status': 'eingereicht',
          'unterschrieben_am': '2026-09-01',
          'belehrung_am': '2026-09-10',
        }),
        heute: DateTime(2026, 9, 20),
      );
      expect(h.first.text, contains('24.09.2026'));
      expect(h.first.text, contains('Belehrung'));
    });

    test('ohne Belehrungsdatum wird der Ablauf als ANNAHME ausgewiesen', () {
      // Der gefährliche Fehler wäre, hier stumm „abgelaufen" zu behaupten: die
      // Frist kann in Wahrheit noch gar nicht angefangen haben.
      final h = hzvHinweise(
        t({'status': 'eingereicht', 'unterschrieben_am': '2026-09-01'}),
        heute: DateTime(2026, 9, 20),
      );
      expect(h, isNotEmpty);
      expect(h.first.text, contains('kein Datum für die Widerrufsbelehrung'));
      expect(h.first.text, contains('womöglich noch offen'));
    });

    test('mit Belehrungsdatum wird nach Ablauf nichts mehr gemeldet', () {
      final h = hzvHinweise(
        t({
          'status': 'eingereicht',
          'unterschrieben_am': '2026-09-01',
          'belehrung_am': '2026-09-01',
        }),
        heute: DateTime(2026, 9, 20),
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

  group('Zwei Hausärzte', () {
    Map<String, dynamic> teil(Map<String, dynamic> m) =>
        {'status': 'aktiv', 'ist_wechsel': false, 'arzt_id': 10, 'arzt_name': 'Dr. Lankes', ...m};

    test('ohne laufende Teilnahme wird gar nichts gemeldet', () {
      // Zwei Hausärzte ohne HZV sind einfach zwei Hausärzte.
      final k = hzvKonflikte(
        [teil({'status': 'beendet'})],
        weitereHausaerzte: [{'arzt_id': 99, 'name': 'Dr. Anders'}],
      );
      expect(k, isEmpty);
    });

    test('ein einzelner Eintrag ohne zweiten Arzt ist sauber', () {
      expect(hzvKonflikte([teil({})]), isEmpty);
    });

    test('zwei laufende Teilnahmen sind ein Befund', () {
      final k = hzvKonflikte([teil({}), teil({'arzt_id': 20})]);
      expect(k, hasLength(1));
      expect(k.single.art, HzvHinweisArt.warnung);
      expect(k.single.text, contains('2 laufende Teilnahmen'));
    });

    test('ein beantragter Wechsel wird als solcher erkannt, nicht als Chaos', () {
      final k = hzvKonflikte([teil({}), teil({'arzt_id': 20, 'ist_wechsel': true})]);
      expect(k.single.text, contains('Wechsel'));
      expect(k.single.text, contains('Beendet'));
      expect(k.single.text.contains('gleichzeitig'), isFalse);
    });

    test('ein zweiter Hausarzt in der Akte wird gemeldet', () {
      final k = hzvKonflikte([teil({})],
          weitereHausaerzte: [{'arzt_id': 99, 'name': 'Dr. Anders'}]);
      expect(k.single.art, HzvHinweisArt.warnung);
      expect(k.single.text, contains('Dr. Anders'));
      expect(k.single.text, contains('Vertretungsarzt'));
      expect(k.single.handlung, isNotNull);
    });

    test('derselbe Arzt in einer zweiten Instanz ist KEIN Befund', () {
      // Sonst schlüge die Warnung bei jedem an, der seine Praxis doppelt erfasst.
      final k = hzvKonflikte([teil({})],
          weitereHausaerzte: [{'arzt_id': 10, 'name': 'Dr. Lankes'}]);
      expect(k, isEmpty);
    });

    test('der benannte Vertretungsarzt ist erklärt und kein Befund', () {
      final k = hzvKonflikte(
        [teil({'vertretungsarzt': 'Dr. med. Anders'})],
        weitereHausaerzte: [{'arzt_id': 99, 'name': 'Dr. Anders'}],
      );
      expect(k, isEmpty);
    });

    test('ohne Katalog-Bindung wird über den Namen verglichen — und gesagt, dass es so ist', () {
      final k = hzvKonflikte(
        [teil({'arzt_id': null})],
        weitereHausaerzte: [{'arzt_id': null, 'name': 'Dr. Anders'}],
      );
      expect(k.single.text, contains('nur über den Namen verglichen'));
    });

    test('gleicher Name ohne ids gilt als derselbe Arzt', () {
      final k = hzvKonflikte(
        [teil({'arzt_id': null, 'arzt_name': 'Dr. med. Lankes'})],
        weitereHausaerzte: [{'arzt_id': null, 'name': 'Lankes'}],
      );
      expect(k, isEmpty);
    });

    test('ohne jede Angabe im HZV-Eintrag wird die Lücke gemeldet, nicht geschwiegen', () {
      final k = hzvKonflikte(
        [teil({'arzt_id': null, 'arzt_name': ''})],
        weitereHausaerzte: [{'arzt_id': null, 'name': 'Dr. Anders'}],
      );
      expect(k.single.art, HzvHinweisArt.info);
      expect(k.single.text, contains('Abgleich ist deshalb nicht möglich'));
    });

    test('Titel und Satzzeichen stören den Namensvergleich nicht', () {
      expect(hzvNameNormal('Dr. med. Anna Lankes-Meier'), 'anna lankes meier');
      expect(hzvNameNormal('Prof. Dr. Anna  Lankes'), 'anna lankes');
    });
  });

  group('Wechselgründe', () {
    test('jeder Grund der Reihenfolge hat eine Beschriftung und umgekehrt', () {
      expect(hzvWechselGrundReihenfolge.toSet(), hzvWechselGrundLabel.keys.toSet());
    });

    test('die Härtefallgründe sind eine Teilmenge des Katalogs', () {
      expect(hzvHaertefallGruende.difference(hzvWechselGrundLabel.keys.toSet()), isEmpty);
    });

    test('„zweiter Hausarzt" ist KEIN Härtefallgrund', () {
      // Ein zweiter Hausarzt begründet den vorzeitigen Wechsel nicht — er macht
      // ihn nötig. Getragen wird er von dem Grund, der dahintersteht.
      expect(hzvHaertefallGruende.contains('zweiter_hausarzt'), isFalse);
      expect(hzvHaertefallGruende.contains('regulaer'), isFalse);
      expect(hzvHaertefallGruende.contains('kassenwechsel'), isFalse);
    });

    test('die vier Härtefälle der Kassenverträge sind vollständig', () {
      expect(hzvHaertefallGruende, {
        'arzt_nicht_mehr_dabei', 'praxis_umzug', 'mitglied_umzug',
        'praxisschliessung', 'vertrauensverhaeltnis',
      });
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
      // HZV_WECHSELGRUENDE und HZV_DATENWEITERGABE in krankenkasse_hzv_manage.php
      expect(hzvWechselGrundLabel.keys.toSet(), {
        'arzt_nicht_mehr_dabei', 'praxis_umzug', 'mitglied_umzug', 'praxisschliessung',
        'vertrauensverhaeltnis', 'zweiter_hausarzt', 'regulaer', 'kassenwechsel', 'sonstiges',
      });
      expect(hzvDatenweitergabeLabel.keys.toSet(), {'unbekannt', 'ja', 'nein'});
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
