import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/utils/gespraechsqualitaet.dart';
import 'package:icd360sev_vorsitzer/widgets/guete_anzeige.dart';

/// Die Farben der Güte-Anzeige auf der Gesprächskarte.
///
/// 🔴 WARUM GERECHNET UND NICHT GEWÄHLT. Die Karte ist im Gespräch grün
/// (`#2E7D32`). Ein sattes Rot darauf kommt auf **1,61:1**, das dunklere
/// `#C62828` sogar auf 1,47:1 — WCAG 1.4.11 verlangt 3:1 für Bedienelemente.
/// Rot und Dunkelgrün liegen in der Helligkeit einfach zu nah beieinander;
/// das sieht man dem Quelltext nicht an, und auf dem Schirm merkt man es erst,
/// wenn die Verbindung schlecht ist — also im ungünstigsten Moment.
///
/// Deshalb sitzt die Anzeige auf einer dunklen Pille. Dieser Test rechnet die
/// Kontraste nach, statt sie zu behaupten.
void main() {
  const karte = Color(0xFF2E7D32);

  double kanal(double c) =>
      c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

  double leuchtdichte(Color c) =>
      0.2126 * kanal((c.r * 255).roundToDouble() / 255) +
      0.7152 * kanal((c.g * 255).roundToDouble() / 255) +
      0.0722 * kanal((c.b * 255).roundToDouble() / 255);

  double kontrast(Color a, Color b) {
    final la = leuchtdichte(a), lb = leuchtdichte(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// Die Pille über der Karte, ausgerechnet.
  Color pilleAuf(Color grund) =>
      Color.alphaBlend(kGuetePilleGrund, grund);

  test('jede Stufe erreicht 3:1 auf der Pille', () {
    final grund = pilleAuf(karte);
    for (final st in QualitaetsStufe.values) {
      final k = kontrast(gueteFarbeHell(st), grund);
      expect(k, greaterThanOrEqualTo(3.0),
          reason: '$st: nur ${k.toStringAsFixed(2)}:1 gegen ${grund.toARGB32().toRadixString(16)}');
    }
  });

  test('der weisse Text erreicht 4,5:1 — die Schranke für kleine Schrift', () {
    // ⚠️ Deshalb bleibt der TEXT weiss und wird nicht eingefärbt: bei 11 dp
    // gilt 4,5:1, und das schafft von den vier Farben nur Weiss sicher.
    expect(kontrast(Colors.white, pilleAuf(karte)), greaterThanOrEqualTo(4.5));
  });

  test('ohne Pille würde Rot durchfallen — die Pille ist kein Schmuck', () {
    // Gegenprobe zur Begründung oben: nähme man die Farben direkt auf die
    // Karte, wäre genau die schlimmste Stufe die unsichtbarste.
    final k = kontrast(gueteFarbeHell(QualitaetsStufe.unbrauchbar), karte);
    expect(k, lessThan(3.0),
        reason: 'Wenn das je über 3:1 kommt, ist die Pille verzichtbar — '
            'dann diesen Test streichen, nicht die Begründung.');
  });

  test('jede Stufe hat ein eigenes Symbol', () {
    // ⚠️ Farbe ist nicht der einzige Träger. Hellgrün und Gelb kommen auf
    // 7,07:1 bzw. 7,17:1 — fast dieselbe Helligkeit, also ohne Farbwahrnehmung
    // ununterscheidbar. Die Balkenzahl trägt die Stufe in der FORM.
    final symbole = QualitaetsStufe.values.map(gueteSymbol).toSet();
    expect(symbole.length, QualitaetsStufe.values.length,
        reason: 'zwei Stufen teilen sich ein Symbol');
  });

  test('und jede Stufe hat ein Wort', () {
    for (final st in QualitaetsStufe.values) {
      expect(gueteStufeText(st), isNotEmpty);
    }
  });

  testWidgets('die Balken zeigen wie viel von wie viel', (t) async {
    // 🔴 Die Material-Symbole zeichnen NUR die erreichten Balken; bei
    // „schlecht" war das ein einzelner Strich, der bei 13 dp kaum zu sehen war.
    // Jetzt liegen die vollen drei blass darunter — zwei Symbole übereinander.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GueteBalken(
            stufe: QualitaetsStufe.schlecht,
            groesse: 14,
            farbe: gueteFarbeHell(QualitaetsStufe.schlecht)),
      ),
    ));
    expect(find.byType(Icon), findsNWidgets(2));

    // ⚠️ „kaum verständlich" bekommt EIN eigenes Zeichen, keine null Balken:
    // null Balken und „noch nichts gemessen" sähen sonst gleich aus.
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: GueteBalken(
            stufe: QualitaetsStufe.unbrauchbar,
            groesse: 14,
            farbe: gueteFarbeHell(QualitaetsStufe.unbrauchbar)),
      ),
    ));
    expect(find.byType(Icon), findsOneWidget);
  });
}
