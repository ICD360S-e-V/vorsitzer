import 'dart:ui' as ui;

import 'package:flutter/material.dart';


import '../screens/sipgate_screen.dart';
import '../services/notification_service.dart';
import '../services/sipgate_service.dart';
import '../services/qualitaets_sonde.dart';
import '../services/untertitel_service.dart';
import 'guete_anzeige.dart';
import 'sekunden_takt.dart';

/// Schwebende Gesprächskarte, sichtbar über jedem Bildschirm.
///
/// WOFÜR
/// Ein laufendes Gespräch war bisher nur im sipgate-Bildschirm zu sehen. Wer
/// währenddessen eine Behördenkarte aufschlägt — also genau das, wofür man
/// anruft —, hatte weder die Dauer noch einen Auflegen-Knopf mehr vor sich.
/// Und ein eingehender Anruf blieb unbemerkt, solange ein anderer Bildschirm
/// offen war.
///
/// ⚠️ WARUM DAS EIN `OverlayEntry` IST UND NICHT `MaterialApp.builder`
/// In `main.dart` steht der Weg über `builder` mit
/// `Positioned.fill(child: GlobalChatOverlay())` — **auskommentiert**, weil er
/// auf Android die Knöpfe blockierte. Der Grund ist kein Rätsel: eine Fläche
/// über der ganzen App nimmt jede Berührung an, auch dort, wo sie nichts
/// zeichnet. Es sah nach einem Freeze aus.
///
/// Diese Karte hängt deshalb als `OverlayEntry` im Navigator-Overlay (dasselbe
/// Muster wie [LoginApprovalOverlay]) und benutzt ein `Positioned` in
/// Kartengrösse — **niemals** `Positioned.fill`. Getroffen wird nur, was man
/// auch sieht. `main.dart` wird nicht angefasst.
class SipgateAnrufOverlay {
  SipgateAnrufOverlay._internal();
  static final SipgateAnrufOverlay _instance = SipgateAnrufOverlay._internal();
  factory SipgateAnrufOverlay() => _instance;

  final SipgateService _dienst = SipgateService();
  OverlayEntry? _eintrag;
  bool _aktiv = false;
  bool _unterdrueckt = false;

  /// Wohin der Nutzer die Karte gezogen hat. `null` = Standardplatz.
  Offset? _position;

  /// Einmal beim App-Start aufrufen. Ab dann erscheint die Karte von selbst,
  /// sobald ein Gespräch läuft, und verschwindet, wenn es endet.
  void aktivieren() {
    if (_aktiv) return;
    _aktiv = true;
    _dienst.zustand.addListener(_pruefen);
    _pruefen();
  }

  /// Im sipgate-Bildschirm ausblenden: dort steht die Karte schon gross auf der
  /// Seite, zweimal dasselbe verdeckt nur die Wähltastatur.
  void unterdruecken(bool an) {
    if (_unterdrueckt == an) return;
    _unterdrueckt = an;
    _pruefen();
  }

  void _pruefen() {
    final laeuft = _dienst.zustand.value.gespraech != null;
    if (laeuft && !_unterdrueckt) {
      _zeigen();
    } else {
      _verbergen();
    }
  }

  void _zeigen() {
    if (_eintrag != null) return;
    final overlay = NotificationService.navigatorKey.currentState?.overlay;
    // Kein Overlay heisst: die App baut gerade erst auf. Kein Grund für einen
    // Fehler — beim nächsten Zustandswechsel (spätestens im Sekundentakt der
    // Dauer) ist es da.
    if (overlay == null) return;
    _position = null; // jedes Gespräch fängt am Standardplatz an
    _eintrag = OverlayEntry(builder: (ctx) => _Karte(overlay: this));
    overlay.insert(_eintrag!);
  }

  void _verbergen() {
    _eintrag?.remove();
    _eintrag = null;
  }

