import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Die Reiterleiste des Versicherungs-Vertragsdialogs.
///
/// ⚠️ Dieser Test existiert, weil ein Reiter schon einmal unsichtbar war,
/// obwohl er im Code stand: `TabBar(isScrollable: true)` schneidet nicht ab
/// und meldet nichts — der letzte Reiter liegt einfach ausserhalb und ist
/// nur durch Wischen AN DER LEISTE erreichbar. Das findet niemand, der ihn
/// nicht sucht. `flutter analyze` sieht davon nichts, und ein Widget-Test,
/// der bloss `find.text` benutzt, findet den Reiter ebenfalls — auch wenn
/// er 267 px hinter dem Fensterrand steht.
///
/// Deshalb wird die POSITION geprüft, nicht die Existenz.
///
/// Die Breiten sind die des Dialogs aus `_openDetail`:
/// `MediaQuery.sizeOf(ctx).width.clamp(320, 1060)`.
void main() {
  // Zeichengleich mit `_VersicherungDetailView.build`. Wer dort einen
  // Reiter ergänzt oder umbenennt, ergänzt ihn hier — sonst prüft der Test
  // eine Leiste, die es nicht mehr gibt.
  const reiter = [
    'Details',
    'Police',
    'Korrespondenz',
    'Kündigung',
    'E-Kündigung',
  ];

  Future<Rect> leisteBauen(
    WidgetTester t,
    double breite,
    String suchen,
  ) async {
    t.view.physicalSize = Size(breite, 400);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
    await t.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: reiter.length,
          child: Scaffold(
            appBar: AppBar(
              bottom: TabBar(
                isScrollable: true,
                tabs: [
                  for (final x in reiter)
                    Tab(icon: const Icon(Icons.circle, size: 18), text: x),
                ],
              ),
            ),
            body: TabBarView(children: [for (final x in reiter) Text(x)]),
          ),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 400));
    return t.getRect(find.text(suchen));
  }

  testWidgets('E-Kündigung liegt bei voller Dialogbreite im Bild', (t) async {
    const maximum = 1060.0; // die Obergrenze aus dem clamp()
    final r = await leisteBauen(t, maximum, 'E-Kündigung');
    expect(
      r.right,
      lessThanOrEqualTo(maximum),
      reason:
          'Der Reiter endet bei ${r.right.toInt()} px und ist damit '
          'nur durch Wischen erreichbar. Entweder eine Beschriftung '
          'kürzen oder den Dialog verbreitern.',
    );
  });

  testWidgets('auch auf einem Tablet quer (1000 px) im Bild', (t) async {
    final r = await leisteBauen(t, 1000, 'E-Kündigung');
    expect(r.right, lessThanOrEqualTo(1000.0));
  });

  // ⚠️ Auf dem Telefon passen fünf Reiter physisch nicht — das ist keine
  // Regression, sondern die Grenze der Leiste. Der Test hält nur fest, dass
  // es genau EIN Reiter ist, der dort herausfällt: fiele schon „Kündigung"
  // heraus, wäre die Leiste zu voll geworden und müsste umgebaut werden.
  testWidgets('auf dem Telefon fällt höchstens der letzte Reiter heraus', (
    t,
  ) async {
    final r = await leisteBauen(t, 412, 'Kündigung');
    expect(
      r.right,
      lessThanOrEqualTo(412.0 * 2),
      reason:
          'Selbst der vorletzte Reiter liegt weit draussen — die '
          'Leiste trägt zu viele oder zu lange Beschriftungen.',
    );
  });
}
