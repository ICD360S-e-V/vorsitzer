import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/person_name.dart';

/// Der Anlass ist ein echter Datensatz, kein gedachter.
///
/// V27655 hat `vorname = 'Ionut-Claudiu'` **und** `vorname2 = 'Claudiu'`. Die
/// vier Stellen im Client, die beide Felder mit `join(' ')` zusammenhängen,
/// erzeugen daraus „Ionut-Claudiu Claudiu Duinea" — einen Namen, den es nicht
/// gibt. Auf der Visitenkarte fällt das sofort auf; auf einer Vollmacht fällt
/// es erst auf, wenn eine Behörde nachfragt.
///
/// Die Regel steht an vier Stellen (drei davon in PHP auf dem Server, siehe
/// `vfPersonName()` in api/helpers/vorstand_funktion.php). Dieser Test ist die
/// einzige Stelle, an der ein Auseinanderdriften überhaupt auffallen kann —
/// das PHP liegt in keinem Repo.
void main() {
  group('vornameVoll', () {
    test('lässt einen vorname2 weg, der schon im vorname steckt', () {
      // V27655, der Auslöser.
      expect(vornameVoll('Ionut-Claudiu', 'Claudiu'), 'Ionut-Claudiu');
    });

    test('hängt einen echten zweiten Vornamen an', () {
      expect(vornameVoll('Beata', 'Maria'), 'Beata Maria');
    });

    test('vergleicht ohne Rücksicht auf Groß- und Kleinschreibung', () {
      expect(vornameVoll('Anne', 'anne'), 'Anne');
      expect(vornameVoll('ANNE-MARIE', 'marie'), 'ANNE-MARIE');
    });

    test('kommt mit leeren und fehlenden Feldern zurecht', () {
      expect(vornameVoll('Anna', ''), 'Anna');
      expect(vornameVoll('Anna', null), 'Anna');
      expect(vornameVoll('', 'Maria'), 'Maria');
      expect(vornameVoll(null, null), '');
      expect(vornameVoll('  Anna  ', '  '), 'Anna');
    });
  });

  group('personName', () {
    test('setzt Vor- und Nachnamen ohne Dublette zusammen', () {
      expect(
        personName('Ionut-Claudiu', 'Claudiu', 'Duinea'),
        'Ionut-Claudiu Duinea',
      );
    });

    test('behält mehrteilige Vornamen vollständig', () {
      // K91719: der alte Leerzeichen-Split hat hieraus Vorname „Andreea" und
      // Nachname „Denisa Camelia Raduica" gemacht.
      expect(
        personName('Andreea Denisa Camelia', null, 'Raduica'),
        'Andreea Denisa Camelia Raduica',
      );
    });

    test('fällt auf die abgeleitete Spalte `name` zurück', () {
      // Die fünf anonymisierten Konten haben keine Einzelfelder mehr.
      expect(
        personName('', '', '', fallbackName: 'Anonim #0103'),
        'Anonim #0103',
      );
    });

    test('nimmt den Rückfall NICHT, solange Einzelfelder gefüllt sind', () {
      expect(
        personName('Anna', null, 'Meier', fallbackName: 'Voellig Anders'),
        'Anna Meier',
      );
    });
  });

  group('nachnameOder', () {
    test('nimmt den Nachnamen, wenn es einen gibt', () {
      expect(nachnameOder('Duinea', fallbackName: 'X Y'), 'Duinea');
    });

    test('nimmt sonst den letzten Bestandteil von `name`', () {
      expect(nachnameOder('', fallbackName: 'Anna Maria Meier'), 'Meier');
    });

    test('gibt einen einteiligen Rückfall unverändert zurück', () {
      expect(nachnameOder(null, fallbackName: 'Anonim'), 'Anonim');
    });

    test('bleibt leer, wenn es gar nichts gibt', () {
      expect(nachnameOder(null), '');
      expect(nachnameOder('  ', fallbackName: '  '), '');
    });
  });
}