  void _verschieben(Offset delta, Size flaeche, Size karte) {
    final start = _position ?? _standardOrt(flaeche, karte);
    // Innerhalb des Bildschirms halten — eine Karte, die man an den Rand
    // schiebt und nicht mehr erreicht, wäre schlimmer als eine feste.
    _position = Offset(
      (start.dx + delta.dx).clamp(8.0, (flaeche.width - karte.width - 8).clamp(8.0, double.infinity)),
      (start.dy + delta.dy).clamp(8.0, (flaeche.height - karte.height - 8).clamp(8.0, double.infinity)),
    );
    _eintrag?.markNeedsBuild();
  }

  Offset _standardOrt(Size flaeche, Size karte) =>
      Offset((flaeche.width - karte.width) / 2, 12);
}

class _Karte extends StatelessWidget {
  const _Karte({required this.overlay});
  final SipgateAnrufOverlay overlay;

  static const double _breite = 320;
  // ⚠️ 108 -> 92: die Güte steht seit der Glaskarte NEBEN der Uhr statt in
  // einer eigenen dritten Zeile. Der Wert begrenzt NUR, wie weit sich die
  // Karte ziehen lässt — bliebe er zu klein, liesse sie sich über den unteren
  // Rand hinausschieben und der Auflegen-Knopf wäre nicht mehr erreichbar.
  static const double _hoehe = 92;

  /// Wie stark die Scheibe zum Schwarzen gezogen wird, und wie dicht sie deckt.
  ///
  /// 🔴 BEIDE ZAHLEN SIND GEMESSEN, NICHT GEWÄHLT. Die Karte schwebt über
  /// beliebigem Inhalt, also entscheidet der ungünstigste Untergrund. Gegen
  /// Weiss, Hellgrau, Gelb, Indigo, Schwarz und das eigene Grün gerechnet,
  /// über alle vier Kartenfarben (verbunden, klingelt, wählt, Konferenz):
  ///
  ///     weisser Text          schlechtester Fall  11,36:1   (verlangt 4,5:1)
  ///     Welle und Kante       schlechtester Fall   3,56:1   (verlangt 3:1)
  ///
  /// ⚠️ Die zuerst gebaute Fassung (Tönung 0,78 / Deckung 0,62) sah besser aus
  /// und kam mit der roten Welle über einer weissen Fläche auf **2,09:1** —
  /// im schlimmsten Fall nicht ablesbar. Wer eine der Zahlen senkt, rechnet
  /// nach.
  ///
  /// ⚠️ Der Glaseindruck kommt überwiegend aus der UNSCHÄRFE, nicht aus der
  /// Durchsicht. Die 18 % Rest-Durchsicht genügen, damit sich Formen und
  /// Farben darunter abzeichnen.
  static const double _glasToenung = 0.86;
  static const double _glasDeckung = 0.82;
  static const double _glasUnschaerfe = 18;
  static const double _rundung = 20;

  /// Wie hoch das Mitschrift-Fenster in der Karte ist.
  ///
  /// ⚠️ FEST, nicht mitwachsend. Der Text sammelt sich über das ganze Gespräch;
  /// eine Karte, die mit ihm wächst, deckt nach fünf Minuten den halben
  /// Bildschirm zu — und sie schwebt über allem anderen. Drei Zeilen sind das,
  /// was man im Vorbeigehen liest.
  ///
  /// ⚠️ 58 -> 64, weil 58 die drei Zeilen NICHT hergab: 13 dp Schrift mal 1,35
  /// Zeilenluft sind 17,6 dp, drei davon 52,7, dazu 2 mal 5 dp Polster — macht
  /// 62,7. Bei 58 schnitt der Rollbereich die oberste Zeile waagerecht durch;
  /// auf einer Randerung sieht man es sofort, im Quelltext nicht. Die
  /// Beschreibung stimmte, die Zahl nicht.
  static const double _mitschriftHoehe = 64;

