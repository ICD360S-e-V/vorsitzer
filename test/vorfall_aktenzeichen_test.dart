import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_inkasso.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Das Aktenzeichen gehört an den Vorfall, nicht in seine Bezeichnung.
///
/// ⚠️ Bis 21.08.2026 hatte der Vorfall nur EIN Textfeld. Also wurde beides
/// hineingeschrieben — „Aktenzeichen: 6865140/26/0 - Miete und
/// Nebenkosten". Der Widerspruch las das Aktenzeichen aus einer eigenen
/// Tabelle, die leer war, und baute daraus einen Betreff ganz ohne
/// Bezugsnummer: „Widerspruch — Aktenzeichen: 6865140/26/0 - Miete und
/// Nebenkosten". Ein Inkassobüro legt nach der Nummer ab; steht sie nicht
/// an ihrem Platz, landet das Schreiben im Zweifel nirgends.
void main() {
  group('Betreff', () {
    test('mit Aktenzeichen steht die Nummer vorn', () {
      // Genau der Fall des Mitglieds V10002 nach der Trennung.
      expect(widerspruchBetreff('6865140/26/0', 'Miete und Nebenkosten'),
          'Aktenzeichen 6865140/26/0 - Widerspruch');
    });

    test('ohne Aktenzeichen bleibt die Sache — aber sie ist der Notnagel', () {
      expect(widerspruchBetreff(null, 'Miete und Nebenkosten'),
          'Widerspruch — Miete und Nebenkosten');
      expect(widerspruchBetreff('   ', null), 'Widerspruch gegen Ihre Forderung');
    });

    test('⚠️ die Nummer wird nicht doppelt genannt', () {
      // Sonst stünde nach der Trennung „Aktenzeichen 6865140/26/0 -
      // Widerspruch" im Kopf und „Aktenzeichen: 6865140/26/0 - Miete …"
      // gleich darunter als Sache.
      final b = widerspruchBetreff('6865140/26/0', 'Miete und Nebenkosten');
      expect('6865140/26/0'.allMatches(b).length, 1);
    });
  });

  group('Titel des Vorfalls', () {
    test('Nummer zuerst, dann die Sache', () {
      expect(
          vorfallTitel(const {
            'aktenzeichen': '6865140/26/0',
            'bezeichnung': 'Miete und Nebenkosten',
          }),
          '6865140/26/0 · Miete und Nebenkosten');
    });

    test('fehlt eines, bleibt das andere allein stehen', () {
      expect(vorfallTitel(const {'bezeichnung': 'Miete'}), 'Miete');
      expect(vorfallTitel(const {'aktenzeichen': 'AZ-9'}), 'AZ-9');
      expect(vorfallTitel(const {}), '(ohne Bezeichnung)');
      // Leerzeichen sind kein Inhalt — sonst stünde da „ · Miete".
      expect(vorfallTitel(const {'aktenzeichen': '  ', 'bezeichnung': 'Miete'}), 'Miete');
    });
  });
}
