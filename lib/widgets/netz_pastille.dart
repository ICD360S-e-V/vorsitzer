import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/api_service.dart';

/// Die vier Netzlogos, einmal je Sitzung geholt.
///
/// ⚠️ Ein `null` als WERT heisst „versucht, ging nicht" — das ist etwas
/// anderes als ein fehlender Schlüssel („noch nicht versucht"). Ohne diese
/// Unterscheidung fragte ein toter Endpunkt bei jedem Neuaufbau erneut an.
///
/// Auf oberster Ebene und nicht in der Klasse, damit ein Test ihn vorbelegen
/// kann, ohne dass die Klasse dafür öffentlich werden muss.
final Map<String, String?> netzlogoSpeicher = <String, String?>{};

/// Zeichnet ein Netzlogo aus dem Speicher — und holt es beim ersten Mal.
///
/// ⚠️ VIER DATEIEN, EINMAL JE SITZUNG. Sie liegen hinter der Anmeldung, also
/// kann sie kein `Image.network` einfach ziehen; und sie in jede Listenzeile zu
/// hängen hiesse, dieselben vier Dateien fünfzigmal anzufragen.
///
/// ⚠️ Der Rückfall ist der NAME, nicht nichts. Eine leere Lücke sähe aus, als
/// fehle die Auskunft selbst — dabei ist nur das Bild nicht da.
class _Logo extends StatefulWidget {
  const _Logo({required this.schluessel, required this.ersatz});
  final String schluessel;
  final String ersatz;

  @override
  State<_Logo> createState() => _LogoState();
}

class _LogoState extends State<_Logo> {
  @override
  void initState() {
    super.initState();
    if (!netzlogoSpeicher.containsKey(widget.schluessel)) _holen();
  }

  Future<void> _holen() async {
    // Sofort merken, dass es läuft — sonst starten fünfzig Zeilen fünfzig
    // Abrufe, bevor der erste antwortet.
    netzlogoSpeicher[widget.schluessel] = null;
    final svg = await ApiService().netzlogoSvg(widget.schluessel);
    if (svg == null) return;
    netzlogoSpeicher[widget.schluessel] = svg;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final svg = netzlogoSpeicher[widget.schluessel];
    if (svg == null) {
      // Leerer Ersatz heisst: der Name steht ohnehin daneben. Ihn ein zweites
      // Mal zu setzen wäre nur Lärm.
      return widget.ersatz.isEmpty
          ? const SizedBox.shrink()
          : Text(widget.ersatz, style: const TextStyle(fontSize: 10));
    }
    return SvgPicture.string(svg, height: 12);
  }
}

/// Was an einer Rufnummer selbst abzulesen ist — Art, Ort, Netz.
///
/// ⚠️ DREI AUSKÜNFTE, DIE UNTERSCHIEDLICH BELASTBAR SIND, UND DAS MUSS MAN
/// SEHEN. Die Art (Festnetz, Mobil, 0900 …) steht im Nummernraum der
/// Bundesnetzagentur und wird nie portiert. Der Ort bei Festnetznummern
/// ebenso: portiert wird nur innerhalb desselben Ortsnetzes. Das Netz bei
/// Mobilnummern dagegen sagt nur, wem der BLOCK zugeteilt wurde — seit der
/// Rufnummernmitnahme (November 2002) kann eine 0171 bei Vodafone liegen.
///
/// Deshalb trägt das Netz-Zeichen eine Erklärung, die man antippen kann, und
/// der Text daneben sagt „Block", nicht „Anbieter". Ein Logo ohne diesen
/// Unterschied wäre eine Behauptung mit Zuversicht — und die ist bei jeder
/// portierten Nummer falsch.
class NetzPastille extends StatelessWidget {
  const NetzPastille({super.key, required this.einordnung, this.kompakt = false});

  /// Der `einordnung`-Block aus `anrufer` / `list_anrufe`.
  final Map<String, dynamic>? einordnung;

  /// In Listenzeilen: nur das Nötigste, ohne Beiwerk.
  final bool kompakt;

