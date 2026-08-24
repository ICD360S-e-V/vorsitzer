import 'package:flutter/material.dart';

import '../utils/app_farben.dart';
import '../utils/landratsamt_antraege.dart';

/// Auswahlfläche für die Vorfall-Art.
///
/// Ersetzt das frühere Dropdown. Zeigt neben dem Titel den Fachbereich, die
/// Rechtsgrundlage und — das ist der eigentliche Zweck — den
/// Zuständigkeitshinweis, wo es einen gibt.
class LandratsamtArtAuswahl extends StatelessWidget {
  final String wert;
  final ValueChanged<String> onGewaehlt;

  const LandratsamtArtAuswahl({super.key, required this.wert, required this.onGewaehlt});

  @override
  Widget build(BuildContext context) {
    final eintrag = landratsamtAntragFinden(wert);
    final leer = wert.trim().isEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      InkWell(
        onTap: () async {
          final gewaehlt = await showDialog<String>(
            context: context,
            builder: (_) => const LandratsamtArtSuchDialog(),
          );
          if (gewaehlt != null) onGewaehlt(gewaehlt);
        },
        borderRadius: BorderRadius.circular(8),
        child: InputDecorator(
          decoration: InputDecoration(
            labelText: 'Art *',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: const Icon(Icons.search, size: 18),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text(
              leer ? 'Antrag oder Vorgang wählen …' : wert,
              style: TextStyle(fontSize: 13, color: leer ? F.h(Colors.grey, 500) : null),
            ),
            if (eintrag != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  eintrag.recht == null ? eintrag.gruppe : '${eintrag.gruppe} · ${eintrag.recht}',
                  style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600)),
                ),
              ),
            // Ein Wert aus einer älteren Fassung, den der Katalog nicht mehr
            // kennt, wird nicht stillschweigend geschluckt — sonst sähe er
            // aus wie ein regulärer Eintrag.
            if (!leer && eintrag == null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text('Freier Text — nicht aus dem Katalog',
                    style: TextStyle(fontSize: 10, color: F.h(Colors.orange, 800))),
              ),
          ]),
        ),
      ),
      if (eintrag?.hinweis != null) ...[
        const SizedBox(height: 6),
        ZustaendigkeitsHinweis(text: eintrag!.hinweis!, streng: eintrag.streng),
      ],
    ]);
  }
}

/// Der Kasten, der sagt, wenn das Landratsamt gar nicht die richtige Stelle ist.
///
/// ⚠️ Kein Schmuck: Wer einen Schwerbehindertenantrag in Bayern beim
/// Landratsamt einwirft, wartet Wochen auf die Weiterleitung. Bei einer Frist
/// kostet das den Anspruch.
class ZustaendigkeitsHinweis extends StatelessWidget {
  final String text;

  /// Falsche Behörde statt blosser Anmerkung — rot statt gelb, Warndreieck
  /// statt „i".
  final bool streng;

  const ZustaendigkeitsHinweis({super.key, required this.text, this.streng = false});

  @override
  Widget build(BuildContext context) {
    final grund = streng ? F.h(Colors.red, 50) : F.h(Colors.amber, 50);
    final rand = streng ? F.h(Colors.red, 300) : F.h(Colors.amber, 400);
    final schrift = streng ? F.h(Colors.red, 900) : F.h(Colors.amber, 900);
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: grund,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: rand),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(streng ? Icons.warning_amber_rounded : Icons.info_outline,
            size: 15, color: schrift),
        const SizedBox(width: 6),
        Expanded(child: Text(text,
            style: TextStyle(
                fontSize: 11,
                color: schrift,
                fontWeight: streng ? FontWeight.w600 : FontWeight.normal))),
      ]),
    );
  }
}

/// Suchdialog über den Antragskatalog, gruppiert nach Fachbereich.
class LandratsamtArtSuchDialog extends StatefulWidget {
  const LandratsamtArtSuchDialog({super.key});

  @override
  State<LandratsamtArtSuchDialog> createState() => LandratsamtArtSuchDialogState();
}

class LandratsamtArtSuchDialogState extends State<LandratsamtArtSuchDialog> {
  final _sucheC = TextEditingController();
  String _frage = '';

  @override
  void dispose() {
    _sucheC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final treffer = landratsamtAntraegeSuchen(_frage);
    // Nur Gruppen zeigen, in denen die Suche etwas gefunden hat — sonst
    // scrollt man bei einer engen Suche durch zwanzig leere Überschriften.
    final gruppen = kLandratsamtGruppen
        .where((g) => treffer.any((a) => a.gruppe == g))
        .toList(growable: false);

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [
        Icon(Icons.assignment, color: F.h(Colors.brown, 700), size: 20),
        const SizedBox(width: 8),
        const Expanded(child: Text('Antrag oder Vorgang wählen', style: TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: 620,
        height: 520,
        child: Column(children: [
          TextField(
            controller: _sucheC,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Suchen — auch nach Paragraf, z. B. „§ 35a" oder „Führerschein"',
              hintStyle: const TextStyle(fontSize: 12),
              prefixIcon: const Icon(Icons.search, size: 18),
              suffixIcon: _frage.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () { _sucheC.clear(); setState(() => _frage = ''); },
                    ),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (v) => setState(() => _frage = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: treffer.isEmpty
                ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.search_off, size: 40, color: F.h(Colors.grey, 300)),
                    const SizedBox(height: 8),
                    Text('Nichts gefunden', style: TextStyle(color: F.h(Colors.grey, 500), fontSize: 13)),
                    const SizedBox(height: 4),
                    Text('„Sonstiges" steht ganz unten in der Liste.',
                        style: TextStyle(color: F.h(Colors.grey, 400), fontSize: 11)),
                  ]))
                : ListView.builder(
                    itemCount: gruppen.length,
                    itemBuilder: (_, gi) {
                      final gruppe = gruppen[gi];
                      final eintraege = treffer.where((a) => a.gruppe == gruppe).toList();
                      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(2, 12, 2, 6),
                          child: Text(gruppe.toUpperCase(),
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.6,
                                  color: F.h(Colors.brown, 400))),
                        ),
                        ...eintraege.map((a) => InkWell(
                              onTap: () => Navigator.pop(context, a.titel),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 4),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: F.flaeche,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: F.h(Colors.grey, 300)),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(a.titel, style: const TextStyle(fontSize: 13)),
                                  if (a.recht != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Text(a.recht!,
                                          style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 600))),
                                    ),
                                  if (a.hinweis != null)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Icon(
                                            a.streng
                                                ? Icons.warning_amber_rounded
                                                : Icons.info_outline,
                                            size: 12,
                                            color: a.streng
                                                ? F.h(Colors.red, 900)
                                                : F.h(Colors.amber, 900)),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(a.hinweis!,
                                              style: TextStyle(
                                                  fontSize: 10,
                                                  color: a.streng
                                                      ? F.h(Colors.red, 900)
                                                      : F.h(Colors.amber, 900),
                                                  fontWeight: a.streng
                                                      ? FontWeight.w600
                                                      : FontWeight.normal)),
                                        ),
                                      ]),
                                    ),
                                ]),
                              ),
                            )),
                      ]);
                    },
                  ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('${treffer.length} von ${kLandratsamtAntraege.length} Vorgängen',
                  style: TextStyle(fontSize: 10, color: F.h(Colors.grey, 500))),
            ),
          ),
        ]),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Abbrechen'))],
    );
  }
}

