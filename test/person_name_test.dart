import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/person_name.dart';

/// Der Anlass ist ein echter Datensatz, kein gedachter.
///
/// V10001 hat `vorname = 'Ilies-Cristian'` **und** `vorname2 = 'Cristian'`. Die
/// vier Stellen im Client, die beide Felder mit `join(' ')` zusammenhängen,
/// erzeugen daraus „Ilies-Cristian Cristian Doe" — einen Namen, den es nicht
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
      // V10001, der Auslöser.
      expect(vornameVoll('Ilies-Cristian', 'Cristian'), 'Ilies-Cristian');
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
        personName('Ilies-Cristian', 'Cristian', 'Doe'),
        'Ilies-Cristian Doe',
      );
    });

    test('behält mehrteilige Vornamen vollständig', () {
      // K10001: der alte Leerzeichen-Split hat hieraus Vorname „Andreea" und
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
      expect(nachnameOder('Doe', fallbackName: 'X Y'), 'Doe');
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

  group('initialen', () {
    test('trennt auch am Bindestrich', () {
      // ⚠️ „Ilies-Cristian" sind zwei Namen. Ohne den Bindestrich käme `id`
      // heraus statt `icd` — und icd@icd360s.de ist die Adresse, die es gibt.
      expect(initialen('Ilies-Cristian', 'Cristian', 'Doe'), 'icd');
      expect(initialen('Michaela-Christine', null, 'Weber'), 'mcw');
      expect(initialen('Marian-Sevastian-Robert', null, 'Demo'), 'msrd');
    });

    test('nimmt jeden Teil eines mehrteiligen Vornamens', () {
      expect(initialen('Andreea Denisa Camelia', null, 'Raduica'), 'adcr');
    });

    test('zählt einen doppelten vorname2 nicht zweimal', () {
      // Sonst hätte V10001 ein `c` zu viel.
      expect(initialen('Ilies-Cristian', 'Cristian', 'Doe'),
          isNot(contains('cc')));
    });

    test('leere Eingabe ergibt leer', () {
      expect(initialen(null, null, null), '');
      expect(initialen('  ', '', '  '), '');
    });
  });

  group('vereinsAdresse', () {
    String adr(String rolle, String nr, String vor, String? vor2, String nach) =>
        vereinsAdresse(
            rolle: rolle,
            mitgliedernummer: nr,
            vorname: vor,
            vorname2: vor2,
            nachname: nach,
            domain: 'icd360s.de');

    test('Ämter bekommen ihre Initialen', () {
      // ⚠️ Die beiden ersten sind keine Erfindung: `icd@` und `mcw@` benutzen
      // die zwei Vorsitzenden seit jeher. Die Regel schreibt die gelebte
      // Praxis auf, statt eine neue zu erfinden.
      expect(adr('vorsitzer', 'V10001', 'Ilies-Cristian', 'Cristian', 'Doe'),
          'icd@icd360s.de');
      expect(adr('vorsitzer', 'V10002', 'Michaela-Christine', null, 'Weber'),
          'mcw@icd360s.de');
      expect(adr('schatzmeister', 'S10001', 'Adela', null, 'Musterfrau'),
          'am@icd360s.de');
      expect(adr('kassierer', 'K10001', 'Andreea Denisa Camelia', null, 'Raduica'),
          'adcr@icd360s.de');
    });

    test('alle übrigen bekommen die Mitgliedsnummer', () {
      expect(adr('mitglied', 'M10002', 'Muster', null, 'Paula'),
          'M10002@icd360s.de');
      expect(adr('jugendmitglied', 'J19999', 'mykhailo', null, 'tsynhalov'),
          'J19999@icd360s.de');
      expect(adr('anonymous', 'ANON_0103', '', null, ''),
          'ANON_0103@icd360s.de');
    });

    test('ohne verwertbaren Namen bleibt die Nummer', () {
      // Besser als ein leeres `@icd360s.de`.
      expect(adr('vorsitzer', 'V99999', '', null, ''), 'V99999@icd360s.de');
    });

    test('die heutigen sechs Ämter kollidieren nicht', () {
      // ⚠️ Gleiche Initialen ergäben dieselbe Adresse — und weil alles im
      // Auffang-Postfach landet, fiele das niemandem auf. Hier fällt es auf.
      final adressen = [
        adr('vorsitzer', 'V10001', 'Ilies-Cristian', 'Cristian', 'Doe'),
        adr('vorsitzer', 'V10002', 'Michaela-Christine', null, 'Weber'),
        adr('schatzmeister', 'S10001', 'Adela', null, 'Musterfrau'),
        adr('kassierer', 'K10001', 'Andreea Denisa Camelia', null, 'Raduica'),
        adr('mitgliedergrunder', 'M10004', 'Marian-Sevastian-Robert', null, 'Demo'),
        adr('mitgliedergrunder', 'M10001', 'Danut-Marius', null, 'Gradinar'),
      ];
      expect(adressen.toSet().length, adressen.length,
          reason: 'zwei Ämter teilen sich eine Adresse: $adressen');
    });

    test('die Rolle wird ohne Rücksicht auf Schreibweise erkannt', () {
      expect(adr('Vorsitzer', 'V10001', 'Ilies-Cristian', 'Cristian', 'Doe'),
          'icd@icd360s.de');
      expect(adr('  VORSITZER  ', 'V10001', 'Ilies-Cristian', 'Cristian', 'Doe'),
          'icd@icd360s.de');
    });
  });
}
