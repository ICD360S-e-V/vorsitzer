import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/blut_bedeutung.dart';
import 'package:icd360sev_vorsitzer/utils/blut_parameter_liste.dart';
import 'package:icd360sev_vorsitzer/utils/blut_pdf_teile.dart';

void main() {
  group('pdfText', () {
    test('ersetzt die Zeichen, die die PDF-Schrift nicht kennt', () {
      expect(pdfText('a—b'), 'a-b');
      expect(pdfText('„gut“'), '"gut"');
      expect(pdfText('7,9↑'), '7,9');
      expect(pdfText('mehr…'), 'mehr...');
    });

    test('lässt an, was Helvetica darstellen kann', () {
      // ⚠️ Umlaute, ß und µ MÜSSEN durchkommen — sie stehen in fast jedem
      // Parameternamen und in jeder Einheit.
      const s = 'Hämoglobin 16,1 g/dl · Tsd/µl · außerhalb · Öl · Übergewicht';
      expect(pdfText(s), s);
    });
  });

  // ⚠️ Das ist die eigentliche Plane. Kommt später eine Erklärung mit einem
  // typografischen Zeichen dazu, malt das PDF an dieser Stelle ein leeres
  // Kästchen — sichtbar nur, wenn jemand das erzeugte Blatt ansieht.
  // Hier fällt es beim Testlauf auf.
  test('keine Erklärung enthält ein Zeichen außerhalb von Latin-1', () {
    final schlimm = <String>[];
    kBlutBedeutung.forEach((key, b) {
      for (final t in [b.ist, b.hoch, b.tief, b.quelle]) {
        final gefiltert = pdfText(t);
        for (final r in gefiltert.runes) {
          if (r > 0xFF) {
            schlimm.add('$key: ${String.fromCharCode(r)} (U+${r.toRadixString(16)})');
            break;
          }
        }
      }
    });
    expect(schlimm, isEmpty, reason: 'Zeichen ohne Glyphe: ${schlimm.take(10)}');
  });

  test('auch Bezeichnung und Einheit jedes Parameters bleiben darstellbar', () {
    final schlimm = <String>[];
    for (final geschlecht in [true, false]) {
      for (final p in blutParameterListe(geschlecht)) {
        for (final t in [p['label'] as String, (p['unit'] as String?) ?? '',
                         (p['gruppe'] as String?) ?? '']) {
          if (pdfText(t).runes.any((r) => r > 0xFF)) schlimm.add('${p['key']}: $t');
        }
      }
    }
    expect(schlimm, isEmpty, reason: 'Zeichen ohne Glyphe: ${schlimm.take(10)}');
  });

  group('Bericht', () {
    Map<String, dynamic> wert(String key, dynamic v, String status) {
      final p = blutParameterListe(true).firstWhere((e) => e['key'] == key);
      return {...p, 'value': v, 'status': status};
    }

    test('lässt sich mit ALLEN Parametern erzeugen', () async {
      // Jeder Parameter einmal, damit kein einzelner die Erzeugung sprengt —
      // etwa durch einen Referenzbereich, den der Balken nicht abbilden kann.
      final alle = blutParameterListe(true).map((p) {
        return p['qualitativ'] == true
            ? {...p, 'value': 'negativ', 'status': 'normal'}
            : {...p, 'value': (p['min'] as num).toDouble(), 'status': 'normal'};
      }).toList();
      final pdf = blutBerichtPdf(
        datum: '17.08.2026', patient: 'Max Mustermann',
        mitgliedsnummer: 'M10002', werte: alle, auffaellig: const [],
      );
      expect((await pdf.save()).length, greaterThan(1000));
    });

    test('kommt ohne Referenzbereich aus', () async {
      final pdf = blutBerichtPdf(
        datum: '', patient: '', mitgliedsnummer: '',
        werte: [wert('hdl_cholesterin', 38.0, 'niedrig')],
        auffaellig: [wert('hdl_cholesterin', 38.0, 'niedrig')],
      );
      expect((await pdf.save()).length, greaterThan(500));
    });
  });
}
