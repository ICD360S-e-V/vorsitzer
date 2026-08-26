import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/blut_parameter_liste.dart';

void main() {
  group('blutParameterListe', () {
    final m = blutParameterListe(true);
    final w = blutParameterListe(false);

    test('alle 208 Parameter des Katalogs', () {
      expect(m, hasLength(208));
      expect(w, hasLength(208));
    });

    // ⚠️ Der Schlüssel IST der Speicher: er steht so in der verschlüsselten
    // Historie und in blut_parameter.php auf dem Server. Zwei Einträge mit
    // demselben Schlüssel hieße, dass ein Wert den anderen überschreibt.
    test('kein Schlüssel doppelt', () {
      final keys = m.map((p) => p['key']).toList();
      expect(keys.toSet(), hasLength(keys.length));
    });

    test('jeder Eintrag hat die Felder, die der Dialog liest', () {
      for (final p in m) {
        expect(p['key'], isA<String>(), reason: 'key fehlt');
        expect((p['key'] as String).isNotEmpty, isTrue);
        expect(p['label'], isA<String>(), reason: '${p['key']}: label fehlt');
        expect(p['gruppe'], isA<String>(), reason: '${p['key']}: gruppe fehlt');
        // min/max liest der Dialog als num — auch bei qualitativen, dort
        // ungenutzt, aber ein fehlendes Feld wäre ein Absturz statt einer Lücke.
        expect(p['min'], isA<num>(), reason: '${p['key']}: min fehlt');
        expect(p['max'], isA<num>(), reason: '${p['key']}: max fehlt');
      }
    });

    test('numerische Parameter haben min <= max', () {
      for (final p in m.where((p) => p['qualitativ'] != true)) {
        expect((p['min'] as num) <= (p['max'] as num), isTrue,
            reason: '${p['key']}: min ${p['min']} > max ${p['max']}');
      }
    });

    // ⚠️ Diese 36 gab es vor dem 25.08.2026 schon. Ihre Grenzwerte liest
    // jemand seit Monaten; sie zu verschieben wäre eine stille Änderung an
    // etwas, das wie eine Messung aussieht.
    test('die 36 bestehenden Parameter sind unverändert', () {
      final nach = {for (final p in m) p['key']: p};
      const erwartet = {
        'erythrozyten': [4.3, 5.9], 'leukozyten': [4.0, 10.0],
        'thrombozyten': [150.0, 400.0], 'haemoglobin': [13.5, 17.5],
        'haematokrit': [40.0, 52.0], 'natrium': [136.0, 145.0],
        'kalium': [3.5, 5.0], 'calcium': [2.2, 2.65],
        'cholesterin': [0.0, 200.0], 'ldl_cholesterin': [0.0, 130.0],
        'glucose_nuechtern': [70.0, 100.0], 'crp': [0.0, 5.0],
        'vitamin_b12': [200.0, 900.0], 'folsaeure': [3.0, 17.0],
        'vitamin_d3': [30.0, 100.0], 'ferritin': [30.0, 400.0],
      };
      erwartet.forEach((key, grenzen) {
        expect(nach[key], isNotNull, reason: '$key ist verschwunden');
        expect(nach[key]!['min'], grenzen[0], reason: '$key: min verschoben');
        expect(nach[key]!['max'], grenzen[1], reason: '$key: max verschoben');
      });
    });

    test('geschlechtsabhängige Bereiche unterscheiden sich wirklich', () {
      final mm = {for (final p in m) p['key']: p};
      final ww = {for (final p in w) p['key']: p};
      expect(mm['haemoglobin']!['min'], isNot(ww['haemoglobin']!['min']));
      expect(mm['ferritin']!['max'], isNot(ww['ferritin']!['max']));
      // und die, die für beide gleich sind, bleiben gleich
      expect(mm['kalium']!['min'], ww['kalium']!['min']);
    });

    test('innerhalb einer Gruppe alphabetisch — bei 170 Feldern die einzige Chance, etwas zu finden', () {
      final proGruppe = <String, List<String>>{};
      for (final p in m) {
        proGruppe.putIfAbsent(p['gruppe'] as String, () => []).add(p['label'] as String);
      }
      proGruppe.forEach((g, labels) {
        final sortiert = [...labels]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
        expect(labels, sortiert, reason: 'Gruppe "$g" ist nicht alphabetisch');
      });
    });
  });
}