  @override
  Widget build(BuildContext context) {
    final flaeche = MediaQuery.of(context).size;
    // Auf Telefonbreite darf die Karte nicht breiter sein als der Bildschirm.
    final breite = _breite > flaeche.width - 16 ? flaeche.width - 16 : _breite;
    // ⚠️ AUF `aktiv` HÖREN, nicht den Wert einmal ablesen. Die Höhe geht in den
    // Anschlag beim Ziehen ein; wäre sie zu klein angesetzt, liesse sich die
    // Karte über den unteren Rand hinausschieben und der Auflegen-Knopf wäre
    // nicht mehr erreichbar. Genau das wäre passiert, wenn die Mitschrift
    // eingeschaltet wird, WÄHREND die Karte schon steht — ein Zustand, der
    // aussieht wie ein Zeichenfehler und einer der Bedienung ist.
    return ValueListenableBuilder<bool>(
      valueListenable: UntertitelService().aktiv,
      builder: (ctx0, mitSchrift, __) {
        final groesse =
            Size(breite, _hoehe + (mitSchrift ? _mitschriftHoehe + 8 : 0));
        final ort = overlay._position ?? overlay._standardOrt(flaeche, groesse);

        return Positioned(
          left: ort.dx,
          top: ort.dy,
          width: breite,
          child: ValueListenableBuilder<SipgateZustand>(
            valueListenable: SipgateService().zustand,
            builder: (ctx, z, _) {
              final g = z.gespraech;
              // Zwischen dem Entfernen des Eintrags und dem letzten Neubau kann
              // hier ein Takt liegen; dann lieber nichts zeichnen als werfen.
              if (g == null) return const SizedBox.shrink();
              return _inhalt(ctx, z, g, groesse);
            },
          ),
        );
      },
    );
  }