  @override
  Widget build(BuildContext context) {
    final e = einordnung;
    if (e == null) return const SizedBox.shrink();
    final art = '${e['art'] ?? ''}';
    if (art.isEmpty || art == 'unbekannt') return const SizedBox.shrink();

    final logo = e['logo'] as String?;
    final netz = e['netz'] as String?;
    final ort = e['ort'] as String?;
    final hinweis = e['hinweis'] as String?;
    final kosten = e['kosten'] as String?;

    final teile = <Widget>[];

    // ⚠️ ZUERST, UND IN ROT. Steht die Nummer auf der Massnahmenliste der
    // Bundesnetzagentur, ist das die wichtigste Auskunft über sie — wichtiger
    // als Ort oder Netz.
    //
    // ⚠️ Der Wortlaut ist mit Bedacht gewählt: „amtlich aufgefallen", nicht
    // „Betrug". Ein Eintrag heisst, dass die Behörde gegen diese Nummer
    // vorgegangen ist; er ist ein Hinweis, kein Urteil. Und das FEHLEN eines
    // Eintrags heisst gar nichts — die meisten Betrugsanrufe kommen mit
    // gefälschter Absenderkennung, und die steht in keiner Liste. Deshalb gibt
    // es hier auch kein grünes Gegenstück: „nicht gelistet" darf nie wie eine
    // Unbedenklichkeitsbescheinigung aussehen.
    final missbrauch = e['missbrauch'] as String?;
    if (missbrauch != null && missbrauch.isNotEmpty) {
      teile.add(_text(
        context,
        'amtlich aufgefallen',
        Icons.gpp_maybe,
        Colors.red,
        'Die Bundesnetzagentur ist gegen diese Rufnummer wegen '
        'Rufnummernmissbrauchs vorgegangen ($missbrauch).\n\n'
        'Das ist ein Hinweis, kein Urteil — und dass eine Nummer NICHT auf der '
        'Liste steht, sagt nichts: die meisten Betrugsanrufe kommen mit '
        'gefälschter Absenderkennung.',
      ));
    }

    // ⚠️ DER NAME STEHT IMMER DA, DAS ZEICHEN KOMMT DAZU.
    //
    // Vorher erschien bei den vier grossen Netzen nur das Logo und bei allen
    // anderen nur ein Name — das las sich, als fehle mal das eine, mal das
    // andere. Es sind aber 102 Zuteilungsinhaber im Verzeichnis der
    // Bundesnetzagentur; für 98 davon haben wir kein Zeichen, und eines zu
    // erfinden hiesse, Zugehörigkeiten zu behaupten, die nirgends stehen.
    //
    // Also: der Name ist die Auskunft, das Logo ist Beiwerk. Eine Zeile ohne
    // Logo sieht damit nicht mehr nach fehlender Auskunft aus.
    final zuteilung = e['zuteilung'] as String?;
    if (zuteilung != null || netz != null) {
      teile.add(_netzZeichen(
        context,
        logo,
        netz ?? _kurz(zuteilung!),
        hinweis,
        istMobil: art == 'mobil',
      ));
    } else if (art == 'mobil') {
      teile.add(_text(context, 'Mobilfunk', Icons.smartphone, Colors.blueGrey, null));
    }

    if (ort != null) {
      teile.add(_text(context, ort, Icons.place_outlined, Colors.blueGrey, null));
    }

    if (kosten == 'kostenpflichtig') {
      teile.add(_text(context, '${e['art_text']} — kostenpflichtig',
          Icons.euro, Colors.red, hinweis));
    } else if (kosten == 'kostenlos') {
      teile.add(_text(context, '${e['art_text']}', Icons.money_off, Colors.green, null));
    } else if (teile.isEmpty && art != 'festnetz') {
      teile.add(_text(context, '${e['art_text']}', Icons.info_outline, Colors.blueGrey, null));
    }

    if (teile.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 6, runSpacing: 4, children: teile);
  }

  /// „Telefónica Germany GmbH & Co. OHG (ehem. E-Plus …)" ist für eine
  /// Listenzeile zu lang; der Anfang trägt die Auskunft.
  static String _kurz(String s) {
    final ohneKlammer = s.split('(').first.trim();
    return ohneKlammer.length > 28 ? '${ohneKlammer.substring(0, 27)}…' : ohneKlammer;
  }

  Widget _netzZeichen(BuildContext ctx, String? logo, String name, String? hinweis,
      {bool istMobil = false}) {
    return Tooltip(
      message: hinweis ?? name,
      child: InkWell(
        // Auf dem Telefon gibt es keinen Zeiger, der über einem Tooltip stehen
        // bleibt — deshalb zusätzlich antippbar.
        onTap: hinweis == null
            ? null
            : () => showDialog<void>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: Text((istMobil ? 'Mobilfunk: ' : 'Festnetz: ') + name),
                    content: Text(hinweis),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c),
                          child: const Text('Verstanden')),
                    ],
                  ),
                ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: Theme.of(ctx).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            // Das Zeichen NUR, wenn wir eines haben — und nie an seiner Stelle
            // eine Lücke: der Name kommt gleich danach.
            if (logo != null) ...[
              _Logo(schluessel: logo, ersatz: ''),
              const SizedBox(width: 4),
            ],
            Text(name, style: const TextStyle(fontSize: 10)),
            if (!kompakt) ...[
              const SizedBox(width: 5),
              // „Block", nicht „Anbieter" — der Unterschied ist der ganze Punkt.
              Text('Block', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _text(BuildContext ctx, String text, IconData ikone, Color farbe, String? hinweis) {
    final inhalt = Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(ikone, size: 12, color: farbe),
      const SizedBox(width: 3),
      Text(text, style: TextStyle(fontSize: 10, color: farbe)),
    ]);
    return hinweis == null ? inhalt : Tooltip(message: hinweis, child: inhalt);
  }
}
