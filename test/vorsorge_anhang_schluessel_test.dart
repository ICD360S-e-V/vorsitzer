import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/korrespondenz_attachments_widget.dart';

/// Die längsten Vorsorge-Schlüssel aus den fünf Arzt-Tabs.
///
/// Bewusst als Literal und nicht aus den Tabs gelesen: die Konstanten dort
/// sind privat, und ein Test, der seine Erwartung aus dem Prüfling zieht,
/// bestätigt nur sich selbst. Kommt ein längerer Schlüssel dazu, gehört er
/// hierher — und fällt genau dann auf, wenn die Grenze knapp wird.
const _laengsteSchluessel = [
  'schilddruese_sono', // HNO, 17 Zeichen — der längste reale
  'schlafapnoe',
  'retinopathie',
  'biologika_tb',
];

void main() {
  group('vorsorgeAnhangModul', () {
    test('trägt das Mitglied — zwei Mitglieder teilen sich nichts mehr', () {
      final a = vorsorgeAnhangModul(
          userId: 42, type: 'gesundheit_hno', key: 'schlafapnoe');
      final b = vorsorgeAnhangModul(
          userId: 43, type: 'gesundheit_hno', key: 'schlafapnoe');
      expect(a, isNot(b));
    });

    test('trennt die Arzt-Instanzen desselben Mitglieds', () {
      final erste = vorsorgeAnhangModul(
          userId: 42, type: 'gesundheit_hno', key: 'schlafapnoe');
      final zweite = vorsorgeAnhangModul(
          userId: 42, type: 'gesundheit_hno_2', key: 'schlafapnoe');
      expect(erste, isNot(zweite));
      expect(erste, startsWith('vs1_'));
      expect(zweite, startsWith('vs2_'));
    });

    test('ohne Instanz-Suffix ist es die erste', () {
      expect(vorsorgeAnhangModul(userId: 7, type: 'gesundheit_md', key: 'x'),
          'vs1_7_x');
    });

    // Der eigentliche Grund für diese Datei: `modul` ist VARCHAR(50). Ein
    // längerer Wert wird von MariaDB abgeschnitten — und zwei Untersuchungen,
    // deren Schlüssel sich erst hinter Zeichen 50 unterscheiden, lägen dann
    // still im selben Topf.
    test('bleibt auch im schlimmsten Fall unter VARCHAR(50)', () {
      for (final key in _laengsteSchluessel) {
        for (final type in ['gesundheit_krankenhaus', 'gesundheit_hno_9']) {
          // 999999 = eine sechsstellige Mitglieds-ID; der Verein hat heute
          // zweistellige, die Reserve ist Absicht.
          final modul =
              vorsorgeAnhangModul(userId: 999999, type: type, key: key);
          expect(modul.length, lessThanOrEqualTo(50),
              reason: 'zu lang für VARCHAR(50): $modul (${modul.length})');
        }
      }
    });

    test('die Fachrichtung fehlt bewusst — dafür gibt es je eine Tabelle', () {
      expect(vorsorgeAnhangModul(userId: 5, type: 'gesundheit_hno', key: 'k'),
          vorsorgeAnhangModul(userId: 5, type: 'gesundheit_augenarzt', key: 'k'));
    });
  });

  group('vorsorgeAnhangId', () {
    test('das Datum als Zahl, nicht als hashCode', () {
      expect(vorsorgeAnhangId('2026-08-17'), 20260817);
    });

    test('verschiedene Daten kollidieren nicht', () {
      final ids = [
        '2026-08-17',
        '2026-08-18',
        '2025-08-17',
        '2026-09-17',
      ].map(vorsorgeAnhangId).toSet();
      expect(ids.length, 4);
    });

    test('ist über Läufe hinweg stabil — genau das war hashCode nicht', () {
      expect(vorsorgeAnhangId('2015-01-01'), 20150101);
      expect(vorsorgeAnhangId('2040-12-31'), 20401231);
    });

    test('unbrauchbares Datum landet in einem Sammeleimer, wirft aber nicht', () {
      expect(vorsorgeAnhangId(''), 0);
      expect(vorsorgeAnhangId('kein-datum'), 0);
    });
  });

  group('ueberweisungAnhangModul', () {
    test('trägt Mitglied und Instanz', () {
      expect(ueberweisungAnhangModul(userId: 42, type: 'gesundheit_hno'),
          'ue1_42');
      expect(ueberweisungAnhangModul(userId: 42, type: 'gesundheit_hno_3'),
          'ue3_42');
      expect(ueberweisungAnhangModul(userId: 42, type: 'gesundheit_hno'),
          isNot(ueberweisungAnhangModul(userId: 43, type: 'gesundheit_hno')));
    });

    test('bleibt unter VARCHAR(50)', () {
      expect(
          ueberweisungAnhangModul(userId: 999999, type: 'gesundheit_krankenhaus_9')
              .length,
          lessThanOrEqualTo(50));
    });
  });
}
