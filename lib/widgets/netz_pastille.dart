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
      return Text(widget.ersatz, style: const TextStyle(fontSize: 10));
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

    if (logo != null && netz != null) {
      teile.add(_netzZeichen(context, logo, netz, hinweis));
    } else if (art == 'mobil') {
      // Kein Logo heisst nicht „unbekannt": bei den MVNO steht der
      // Zuteilungsinhaber sehr wohl fest, nur sein Netz nicht.
      final zuteilung = e['zuteilung'] as String?;
      teile.add(_text(context, zuteilung == null ? 'Mobilfunk' : _kurz(zuteilung),
          Icons.smartphone, Colors.blueGrey, hinweis));
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

  Widget _netzZeichen(BuildContext ctx, String logo, String netz, String? hinweis) {
    return Tooltip(
      message: hinweis ?? netz,
      child: InkWell(
        // Auf dem Telefon gibt es keinen Zeiger, der über einem Tooltip stehen
        // bleibt — deshalb zusätzlich antippbar.
        onTap: hinweis == null
            ? null
            : () => showDialog<void>(
                  context: ctx,
                  builder: (c) => AlertDialog(
                    title: Text('Netz: $netz'),
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
            _Logo(schluessel: logo, ersatz: netz),
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
