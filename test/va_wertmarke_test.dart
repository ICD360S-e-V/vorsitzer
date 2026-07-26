import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/behorde_versorgungsamt.dart';

void main() {
  group('VaWertmarke Zeitraum', () {
    test('von ist der 1. des Ab-Monats', () {
      final w = VaWertmarke(id: 1, abMonat: '03', abJahr: '2026', bisMonat: '02', bisJahr: '2027');
      expect(w.von, DateTime(2026, 3, 1));
    });

    test('bis ist der LETZTE Tag des Bis-Monats — die Marke gilt den ganzen Monat', () {
      final w = VaWertmarke(id: 1, abMonat: '03', abJahr: '2026', bisMonat: '02', bisJahr: '2027');
      expect(w.bis, DateTime(2027, 2, 28));
      // Schaltjahr
      final s = VaWertmarke(id: 2, abMonat: '01', abJahr: '2028', bisMonat: '02', bisJahr: '2028');
      expect(s.bis, DateTime(2028, 2, 29));
      // Dezember darf nicht ins Vorjahr kippen
      final d = VaWertmarke(id: 3, abMonat: '01', abJahr: '2026', bisMonat: '12', bisJahr: '2026');
      expect(d.bis, DateTime(2026, 12, 31));
    });

    test('unvollständige Angaben liefern null statt zu werfen', () {
      expect(VaWertmarke(id: 1).von, isNull);
      expect(VaWertmarke(id: 1, abMonat: '05').von, isNull);
      expect(VaWertmarke(id: 1, bisJahr: '2026').bis, isNull);
    });

    test('Labels bleiben leer, solange Monat oder Jahr fehlt', () {
      expect(VaWertmarke(id: 1, abMonat: '05').abLabel, '');
      expect(VaWertmarke(id: 1, abMonat: '05', abJahr: '2026').abLabel, '05/2026');
    });
  });

  group('vaWmStatus', () {
    final w = VaWertmarke(id: 1, abMonat: '01', abJahr: '2026', bisMonat: '12', bisJahr: '2026');

    test('vor Beginn = zukuenftig', () {
      expect(vaWmStatus(w, DateTime(2025, 12, 20)), VaWmStatus.zukuenftig);
    });

    test('mitten drin = aktiv', () {
      expect(vaWmStatus(w, DateTime(2026, 5, 10)), VaWmStatus.aktiv);
    });

    test('innerhalb der letzten 60 Tage = laeuftAb', () {
      expect(vaWmStatus(w, DateTime(2026, 11, 20)), VaWmStatus.laeuftAb);
    });

    test('am letzten Gültigkeitstag noch nicht abgelaufen', () {
      expect(vaWmStatus(w, DateTime(2026, 12, 31)), VaWmStatus.laeuftAb);
    });

    test('nach dem Bis-Monat = abgelaufen', () {
      expect(vaWmStatus(w, DateTime(2027, 1, 2)), VaWmStatus.abgelaufen);
    });

    test('ohne Zeitraum = unvollstaendig', () {
      expect(vaWmStatus(VaWertmarke(id: 9), DateTime(2026, 5, 1)), VaWmStatus.unvollstaendig);
    });
  });

  group('Persistenz', () {
    test('JSON-Round-Trip erhält alle Felder inklusive ID', () {
      final w = VaWertmarke(id: 7, abMonat: '04', abJahr: '2026', bisMonat: '03', bisJahr: '2027', notiz: 'kostenlos, Bürgergeld');
      final zurueck = VaWertmarke.fromJson(jsonDecode(jsonEncode(w.toJson())) as Map<String, dynamic>);
      expect(zurueck.id, 7);
      expect(zurueck.abLabel, '04/2026');
      expect(zurueck.bisLabel, '03/2027');
      expect(zurueck.notiz, 'kostenlos, Bürgergeld');
    });

    test('fromJson verkraftet Zahlen als Strings (so kommt es aus der DB)', () {
      final w = VaWertmarke.fromJson({'id': '3', 'ab_monat': 1, 'ab_jahr': 2026});
      expect(w.id, 3);
      expect(w.abMonat, '1');
      expect(w.abJahr, '2026');
    });

    test('Liste sortiert neueste zuerst; Einträge ohne Datum landen hinten', () {
      final list = [
        VaWertmarke(id: 1, abMonat: '01', abJahr: '2025'),
        VaWertmarke(id: 2),
        VaWertmarke(id: 3, abMonat: '06', abJahr: '2026'),
        VaWertmarke(id: 4, abMonat: '01', abJahr: '2026'),
      ]..sort((a, b) => b.sortKey.compareTo(a.sortKey));
      expect(list.map((w) => w.id).toList(), [3, 4, 1, 2]);
    });
  });
}
