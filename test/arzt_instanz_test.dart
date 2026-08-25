import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/arzt_instanz.dart';
import 'package:icd360sev_vorsitzer/widgets/korrespondenz_attachments_widget.dart';

void main() {
  group('arztInstanzAusType', () {
    test('Basis-Schlüssel ohne Zusatz ist Instanz 1', () {
      for (final b in const [
        'gesundheit_augenarzt', 'gesundheit_hno', 'gesundheit_md',
        'gesundheit_rheumatologie', 'gesundheit_krankenhaus',
      ]) {
        expect(arztInstanzAusType(b), 1, reason: b);
      }
    });

    test('einstellig wie bisher', () {
      for (var i = 2; i <= 9; i++) {
        expect(arztInstanzAusType('gesundheit_krankenhaus_$i'), i);
      }
    });

    test('⚠️ der Fehlerfall: zweistellig war vorher Instanz 1', () {
      // `_([2-9])$` traf hier nicht — der zehnte Eintrag hat den ersten
      // überschrieben, lautlos.
      expect(arztInstanzAusType('gesundheit_krankenhaus_10'), 10);
      expect(arztInstanzAusType('gesundheit_krankenhaus_21'), 21);
      expect(arztInstanzAusType('gesundheit_krankenhaus_127'), 127);
    });

    test('keine zwei Instanzen teilen sich eine Nummer', () {
      final gesehen = <int>{};
      for (var i = 1; i <= 40; i++) {
        final n = arztInstanzAusType(arztTypeFuerInstanz('gesundheit_krankenhaus', i));
        expect(gesehen.add(n), isTrue, reason: 'Instanz $i kollidiert mit $n');
        expect(n, i);
      }
    });

    test('Unsinn fällt auf 1 zurück, statt zu werfen', () {
      expect(arztInstanzAusType(''), 1);
      expect(arztInstanzAusType('gesundheit_krankenhaus_'), 1);
      expect(arztInstanzAusType('gesundheit_krankenhaus_x'), 1);
    });
  });

  group('arztTypeFuerInstanz', () {
    test('Instanz 1 trägt keinen Zusatz', () {
      expect(arztTypeFuerInstanz('gesundheit_hno', 1), 'gesundheit_hno');
      expect(arztTypeFuerInstanz('gesundheit_hno', 0), 'gesundheit_hno');
    });
    test('ab 2 hängt die Nummer an', () {
      expect(arztTypeFuerInstanz('gesundheit_hno', 2), 'gesundheit_hno_2');
      expect(arztTypeFuerInstanz('gesundheit_hno', 12), 'gesundheit_hno_12');
    });
  });

  group('Anhang-Schlüssel trennt auch zweistellige Instanzen', () {
    test('Instanz 1 und 10 bekommen verschiedene modul-Schlüssel', () {
      final eins = vorsorgeAnhangModul(
          userId: 13, type: 'gesundheit_krankenhaus', key: 'darmspiegelung');
      final zehn = vorsorgeAnhangModul(
          userId: 13, type: 'gesundheit_krankenhaus_10', key: 'darmspiegelung');
      expect(eins, isNot(zehn));
      expect(zehn, startsWith('vs10_'));
    });

    test('modul bleibt unter der Spaltenbreite VARCHAR(50)', () {
      final m = vorsorgeAnhangModul(
          userId: 999999, type: 'gesundheit_hno_127', key: 'schilddruese_sono');
      expect(m.length, lessThanOrEqualTo(50), reason: m);
    });
  });
}
