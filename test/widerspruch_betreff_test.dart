import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/widgets/vermieter_widerspruch.dart';

/// Der Betreff trägt das Aktenzeichen — auch wenn es später eintrifft.
///
/// ⚠️ Der Fehler, den dieser Test festhält: `_VorfallDetail` baut die
/// Reiter sofort und lädt seine Aktenzeichen erst danach. Beim ersten
/// Aufbau war `aktenzeichen` null, der Betreff bekam die Ersatzfassung —
/// und als die Nummer ankam, stand sie nirgends, weil nichts sie
/// nachzog. Auf dem Gerät sah man dauerhaft „Widerspruch gegen Ihre
/// Forderung".
void main() {
  test('mit Aktenzeichen steht es im Betreff', () {
    expect(widerspruchBetreff('9763281440', 'Mietrückstand 2026'),
        'Aktenzeichen 9763281440 - Widerspruch');
  });

  test('ohne Aktenzeichen tritt die Bezeichnung ein', () {
    expect(widerspruchBetreff(null, 'Mietrückstand 2026'),
        'Widerspruch — Mietrückstand 2026');
    expect(widerspruchBetreff('', 'Mietrückstand 2026'),
        'Widerspruch — Mietrückstand 2026');
  });

  test('ohne beides bleibt ein vollständiger Satz', () {
    // ⚠️ Nie nur „Widerspruch": ein Betreff aus einem Wort ordnet nichts zu.
    expect(widerspruchBetreff(null, null), 'Widerspruch gegen Ihre Forderung');
    expect(widerspruchBetreff('  ', '  '), 'Widerspruch gegen Ihre Forderung');
  });

  test('Leerzeichen um das Aktenzeichen stören nicht', () {
    expect(widerspruchBetreff('  9763281440  ', null),
        'Aktenzeichen 9763281440 - Widerspruch');
  });

/// ⚠️ Der Fehler, der zweimal auftrat: der Vorschlag stand ZUERST da und
/// wurde danach vom gespeicherten Wert überschrieben — der bei jedem
/// Widerspruch leer ist, der vor Einführung des Feldes angelegt wurde.
/// Auf dem Gerät war der Betreff deshalb schlicht leer.
///
/// Die Regel, die daraus folgt und die dieser Test festhält: ein leerer
/// gespeicherter Wert darf NIE gewinnen.

  test('ein leerer gespeicherter Betreff gewinnt nie', () {
    // So rechnet der Reiter: erst laden, dann auffüllen.
    String betreffNachLaden(String? gespeichert, String? az) {
      var feld = gespeichert ?? '';
      if (feld.trim().isEmpty) feld = widerspruchBetreff(az, null);
      return feld;
    }

    expect(betreffNachLaden('', '9763281440'),
        'Aktenzeichen 9763281440 - Widerspruch');
    expect(betreffNachLaden(null, '9763281440'),
        'Aktenzeichen 9763281440 - Widerspruch');
    expect(betreffNachLaden('   ', '9763281440'),
        'Aktenzeichen 9763281440 - Widerspruch');
    // Ein eigener Text bleibt aber stehen.
    expect(betreffNachLaden('Meine eigene Zeile', '9763281440'), 'Meine eigene Zeile');
  });
}
