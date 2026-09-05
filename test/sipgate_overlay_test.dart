import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:icd360sev_vorsitzer/services/notification_service.dart';
import 'package:icd360sev_vorsitzer/services/sipgate_service.dart';
import 'package:icd360sev_vorsitzer/widgets/sipgate_anruf_overlay.dart';


/// Die Nummer, wie sie in der Karte STEHT — verdeckt.
///
/// 🔴 Die Karte schwebt über allem und ist von einem Meter Abstand zu lesen;
/// seit dem 31.08.2026 steht dort nicht mehr die ganze Rufnummer. Diese Tests
/// verlangten vorher die volle Nummer — sie prüfen jetzt das Gegenteil, und
/// zwar in beide Richtungen: die verdeckte Form MUSS da sein, die volle DARF
/// NICHT. Nur so fällt auf, wenn die Verdeckung wieder herausfällt.
const nummerVoll = '+4971112345';
// ⚠️ Von Hand geschrieben und darum nachgezählt: `+4971112345` hat ZEHN
/// Ziffern, sichtbar bleiben fünf, also stehen dort genau fünf Punkte. Meine
/// erste Fassung hatte sechs — und der Test schlug fehl, obwohl der Code
/// stimmte.
const nummerVerdeckt = '+49·····345';

/// Die schwebende Gesprächskarte — und vor allem: dass sie NICHTS blockiert.
///
/// ⚠️ WARUM DIESER TEST DER WICHTIGSTE HIER IST
/// In `main.dart` steht der frühere Weg über `MaterialApp.builder` mit
/// `Positioned.fill(child: GlobalChatOverlay())` **auskommentiert**, weil er auf
/// Android die Knöpfe blockierte — eine Fläche über der ganzen App nimmt jede
/// Berührung an, auch dort, wo sie nichts zeichnet. Es sah nach einem Freeze
/// aus, und die Ursache war unsichtbar.
///
/// Diese Karte hängt deshalb als `OverlayEntry` mit einem `Positioned` in
/// Kartengrösse im Navigator-Overlay. Ob das so bleibt, prüft der Test „ein
/// Knopf darunter ist weiter erreichbar" — er fällt, sobald jemand daraus
/// wieder ein `Positioned.fill` macht.
void main() {
  final dienst = SipgateService();

  /// Baut eine App mit demselben `navigatorKey`, den das Overlay benutzt, und
  /// einem Knopf am unteren Rand — also weit weg von der Karte.
  Widget appMitKnopf(VoidCallback beiDruck) => MaterialApp(
        navigatorKey: NotificationService.navigatorKey,
        home: Scaffold(
          body: Column(
            children: [
              const Spacer(),
              ElevatedButton(
                onPressed: beiDruck,
                child: const Text('Knopf darunter'),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      );

  SipgateGespraech gespraech(SipgateGespraechStand stand, {String? name}) =>
      SipgateGespraech(
        nummer: nummerVoll,
        name: name,
        eingehend: stand == SipgateGespraechStand.klingelt,
        stand: stand,
        verbundenSeit: stand == SipgateGespraechStand.verbunden
            ? DateTime.now().subtract(const Duration(seconds: 187))
            : null,
      );

  tearDown(() {
    // Der Dienst und das Overlay sind Singletons — ohne Aufräumen läuft die
    // Karte in den nächsten Test hinein.
    dienst.zustand.value = const SipgateZustand();
    SipgateAnrufOverlay().unterdruecken(false);
  });

  testWidgets('ohne Gespräch ist keine Karte da', (t) async {
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    await t.pump();
    expect(find.text(nummerVerdeckt), findsNothing);
  });

  testWidgets('bei laufendem Gespräch erscheint Nummer und Dauer', (t) async {
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(SipgateGespraechStand.verbunden));
    await t.pump();

    expect(find.text(nummerVerdeckt), findsOneWidget);
    // ⚠️ Und die volle Nummer DARF NICHT dastehen. Ohne diese Zeile bestünde
    // der Test auch dann, wenn beides zu sehen wäre — die Verdeckung wäre
    // wirkungslos, ohne dass irgendetwas fehlschlägt.
    expect(find.textContaining(nummerVoll), findsNothing);
    // 187 Sekunden → 03:07. Die Uhr, nicht „187".
    expect(find.textContaining('03:07'), findsOneWidget);
  });

  testWidgets('mit Namen steht der Name oben und die Nummer neben der Uhr',
      (t) async {
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value = SipgateZustand(
        gespraech: gespraech(SipgateGespraechStand.verbunden, name: 'Jobcenter'));
    await t.pump();

    expect(find.text('Jobcenter'), findsOneWidget);
    // Ein Name allein sagt nicht, welche der drei Nummern eines Amtes man
    // erreicht hat — deshalb steht sie mit dabei.
    expect(find.textContaining(nummerVerdeckt), findsOneWidget);
  });

  testWidgets('ein Knopf DARUNTER ist weiter erreichbar', (t) async {
    // Der eigentliche Zweck dieser Datei. Fällt dieser Test, blockiert das
    // Overlay die App — genau der Fehler, an dem GlobalChatOverlay gescheitert
    // ist.
    var gedrueckt = 0;
    await t.pumpWidget(appMitKnopf(() => gedrueckt++));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(SipgateGespraechStand.verbunden));
    await t.pump();

    expect(find.text(nummerVerdeckt), findsOneWidget,
        reason: 'die Karte muss da sein, sonst prüft der Test nichts');

    await t.tap(find.text('Knopf darunter'));
    await t.pump();
    expect(gedrueckt, 1,
        reason: 'Das Overlay darf nur dort Berührungen annehmen, wo es auch '
            'zeichnet. Ein Positioned.fill nimmt sie überall an — dann wirkt '
            'die App eingefroren, ohne dass etwas rot wird.');
  });

  testWidgets('ein eingehender Anruf zeigt Annehmen und Ablehnen', (t) async {
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(SipgateGespraechStand.klingelt));
    await t.pump();

    expect(find.text('Eingehender Anruf'), findsOneWidget);
    // Beide Knöpfe, damit man aus jedem Bildschirm annehmen kann — vorher blieb
    // ein eingehender Anruf unbemerkt, solange etwas anderes offen war.
    expect(find.byIcon(Icons.call), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
  });

  testWidgets('beim Wählen steht „Wählt …" und nur Auflegen', (t) async {
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(SipgateGespraechStand.waehlt));
    await t.pump();

    expect(find.text('Wählt …'), findsOneWidget);
    expect(find.byIcon(Icons.call_end), findsOneWidget);
    expect(find.byIcon(Icons.call), findsNothing,
        reason: 'Annehmen gibt es nur bei einem eingehenden Anruf');
  });

  testWidgets('das Ende des Gesprächs nimmt die Karte weg', (t) async {
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(SipgateGespraechStand.verbunden));
    await t.pump();
    expect(find.text(nummerVerdeckt), findsOneWidget);

    dienst.zustand.value = const SipgateZustand();
    await t.pump();
    expect(find.text(nummerVerdeckt), findsNothing);
  });

  testWidgets('unterdruecken() blendet sie aus und wieder ein', (t) async {
    // Der sipgate-Bildschirm zeigt das Gesprächsfeld selbst; zweimal dasselbe
    // würde nur die Wähltastatur verdecken.
    await t.pumpWidget(appMitKnopf(() {}));
    SipgateAnrufOverlay().aktivieren();
    dienst.zustand.value =
        SipgateZustand(gespraech: gespraech(SipgateGespraechStand.verbunden));
    await t.pump();
    expect(find.text(nummerVerdeckt), findsOneWidget);

    SipgateAnrufOverlay().unterdruecken(true);
    await t.pump();
    expect(find.text(nummerVerdeckt), findsNothing);

    SipgateAnrufOverlay().unterdruecken(false);
    await t.pump();
    expect(find.text(nummerVerdeckt), findsOneWidget);
  });

  group('zwei Beine und Konferenz', () {
    SipgateGespraech bein(String nummer, String name,
            {bool gehalten = false, int sek = 90}) =>
        SipgateGespraech(
          nummer: nummer,
          name: name,
          eingehend: false,
          stand: SipgateGespraechStand.verbunden,
          verbundenSeit: DateTime.now().subtract(Duration(seconds: sek)),
          gehalten: gehalten,
        );

    testWidgets('beim zweiten Gespräch steht dabei, WER gehalten wird',
        (t) async {
      // Sonst wundert man sich, warum die zweite Person schweigt.
      await t.pumpWidget(appMitKnopf(() {}));
      SipgateAnrufOverlay().aktivieren();
      dienst.zustand.value = SipgateZustand(
        gespraech: bein(nummerVoll, 'Jobcenter'),
        zweites: bein('+4916087654321', 'Frau Gradinar', gehalten: true),
      );
      await t.pump();

      expect(find.text('Jobcenter'), findsOneWidget);
      expect(find.textContaining('hält: Frau Gradinar'), findsOneWidget);
    });

    testWidgets('die Konferenz nennt beide Teilnehmer', (t) async {
      await t.pumpWidget(appMitKnopf(() {}));
      SipgateAnrufOverlay().aktivieren();
      dienst.zustand.value = SipgateZustand(
        gespraech: bein(nummerVoll, 'Jobcenter'),
        zweites: bein('+4916087654321', 'Frau Gradinar'),
        konferenz: true,
      );
      await t.pump();

      // Eine Konferenz mit einem Amt und einem Mitglied darf nicht wie ein
      // einzelner Anruf aussehen — beide Namen gehören sichtbar hin.
      expect(find.textContaining('Konferenz:'), findsOneWidget);
      expect(find.textContaining('Jobcenter'), findsOneWidget);
      expect(find.textContaining('Frau Gradinar'), findsOneWidget);
      expect(find.byIcon(Icons.groups), findsOneWidget);
    });

    testWidgets('auch in der Konferenz bleibt ein Knopf darunter erreichbar',
        (t) async {
      // Dieselbe Zusage wie beim einzelnen Gespräch, für den zweiten Rahmen —
      // er hat eigenen Code und könnte sie sonst einzeln verlieren.
      var gedrueckt = 0;
      await t.pumpWidget(appMitKnopf(() => gedrueckt++));
      SipgateAnrufOverlay().aktivieren();
      dienst.zustand.value = SipgateZustand(
        gespraech: bein(nummerVoll, 'Jobcenter'),
        zweites: bein('+4916087654321', 'Frau Gradinar'),
        konferenz: true,
      );
      await t.pump();
      await t.tap(find.text('Knopf darunter'));
      await t.pump();
      expect(gedrueckt, 1);
    });
  });

  group('Zustand: was die Konferenz erlaubt', () {
    test('verbundeneBeine zählt nur, was wirklich verbunden ist', () {
      final z = SipgateZustand(
        gespraech: SipgateGespraech(
            nummer: 'a',
            eingehend: false,
            stand: SipgateGespraechStand.verbunden,
            verbundenSeit: DateTime.now()),
        zweites: const SipgateGespraech(
            nummer: 'b', eingehend: false, stand: SipgateGespraechStand.waehlt),
      );
      expect(z.beine, hasLength(2));
      expect(z.verbundeneBeine, 1,
          reason: 'ein wählendes Bein kann man nicht zusammenschalten');
    });

    test('ohne Gespräch ist alles leer', () {
      const z = SipgateZustand();
      expect(z.beine, isEmpty);
      expect(z.verbundeneBeine, 0);
      expect(z.konferenz, isFalse);
    });
  });
}
