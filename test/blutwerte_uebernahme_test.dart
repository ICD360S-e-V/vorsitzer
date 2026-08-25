import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/blutwerte_uebernahme.dart';

/// Ein Vorschlag, wie ihn `api/admin/gesundheit_blut_ocr.php` liefert.
Map<String, dynamic> _v(
  String key, {
  String? wert,
  String label = 'Wert',
  String einheit = 'mg/dl',
  String? warnung,
  bool bestaetigt = true,
  bool umgerechnet = false,
  String? geleseneEinheit,
  bool qualitativ = false,
  bool unscharf = false,
  String zeile = 'Parameter   1,0   mg/dl   0,5 - 2,0',
}) =>
    {
      'key': key,
      'label': label,
      'einheit': einheit,
      'wert': wert,
      'zeile': zeile,
      'zeile_nr': 7,
      'warnung': warnung,
      'umgerechnet': umgerechnet,
      'gelesene_einheit': geleseneEinheit,
      'bestaetigt': bestaetigt,
      'unscharf': unscharf,
      'qualitativ': qualitativ,
    };

void main() {
  group('blutVorschlaegeAufbereiten', () {
    test('ein sauberer, von beiden Lesungen bestätigter Wert wird vorangehakt', () {
      final l = blutVorschlaegeAufbereiten([_v('crp', wert: '2.8')], {});
      expect(l, hasLength(1));
      expect(l.first.uebernehmbar, isTrue);
      expect(l.first.gewaehlt, isTrue);
      expect(l.first.ueberschreibt, isFalse);
    });

    test('ein Wert mit Warnung wird gezeigt, aber NICHT vorangehakt', () {
      // Der Fall, der die Übernahme gefährlich machen würde: gelesen, aber
      // mit einem Vorbehalt, den ein Mensch ansehen muss.
      final l = blutVorschlaegeAufbereiten(
        [_v('crp', wert: '2.8', warnung: 'nur in einer der beiden Lesungen gefunden')],
        {},
      );
      expect(l.first.uebernehmbar, isTrue);
      expect(l.first.gewaehlt, isFalse);
      expect(l.first.warnung, isNotNull);
    });

    test('widersprüchliche Lesungen kommen ohne Wert an und sind nicht wählbar', () {
      final l = blutVorschlaegeAufbereiten(
        [_v('mch', wert: null, warnung: 'die beiden Lesungen widersprechen sich (311 / 31.1)')],
        {},
      );
      expect(l.first.uebernehmbar, isFalse);
      expect(l.first.gewaehlt, isFalse);
    });

    test('ein leerer Wertstring zählt wie kein Wert', () {
      final l = blutVorschlaegeAufbereiten([_v('crp', wert: '   ')], {});
      expect(l.first.uebernehmbar, isFalse);
    });

    test('ein belegtes Feld wird als Überschreibung markiert und nicht vorangehakt', () {
      final l = blutVorschlaegeAufbereiten([_v('crp', wert: '2.8')], {'crp': '9.9'});
      expect(l.first.ueberschreibt, isTrue);
      expect(l.first.bisher, '9.9');
      expect(l.first.gewaehlt, isFalse);
    });

    test('derselbe Wert im Feld ist keine Überschreibung', () {
      final l = blutVorschlaegeAufbereiten([_v('crp', wert: '2.8')], {'crp': '2.8'});
      expect(l.first.ueberschreibt, isFalse);
      // Vorangehakt trotzdem nicht — es gibt nichts zu übernehmen.
      expect(l.first.gewaehlt, isFalse);
    });

    test('ein unbestätigter Wert wird nicht vorangehakt', () {
      final l = blutVorschlaegeAufbereiten([_v('crp', wert: '2.8', bestaetigt: false)], {});
      expect(l.first.gewaehlt, isFalse);
    });

    test('Umrechnung wird durchgereicht, damit der Dialog die Quelleinheit nennen kann', () {
      final l = blutVorschlaegeAufbereiten(
        [_v('creatinin', wert: '1.0633', umgerechnet: true, geleseneEinheit: 'hmol/l')],
        {},
      );
      expect(l.first.umgerechnet, isTrue);
      expect(l.first.geleseneEinheit, 'hmol/l');
    });

    test('qualitative Werte behalten ihre Kennzeichnung', () {
      final l = blutVorschlaegeAufbereiten(
        [_v('hiv_screening', wert: 'negativ', einheit: 'S/CO', qualitativ: true)],
        {},
      );
      expect(l.first.qualitativ, isTrue);
      expect(l.first.wert, 'negativ');
    });

    test('nach Bezeichnung sortiert, nicht nach Reihenfolge im Befund', () {
      final l = blutVorschlaegeAufbereiten([
        _v('b', wert: '1', label: 'Zink'),
        _v('a', wert: '2', label: 'Albumin'),
      ], {});
      expect(l.map((e) => e.label), ['Albumin', 'Zink']);
    });

    test('Einträge ohne Schlüssel werden übersprungen, nicht geraten', () {
      final l = blutVorschlaegeAufbereiten([
        {'label': 'ohne key', 'wert': '5'},
        _v('crp', wert: '2.8'),
      ], {});
      expect(l, hasLength(1));
      expect(l.first.key, 'crp');
    });

    // ⚠️ PHP kennt nur einen Array-Typ: eine lückenlose Liste wird zur
    // JSON-Liste, eine mit Lücken zum Objekt, eine leere wieder zur Liste.
    // Ein `as List` darauf wirft — genau so wurde der Speedtest-Schirm grau.
    test('ein Objekt statt einer Liste wirft nicht, sondern liefert nichts', () {
      expect(blutVorschlaegeAufbereiten({'0': _v('crp', wert: '1')}, {}), isEmpty);
    });

    test('null und leere Liste liefern nichts', () {
      expect(blutVorschlaegeAufbereiten(null, {}), isEmpty);
      expect(blutVorschlaegeAufbereiten(const [], {}), isEmpty);
    });

    test('fremde Einträge in der Liste werden übersprungen', () {
      final l = blutVorschlaegeAufbereiten(['unsinn', 42, _v('crp', wert: '2.8')], {});
      expect(l, hasLength(1));
    });

    // ⚠️ Der Server gleicht verlesene Parameternamen tolerant ab — ohne das
    // war ein echter Scan nicht lesbar. Aber „ähnlich" ist kein Grund, eine
    // Zahl vorzuhaken: gemessen kam "Calcium (Serum)" als "Galdum (Berum)"
    // zurück und lag näher an Kalium als an Calcium.
    test('ein nur ähnlich erkannter Name wird NICHT vorangehakt', () {
      final l = blutVorschlaegeAufbereiten(
          [_v('crp', wert: '2.8', unscharf: true)], {});
      expect(l.first.unscharf, isTrue);
      expect(l.first.gewaehlt, isFalse,
          reason: 'unscharfer Name darf nie ohne Ansehen übernommen werden');
      expect(l.first.uebernehmbar, isTrue,
          reason: 'anhaken darf man ihn trotzdem — nur nicht von allein');
    });

    test('ohne das Feld gilt der Name als zeichengleich', () {
      final roh = _v('crp', wert: '2.8')..remove('unscharf');
      final l = blutVorschlaegeAufbereiten([roh], {});
      expect(l.first.unscharf, isFalse);
      expect(l.first.gewaehlt, isTrue);
    });
  });
}
