import 'package:flutter/material.dart';

import '../screens/sipgate_screen.dart';
import '../services/notification_service.dart';
import '../services/sipgate_service.dart';
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
  static const double _hoehe = 92;

  @override
  Widget build(BuildContext context) {
    final flaeche = MediaQuery.of(context).size;
    // Auf Telefonbreite darf die Karte nicht breiter sein als der Bildschirm.
    final breite = _breite > flaeche.width - 16 ? flaeche.width - 16 : _breite;
    final groesse = Size(breite, _hoehe);
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
        titel: 'Konferenz: ${z.beine.map((b) => b.anzeige).join(' + ')}',
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

    return GestureDetector(
      // Ziehen, damit die Karte nichts verdeckt, was man gerade lesen muss.
      onPanUpdate: (d) => overlay._verschieben(d.delta, MediaQuery.of(context).size, groesse),
      child: Material(
        elevation: 10,
        borderRadius: BorderRadius.circular(14),
        color: farbe,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          // Tippen führt in den vollen Bildschirm — dort sind DTMF-Tasten,
          // Verlauf und die Absendernummer.
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
                      Text(
                        // Bei zwei Beinen zählt, WER dran ist — nicht nur eine
                        // Nummer. Eine Konferenz mit einem Amt und einem
                        // Mitglied darf nicht wie ein einzelner Anruf aussehen.
                        z.konferenz
                            ? 'Konferenz: ${z.beine.map((b) => b.anzeige).join(' + ')}'
                            : g.anzeige,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      // ⚠️ Nur DIESE Zeile tickt, nicht die Karte darum: Name,
                      // Farbe und Knöpfe ändern sich nur bei einem Ereignis.
                      SekundenTakt(
                        // Beim Klingeln und beim Wählen steht hier ein fester
                        // Satz — da gibt es nichts zu ticken.
                        aktiv: verbunden,
                        bauen: (_) => Text(
                        // Bei „verbunden" steht oben der Name und hier die Uhr;
                        // die Nummer daneben, weil ein Name allein nicht sagt,
                        // welche der drei Nummern eines Amtes man erreicht hat.
                        () {
                          // Wer gehalten wird, gehört in die Zeile: sonst
                          // wundert man sich, warum die zweite Person schweigt.
                          final anderes = z.zweites != null && !z.konferenz
                              ? (z.zweites!.gehalten
                                  ? ' · hält: ${z.zweites!.anzeige}'
                                  : ' · 2 Gespräche')
                              : '';
                          final nr = SipgateService.anruferAnzeige(g.nummer);
                          if (verbunden && g.anzeige != nr) {
                            return '${zeile()} · $nr$anderes';
                          }
                          return '${zeile()}$anderes';
                        }(),
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
          ),
        ),
      ),
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
