import 'package:flutter/material.dart';

class WasserTrinkenTab extends StatelessWidget {
  const WasserTrinkenTab({super.key});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _infoCard(Icons.water_drop, 'Warum Wasser trinken?', Colors.blue, [
        'Wasser ist der wichtigste Nährstoff — der Körper besteht zu ca. 60% aus Wasser.',
        'Schon 2% Dehydration beeinträchtigt Konzentration und Leistungsfähigkeit.',
        'Ausreichend trinken unterstützt Nieren, Verdauung, Haut und Immunsystem.',
      ]),
      const SizedBox(height: 12),
      _infoCard(Icons.local_drink, 'Wie viel sollte man trinken?', Colors.teal, [
        'Erwachsene: mindestens 1,5 – 2 Liter pro Tag (DGE-Empfehlung).',
        'Bei Hitze, Sport oder Krankheit: bis zu 3 Liter oder mehr.',
        'Kinder (1–10 Jahre): ca. 0,6 – 1 Liter pro Tag.',
        'Ältere Menschen: oft vermindertes Durstgefühl — bewusst trinken!',
      ]),
      const SizedBox(height: 12),
      _infoCard(Icons.schedule, 'Wann trinken?', Colors.orange, [
        'Morgens: 1 Glas Wasser direkt nach dem Aufstehen.',
        'Vor den Mahlzeiten: ca. 30 Minuten vorher — unterstützt die Verdauung.',
        'Regelmäßig über den Tag verteilt — nicht alles auf einmal.',
        'Vor und nach dem Sport.',
      ]),
      const SizedBox(height: 12),
      _infoCard(Icons.warning_amber, 'Zeichen von Wassermangel', Colors.red, [
        'Kopfschmerzen und Schwindel',
        'Müdigkeit und Konzentrationsprobleme',
        'Dunkler Urin',
        'Trockene Haut und Lippen',
        'Verstopfung',
      ]),
      const SizedBox(height: 12),
      _infoCard(Icons.lightbulb, 'Tipps für mehr Wasser im Alltag', Colors.amber, [
        'Wasserflasche immer griffbereit halten.',
        'Erinnerungen stellen (App oder Handy-Wecker).',
        'Geschmack: Zitrone, Gurke, Minze oder Beeren ins Wasser.',
        'Für jede Tasse Kaffee ein Glas Wasser trinken.',
        'Mit einer Wasserfilter-Anlage schmeckt Leitungswasser besser (siehe Filter-Tab).',
      ]),
      const SizedBox(height: 12),
      _infoCard(Icons.no_drinks, 'Was zählt nicht als Wasser?', Colors.grey, [
        'Kaffee und Schwarztee — entwässernd in großen Mengen.',
        'Softdrinks und Säfte — viel Zucker, oft kontraproduktiv.',
        'Alkohol — stark entwässernd.',
        'Energydrinks — hoher Koffein- und Zuckergehalt.',
      ]),
      const SizedBox(height: 12),
      Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.blue.shade200)),
        child: Row(children: [
          Icon(Icons.favorite, size: 24, color: Colors.blue.shade700),
          const SizedBox(width: 12),
          Expanded(child: Text('ICD360S e.V. empfiehlt: Trinken Sie täglich mindestens 2 Liter gefiltertes Wasser für Ihre Gesundheit. '
            'Schauen Sie im Tab „Filter" nach unseren Empfehlungen für Wasserfilter-Anlagen.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade800, height: 1.4))),
        ]),
      ),
    ]));
  }

  Widget _infoCard(IconData icon, String title, MaterialColor color, List<String> points) {
    return Container(padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 22, color: color.shade700),
          const SizedBox(width: 10),
          Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800)),
        ]),
        const SizedBox(height: 10),
        ...points.map((p) => Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(padding: const EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 6, color: color.shade400)),
          const SizedBox(width: 8),
          Expanded(child: Text(p, style: TextStyle(fontSize: 13, color: Colors.grey.shade800, height: 1.4))),
        ]))),
      ]),
    );
  }
}