  Widget _inhalt(BuildContext context, SipgateZustand z, SipgateGespraech g, Size groesse) {
    final dienst = SipgateService();
    final verbunden = g.stand == SipgateGespraechStand.verbunden;
    final klingelt = g.stand == SipgateGespraechStand.klingelt;

    if (z.konferenz) {
      // Eigene Farbe, damit man auf einen Blick sieht, dass zwei Menschen
      // mithören — bei Gesundheits- oder Behördenthemen ist das kein Detail.
      return _rahmen(
        context, groesse, const Color(0xFF5E35B1), Icons.groups,
        titel: 'Konferenz: ${z.beine.map((b) => b.anzeigeVerdeckt).join(' + ')}',
        zeile: () => SipgateService.dauerUhr(g.dauerSekunden),
        knoepfe: [
          _rundKnopf(
            g.stumm ? Icons.mic_off : Icons.mic,
            Colors.white24,
            g.stumm ? 'Mikrofon einschalten' : 'Stummschalten',
            () => dienst.stummSchalten(!g.stumm),
          ),
          const SizedBox(width: 6),
          _rundKnopf(Icons.call_end, Colors.red.shade700, 'Auflegen',
              () => dienst.auflegen()),
        ],
      );
    }

    // ⚠️ `zeile` ist ein Rückruf, kein String. Bei „verbunden" steht dort die
    // Uhr, und die muss im Takt NEU ausgerechnet werden — ein hier fertig
    // gebauter String wäre eine Sekunde später derselbe und die Uhr stünde.
    final (farbe, symbol, zeile) = switch (g.stand) {
      SipgateGespraechStand.verbunden => (
          const Color(0xFF2E7D32),
          Icons.phone_in_talk,
          () => SipgateService.dauerUhr(g.dauerSekunden),
        ),
      SipgateGespraechStand.klingelt => (
          const Color(0xFF1565C0),
          Icons.phone_callback,
          () => 'Eingehender Anruf',
        ),
      SipgateGespraechStand.waehlt => (
          const Color(0xFF00695C),
          Icons.phone_forwarded,
          () => 'Wählt …',
        ),
    };

    // Die zweite Zeile als Text.
    //
    // ⚠️ Eine Funktion, kein fertiger String: `zeile()` rechnet die Uhr JEDES
    // MAL neu. Ein einmal gebauter String wäre für die ganze Lebensdauer der
    // Karte derselbe, und die Uhr stünde still.
    String zeileText() {
      // Wer gehalten wird, gehört in die Zeile: sonst wundert man sich, warum
      // die zweite Person schweigt.
      final anderes = z.zweites != null && !z.konferenz
          ? (z.zweites!.gehalten
              ? ' · hält: ${z.zweites!.anzeigeVerdeckt}'
              : ' · 2 Gespräche')
          : '';
      // ⚠️ Zuerst, und mit eigenem Wortlaut: „die Gegenseite hat uns geparkt"
      // erklärt die plötzliche Stille. Ohne den Satz ist sie von einer Störung
      // nicht zu unterscheiden — und man legt auf, während das Amt gerade
      // jemanden holt.
      if (g.vonGegenseiteGehalten) {
        return 'In der Warteschleife · ${zeile()}$anderes';
      }
      // Ein Name allein sagt nicht, welche der drei Nummern eines Amtes man
      // erreicht hat — deshalb steht sie mit dabei.
      final nr = SipgateService.anruferVerdeckt(g.nummer);
      if (verbunden && g.anzeigeVerdeckt != nr) {
        return '${zeile()} · $nr$anderes';
      }
      return '${zeile()}$anderes';
    }

    return GestureDetector(
      // Ziehen, damit die Karte nichts verdeckt, was man gerade lesen muss.
      onPanUpdate: (d) => overlay._verschieben(d.delta, MediaQuery.of(context).size, groesse),
      child: _glas(
        ton: farbe,
        kind: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(_rundung),
            // Tippen führt in den vollen Bildschirm — dort sind DTMF-Tasten,
            // Verlauf und die Absendernummer.
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SipgateScreen()),
            ),
            child: Padding(
              // Links kein Rand: dort sitzt der farbige Streifen an der Kante.
              padding: const EdgeInsets.fromLTRB(0, 10, 12, 10),
              child: _mitKarte(
              Row(
              children: [
                // Der Streifen folgt der GÜTE, sobald gemessen wird — vorher
                // der Farbe des Zustands. Eigener Melder, damit nicht die
                // ganze Karte alle drei Sekunden neu gebaut wird.
                if (verbunden)
                  ValueListenableBuilder<QualitaetsProbe?>(
                    valueListenable: SipgateService().guete,
                    builder: (_, probe, __) => _kante(probe == null
                        ? Colors.white.withValues(alpha: 0.55)
                        : gueteFarbeHell(probe.stufe)),
                  )
                else
                  _kante(Colors.white.withValues(alpha: 0.55)),
                Icon(symbol, color: Colors.white, size: 24),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        // Bei zwei Beinen zählt, WER dran ist — nicht nur eine
                        // Nummer. Eine Konferenz mit einem Amt und einem
                        // Mitglied darf nicht wie ein einzelner Anruf aussehen.
                        z.konferenz
                            ? 'Konferenz: '
                                '${z.beine.map((b) => b.anzeigeVerdeckt).join(' + ')}'
                            // ⚠️ Verdeckt: die Karte schwebt über allem und
                            // ist von einem Meter Abstand zu lesen. Im
                            // Vollbild steht die Nummer ganz da — dorthin geht
                            // man absichtlich.
                            : g.anzeigeVerdeckt,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      // Uhr und Güte in EINER Zeile.
                      //
                      // ⚠️ Nur DIESE Zeile tickt, nicht die Karte darum: Name,
                      // Farbe und Knöpfe ändern sich nur bei einem Ereignis.
                      //
                      // 🔴 WARUM `LayoutBuilder` UND NICHT ZWEIMAL `Flexible`.
                      // Gemessen: für diese Spalte bleiben genau 177 dp.
                      // `Flexible` teilt sie starr in zwei Hälften und gibt
                      // ungenutzten Platz NICHT an das Geschwisterkind zurück
                      // — die Uhr („02:14", 33 dp) verschenkte damit 55 dp,
                      // und daneben stand „brauc…" statt „brauchbar". Genau so
                      // sah die erste Fassung aus.
                      //
                      // Jetzt hat die Uhr Vorrang und nimmt, was sie braucht;
                      // die Güte bekommt mit `Expanded` den ganzen Rest. Der
                      // Deckel von 62 % schützt sie davor, dass eine lange
                      // Uhrzeile („In der Warteschleife · …", 166 dp) alles
                      // frisst.
                      //
                      // ⚠️ Die Reihenfolge ist eine ENTSCHEIDUNG: passt beides
                      // nicht, gewinnt die Uhrzeile mit der Rufnummer und das
                      // Wort weicht. Die Stufe steht dann immer noch in der
                      // Welle und in der Kante — die Nummer stünde nirgends.
                      LayoutBuilder(
                        builder: (ctx2, mass) {
                          final uhr = SekundenTakt(
                            // Beim Klingeln und beim Wählen steht hier ein
                            // fester Satz — da gibt es nichts zu ticken.
                            aktiv: verbunden,
                            bauen: (_) => Text(
                              zeileText(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13,
                                // Feste Breite je Ziffer, sonst zappelt die Uhr.
                                fontFeatures: verbunden
                                    ? const [FontFeature.tabularFigures()]
                                    : null,
                              ),
                            ),
                          );
                          if (!verbunden) return uhr;
                          // ⚠️ Eigener Melder, nicht der Gesamtzustand: sonst
                          // würde die ganze Karte alle drei Sekunden neu
                          // gebaut — genau die Last, wegen der der
                          // Sekundentakt im Dienst abgeschafft wurde.
                          return ValueListenableBuilder<QualitaetsProbe?>(
                            valueListenable: SipgateService().guete,
                            // ⚠️ Solange nichts gemessen ist, steht hier GAR
                            // NICHTS von der Güte. Eine flache graue Welle wäre
                            // von der flachen roten Welle bei „kaum
                            // verständlich" nicht zu unterscheiden — das Fehlen
                            // ist die einzige eindeutige Darstellung von „noch
                            // nicht bekannt".
                            builder: (_, probe, __) => probe == null
                                ? uhr
                                : Row(children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(
                                          maxWidth: mass.maxWidth * 0.62),
                                      child: uhr,
                                    ),
                                    const SizedBox(width: 6),
                                    Welle(
                                      stufe: probe.stufe,
                                      farbe: gueteFarbeHell(probe.stufe),
                                    ),
                                    const SizedBox(width: 5),
                                    Expanded(
                                      child: Text(
                                        gueteStufeText(probe.stufe),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        // ⚠️ WEISS, nicht in der Güte-Farbe.
                                        // Auf der Scheibe über einer weissen
                                        // Fläche käme Rot auf 2,09:1, Weiss
                                        // kommt auf 11,36:1. Die Farbe trägt
                                        // die Welle und die Kante, das Wort
                                        // trägt den Sinn.
                                        // ⚠️ 11,5 und nicht 12. Gemessen bleiben
                                        // für das Wort 106,5 dp; „kaum
                                        // verständlich" ist bei 12 dp nur
                                        // 103,7 dp breit und wurde trotzdem
                                        // abgeschnitten — die Material-Typo
                                        // legt `letterSpacing` obendrauf, rund
                                        // 4 dp auf 17 Zeichen. Wer nach der
                                        // reinen Textbreite geht, rechnet zu
                                        // knapp.
                                        style: const TextStyle(
                                            color: Colors.white, fontSize: 11.5),
                                      ),
                                    ),
                                  ]),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                if (klingelt) ...[
                  _rundKnopf(Icons.call, Colors.green.shade600, 'Annehmen',
                      () => dienst.annehmen()),
                  const SizedBox(width: 6),
                  _rundKnopf(Icons.call_end, Colors.red.shade700, 'Ablehnen',
                      dienst.ablehnen),
                ] else ...[
                  if (verbunden) ...[
                    _rundKnopf(
                      g.stumm ? Icons.mic_off : Icons.mic,
                      Colors.white24,
                      g.stumm ? 'Mikrofon einschalten' : 'Stummschalten',
                      () => dienst.stummSchalten(!g.stumm),
                    ),
                    const SizedBox(width: 6),
                  ],
                  _rundKnopf(Icons.call_end, Colors.red.shade700, 'Auflegen',
                      dienst.auflegen),
                ],
              ],
              ),
              verbunden,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Die Karte: eine Zeile mit Namen, Uhr und Knöpfen — darunter, über die
  /// ganze Breite, die Mitschrift.
  ///
  /// ⚠️ UNTER DER ZEILE, NICHT IN IHR. Die erste Fassung hängte den Block in
  /// die mittlere Spalte. Gerendert und angesehen war das Ergebnis eindeutig:
  /// der Text hatte nur ~185 der 296 verfügbaren Pixel, brauchte dadurch
  /// deutlich mehr Zeilen, stand direkt an den Knöpfen — und die Knöpfe
  /// rutschten auf die Mitte der nun hohen Karte, also weg von der Nummer, zu
  /// der sie gehören. Nichts davon war im Quelltext zu sehen.
  /// Die Scheibe: Unschärfe, getönte Deckschicht, dünner heller Rand.
  ///
  /// ⚠️ `BackdropFilter` verwischt, was VOR ihm gezeichnet wurde — in einem
  /// Overlay also die ganze Anwendung darunter. Genau das ist gewollt; es
  /// heisst aber auch, dass die Unschärfe in JEDEM Bild neu gerechnet wird.
  /// Deshalb steht eine `RepaintBoundary` davor: ohne sie zöge jede tickende
  /// Sekunde eine Neuberechnung der ganzen Scheibe nach sich.
  ///
  /// ⚠️ NICHT auf einem Gerät gemessen. Auf diesem Tablet ist unbekannt, was
  /// die Unschärfe während eines Gesprächs kostet.
  Widget _glas({required Color ton, required Widget kind}) {
    final scheibe = Color.lerp(ton, Colors.black, _glasToenung)!
        .withValues(alpha: _glasDeckung);
    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_rundung),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
              sigmaX: _glasUnschaerfe, sigmaY: _glasUnschaerfe),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheibe,
              borderRadius: BorderRadius.circular(_rundung),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: kind,
          ),
        ),
      ),
    );
  }

  /// Der farbige Streifen an der linken Kante.
  ///
  /// ⚠️ Er trägt die Farbe, das Wort daneben trägt den Sinn — die Kante allein
  /// wäre eine Aussage nur über Farbe (WCAG 1.4.1).
  Widget _kante(Color farbe) => Container(
        width: 4,
        height: 42,
        margin: const EdgeInsets.only(right: 11),
        decoration: BoxDecoration(
          color: farbe,
          borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
        ),
      );

  Widget _mitKarte(Widget zeile, bool verbunden) {
    if (!verbunden) return zeile;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [zeile, _mitschrift()],
    );
  }

  /// Die Mitschrift der Gegenstelle, direkt in der Gesprächskarte.
  ///
  /// ⚠️ WARUM HIER UND NICHT NUR IM VOLLBILD. Wer schlecht hört, liest MIT,
  /// während er spricht — und die Karte ist das, was während des Gesprächs
  /// über allem anderen steht. Im Vollbildschirm steht der Text schon; dorthin
  /// zu wechseln heisst aber, das Fenster zu verlassen, in dem man gerade
  /// arbeitet.
  ///
  /// ⚠️ `reverse: true` STATT EINES AUTOMATISCHEN SCROLLENS. Damit liegt der
  /// Anker am ENDE des Textes: das Zuletztgesagte steht immer da, ohne
  /// Controller, ohne Nachführen und ohne den Fall „neuer Satz kam an, während
  /// der Bildschirm gerade neu gebaut wurde". Zurückblättern geht trotzdem.
  ///
  /// ⚠️ NICHT abschneiden und dann `TextOverflow.ellipsis`: das kürzt am ENDE,
  /// also genau das Neueste — der einzige Teil, auf den es hier ankommt.
  ///
  /// ⚠️ Nicht in der Konferenz. Die Mitschrift hängt an der Tonspur von Bein A;
  /// bei zwei Gesprächspartnern stünde dort der eine, und man läse es als
  /// beide.
  Widget _mitschrift() {
    return ValueListenableBuilder<bool>(
      valueListenable: UntertitelService().aktiv,
      builder: (ctx, an, __) {
        if (!an) return const SizedBox.shrink();
        return Padding(
          // ⚠️ Links 15 und nicht 0: die Karte hat seit der Scheibe keinen
          // linken Rand mehr (dort sitzt der farbige Streifen). Ohne diese
          // Zahl klebte die Mitschrift an der Kante, während Symbol und Text
          // darüber eingerückt stehen — 4 (Streifen) + 11 (Abstand) = 15.
          padding: const EdgeInsets.only(top: 6, left: 15),
          child: Container(
            width: double.infinity,
            height: _mitschriftHoehe,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              // Dunkel auf der farbigen Karte: heller Text auf hellem Grund
              // wäre bei Tageslicht auf einem Tablet nicht zu lesen.
              color: Colors.black.withValues(alpha: 0.28),
              // Etwas runder als vorher (8), damit es zur Rundung der
              // Scheibe passt.
              borderRadius: BorderRadius.circular(14),
            ),
            child: ValueListenableBuilder<String>(
              valueListenable: UntertitelService().text,
              builder: (ctx, text, __) => SingleChildScrollView(
                reverse: true,
                child: Text(
                  text.isEmpty ? 'Mitschrift läuft …' : text,
                  style: TextStyle(
                    // Kleiner als im Vollbild (dort 19), aber mit derselben
                    // Zeilenluft — hier sind nur drei Zeilen Platz.
                    fontSize: 13,
                    height: 1.35,
                    color: text.isEmpty ? Colors.white60 : Colors.white,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Gemeinsamer Rahmen: Ziehen, Antippen, Farbe, Symbol, zwei Zeilen, Knöpfe.
  Widget _rahmen(
    BuildContext context,
    Size groesse,
    Color farbe,
    IconData symbol, {
    required String titel,
    /// ⚠️ Ein Rückruf, kein String: die Uhr muss jede Sekunde NEU
    /// ausgerechnet werden. Ein hereingereichter String wäre für die ganze
    /// Lebensdauer der Karte derselbe, und die Uhr stünde still.
    required String Function() zeile,
    required List<Widget> knoepfe,
  }) =>
      GestureDetector(
        onPanUpdate: (d) =>
            overlay._verschieben(d.delta, MediaQuery.of(context).size, groesse),
        child: Material(
          elevation: 10,
          borderRadius: BorderRadius.circular(14),
          color: farbe,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SipgateScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(symbol, color: Colors.white, size: 26),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(titel,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15)),
                        SekundenTakt(
                          aktiv: true,
                          bauen: (_) => Text(zeile(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.92),
                                fontSize: 13,
                                fontFeatures: const [
                                  FontFeature.tabularFigures()
                                ],
                              )),
                        ),
                      ],
                    ),
                  ),
                  ...knoepfe,
                ],
              ),
            ),
          ),
        ),
      );

  Widget _rundKnopf(IconData symbol, Color farbe, String hinweis, VoidCallback tun) =>
      Tooltip(
        message: hinweis,
        child: Material(
          color: farbe,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: tun,
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(symbol, color: Colors.white, size: 20),
            ),
          ),
        ),
      );
}
