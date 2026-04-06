import 'package:flutter/material.dart';
import '../services/api_service.dart';

class ArbeitsagenturScreen extends StatefulWidget {
  final ApiService apiService;
  final VoidCallback onBack;

  const ArbeitsagenturScreen({
    super.key,
    required this.apiService,
    required this.onBack,
  });

  @override
  State<ArbeitsagenturScreen> createState() => _ArbeitsagenturScreenState();
}

class _ArbeitsagenturScreenState extends State<ArbeitsagenturScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
                tooltip: 'Zurück',
              ),
              const SizedBox(width: 8),
              const Icon(Icons.change_history, size: 32, color: Color(0xFFE30613)),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Bundesagentur für Arbeit',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Mindestlohn · Zeitarbeit Tarife · Leistungen 2026',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Tabs
          Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: TabBar(
              controller: _tabController,
              indicator: BoxDecoration(
                color: Colors.blue.shade700,
                borderRadius: BorderRadius.circular(10),
              ),
              labelColor: Colors.white,
              unselectedLabelColor: Colors.grey.shade700,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Mindestlohn'),
                Tab(text: 'Zeitarbeit Tarife'),
                Tab(text: 'Leistungen'),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Tab content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildMindestlohnTab(),
                _buildZeitarbeitTab(),
                _buildLeistungenTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Tab 1: Mindestlohn ─────────────────────────────────────────────

  Widget _buildMindestlohnTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Big card with current Mindestlohn
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(Icons.euro, size: 48, color: Colors.green.shade700),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Gesetzlicher Mindestlohn 2026',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade800,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '13,90 € brutto / Stunde',
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Gültig ab 01.01.2026 · +0,78 € gegenüber 2025 (13,12 €)',
                          style: TextStyle(fontSize: 14, color: Colors.green.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Info cards row
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  icon: Icons.calendar_month,
                  title: 'Monatslohn (Vollzeit)',
                  value: '~2.411 € brutto',
                  subtitle: '40 Std./Woche × 13,90 €',
                  color: Colors.blue,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(
                  icon: Icons.money_off,
                  title: 'Minijob-Grenze',
                  value: '603,00 € / Monat',
                  subtitle: 'Angepasst an Mindestlohn',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(
                  icon: Icons.people,
                  title: 'Profitieren',
                  value: '> 6 Mio. Menschen',
                  subtitle: '+190 € brutto/Monat',
                  color: Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Mindestlohn history table
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Entwicklung des Mindestlohns',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(2),
                      2: FlexColumnWidth(1.5),
                    },
                    children: [
                      _tableHeaderRow(['Zeitraum', 'Stundenlohn', 'Erhöhung']),
                      _tableRow(['Ab 01.01.2027', '14,60 €', '+0,70 €'], highlight: true),
                      _tableRow(['Ab 01.01.2026', '13,90 €', '+0,78 €'], highlight: true, current: true),
                      _tableRow(['Ab 01.01.2025', '13,12 €', '+0,71 €']),
                      _tableRow(['Ab 01.01.2024', '12,41 €', '+0,41 €']),
                      _tableRow(['Ab 01.01.2023', '12,00 €', '+1,82 €']),
                      _tableRow(['Ab 01.10.2022', '12,00 €', '+1,82 €']),
                      _tableRow(['Ab 01.07.2022', '10,45 €', '+0,27 €']),
                      _tableRow(['Ab 01.01.2022', '9,82 €', '+0,22 €']),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Next increase
          Card(
            color: Colors.blue.shade50,
            child: ListTile(
              leading: Icon(Icons.trending_up, color: Colors.blue.shade700, size: 32),
              title: const Text(
                'Nächste Erhöhung: 01.01.2027',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: const Text('14,60 € brutto / Stunde (+0,70 €)'),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Tab 2: Zeitarbeit Tarife ───────────────────────────────────────

  Widget _buildZeitarbeitTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info banner
          Card(
            color: Colors.indigo.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.indigo.shade700),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Einheitliches GVP/DGB-Tarifwerk ab 01.01.2026',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.indigo.shade800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Die bisherigen BAP- und iGZ-Tarifverträge werden durch ein gemeinsames Tarifwerk ersetzt. '
                          'Ca. 560.000 Beschäftigte erhalten einheitliche Standards.',
                          style: TextStyle(fontSize: 13, color: Colors.indigo.shade700),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Increase steps
          Row(
            children: [
              Expanded(
                child: _infoCard(
                  icon: Icons.calendar_today,
                  title: 'Ab 01.01.2026',
                  value: '+2,99 %',
                  subtitle: '1. Stufe',
                  color: Colors.green,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(
                  icon: Icons.calendar_today,
                  title: 'Ab 01.09.2026',
                  value: '+2,50 %',
                  subtitle: '2. Stufe',
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(
                  icon: Icons.calendar_today,
                  title: 'Ab 01.04.2027',
                  value: '+3,50 %',
                  subtitle: '3. Stufe',
                  color: Colors.blue,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Entgelttabelle ab 01.01.2026
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.table_chart, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'Entgelttabelle ab 01.01.2026',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          'Gültig bis 31.08.2026',
                          style: TextStyle(fontSize: 11, color: Colors.green.shade800),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Table(
                    border: TableBorder.all(color: Colors.grey.shade300),
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FlexColumnWidth(1.5),
                      2: FlexColumnWidth(2),
                      3: FlexColumnWidth(2),
                    },
                    children: [
                      _tableHeaderRow(['Entgeltgruppe', 'Stundenlohn', '+1,5% (>9 Mon.)', '+3,0% (>12 Mon.)']),
                      _tableRow(['EG 1 – Ungelernt', '14,96 €', '15,18 €', '15,41 €']),
                      _tableRow(['EG 2a – Angelernt (einfach)', '15,29 €', '15,52 €', '15,75 €']),
                      _tableRow(['EG 2b – Angelernt (erweitert)', '15,69 €', '15,93 €', '16,16 €']),
                      _tableRow(['EG 3 – Facharbeiter', '16,69 €', '16,94 €', '17,19 €']),
                      _tableRow(['EG 4 – Facharbeiter (qualif.)', '17,65 €', '17,91 €', '18,18 €']),
                      _tableRow(['EG 5 – Spezialisten', '19,78 €', '20,08 €', '20,37 €']),
                      _tableRow(['EG 6 – Meister/Techniker', '21,97 €', '22,30 €', '22,63 €']),
                      _tableRow(['EG 7 – Akademiker', '25,56 €', '25,94 €', '26,33 €']),
                      _tableRow(['EG 8 – Akademiker (qualif.)', '27,36 €', '27,77 €', '28,18 €']),
                      _tableRow(['EG 9 – Akademiker (Experte)', '28,70 €', '29,13 €', '29,56 €']),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Quelle: DGB/GVP-Tarifvertrag Zeitarbeit · Zuschläge nach Einsatzdauer: +1,5% ab 9 Mon., +3,0% ab 12 Mon.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Entgeltgruppen explanation
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.help_outline, color: Colors.amber.shade700),
                      const SizedBox(width: 8),
                      const Text(
                        'Entgeltgruppen – Einordnung',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _egExplanation('EG 1', 'Ungelernte Tätigkeiten ohne Vorkenntnisse (z.B. Helfer, Lager, Produktion)'),
                  _egExplanation('EG 2a/2b', 'Angelernte Tätigkeiten mit kurzer Einweisung (z.B. Maschinenführer, Kommissionierer)'),
                  _egExplanation('EG 3', 'Facharbeiter mit abgeschlossener Berufsausbildung (z.B. Elektriker, Schlosser)'),
                  _egExplanation('EG 4', 'Qualifizierte Facharbeiter mit Zusatzqualifikation'),
                  _egExplanation('EG 5', 'Spezialisten mit besonderen Fachkenntnissen (z.B. CNC-Programmierer)'),
                  _egExplanation('EG 6', 'Meister, Techniker, Fachwirte'),
                  _egExplanation('EG 7', 'Akademiker mit Hochschulabschluss'),
                  _egExplanation('EG 8–9', 'Hochqualifizierte Akademiker / Experten mit Berufserfahrung'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Branchenzuschläge
          Card(
            color: Colors.amber.shade50,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.add_circle_outline, color: Colors.amber.shade800),
                      const SizedBox(width: 8),
                      Text(
                        'Branchenzuschläge (zusätzlich zum Grundentgelt)',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber.shade900),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'In bestimmten Branchen erhalten Zeitarbeitnehmer zusätzliche Zuschläge auf den Tarifstundenlohn:',
                    style: TextStyle(fontSize: 13, color: Colors.amber.shade900),
                  ),
                  const SizedBox(height: 8),
                  _brancheRow('Metall & Elektro (IG Metall)', '+15% bis +65%'),
                  _brancheRow('Chemie (IG BCE)', '+10% bis +40%'),
                  _brancheRow('Kunststoff', '+10% bis +24%'),
                  _brancheRow('Textil & Bekleidung', '+12% bis +21%'),
                  _brancheRow('Kautschuk', '+10% bis +45%'),
                  _brancheRow('Schienenverkehr (EVG)', '+10% bis +36%'),
                  const SizedBox(height: 8),
                  Text(
                    'Zuschläge steigen mit der Einsatzdauer beim selben Kundenbetrieb.',
                    style: TextStyle(fontSize: 11, color: Colors.amber.shade700, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Tab 3: Leistungen ──────────────────────────────────────────────

  Widget _buildLeistungenTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ALG I
          _leistungCard(
            icon: Icons.account_balance_wallet,
            title: 'Arbeitslosengeld I (ALG I)',
            color: Colors.blue,
            items: [
              _kvRow('Voraussetzung', 'Mind. 12 Monate sozialversicherungspflichtig beschäftigt in den letzten 30 Monaten'),
              _kvRow('Höhe', '60% des letzten Netto-Entgelts (67% mit Kind)'),
              _kvRow('Höchstbetrag West', '~2.390 € / Monat'),
              _kvRow('Höchstbetrag Ost', '~2.320 € / Monat'),
              _kvRow('Dauer', '6–24 Monate (abhängig von Alter und Beschäftigungsdauer)'),
              _kvRow('Antrag', 'Bei der Agentur für Arbeit (spätestens 3 Monate vor Arbeitsende melden)'),
            ],
          ),
          const SizedBox(height: 12),

          // Bürgergeld
          _leistungCard(
            icon: Icons.home,
            title: 'Bürgergeld (ab 07/2026: Grundsicherungsgeld)',
            color: Colors.green,
            items: [
              _kvRow('Voraussetzung', 'Hilfebedürftig, erwerbsfähig, 15–65 Jahre, gewöhnlicher Aufenthalt in DE'),
              _kvRow('Regelsatz Alleinstehende', '563 € / Monat'),
              _kvRow('Regelsatz mit Partner', '506 € / Monat pro Person'),
              _kvRow('Kinder 14–17 J.', '471 € / Monat'),
              _kvRow('Kinder 6–13 J.', '390 € / Monat'),
              _kvRow('Kinder 0–5 J.', '357 € / Monat'),
              _kvRow('Zusätzlich', 'Kosten für Unterkunft + Heizung (angemessen)'),
              _kvRow('Reform 07/2026', 'Umbenennung in "Grundsicherungsgeld" – verschärfte Pflichten und Sanktionen'),
            ],
          ),
          const SizedBox(height: 12),

          // Kindergeld
          _leistungCard(
            icon: Icons.child_care,
            title: 'Kindergeld',
            color: Colors.pink,
            items: [
              _kvRow('Höhe', '255 € / Monat pro Kind (seit 01.01.2025)'),
              _kvRow('Anspruch', 'Für alle Kinder bis 18 J. (bis 25 J. bei Ausbildung/Studium)'),
              _kvRow('Antrag', 'Bei der Familienkasse'),
            ],
          ),
          const SizedBox(height: 12),

          // Wohngeld
          _leistungCard(
            icon: Icons.apartment,
            title: 'Wohngeld',
            color: Colors.teal,
            items: [
              _kvRow('Voraussetzung', 'Geringes Einkommen, kein Bürgergeld-Bezug'),
              _kvRow('Höhe', 'Abhängig von Einkommen, Miete, Haushaltsgröße und Wohnort'),
              _kvRow('Antrag', 'Bei der Wohngeldstelle der Gemeinde/Stadt'),
            ],
          ),
          const SizedBox(height: 12),

          // Weiterbildung
          _leistungCard(
            icon: Icons.school,
            title: 'Förderung beruflicher Weiterbildung',
            color: Colors.deepPurple,
            items: [
              _kvRow('Bildungsgutschein', 'Übernahme der Weiterbildungskosten durch die Agentur für Arbeit'),
              _kvRow('Weiterbildungsgeld', '150 € / Monat zusätzlich bei qualifizierter Weiterbildung'),
              _kvRow('Umschulung', 'Bis zu 2 Jahre gefördert (100% Kostenübernahme)'),
              _kvRow('Qualifizierungsgeld', 'Für Beschäftigte, deren Arbeitsplatz durch Strukturwandel bedroht ist'),
            ],
          ),
          const SizedBox(height: 12),

          // Gründungszuschuss
          _leistungCard(
            icon: Icons.rocket_launch,
            title: 'Gründungszuschuss',
            color: Colors.amber,
            items: [
              _kvRow('Voraussetzung', 'Arbeitslos gemeldet + Rest-ALG-Anspruch mind. 150 Tage'),
              _kvRow('Phase 1 (6 Mon.)', 'ALG I + 300 € / Monat'),
              _kvRow('Phase 2 (9 Mon.)', '300 € / Monat (Ermessenssache)'),
              _kvRow('Antrag', 'Bei der Agentur für Arbeit mit Businessplan + Tragfähigkeitsbescheinigung'),
            ],
          ),
          const SizedBox(height: 12),

          // Eingliederungszuschuss
          _leistungCard(
            icon: Icons.handshake,
            title: 'Eingliederungszuschuss (für Arbeitgeber)',
            color: Colors.cyan,
            items: [
              _kvRow('Zweck', 'Zuschuss zum Arbeitsentgelt für Arbeitnehmer mit Vermittlungshemmnissen'),
              _kvRow('Höhe', 'Bis zu 50% des Arbeitsentgelts'),
              _kvRow('Dauer', 'Bis zu 12 Monate (für Ältere bis 36 Monate)'),
              _kvRow('Antrag', 'Arbeitgeber stellt Antrag bei der Agentur für Arbeit'),
            ],
          ),
          const SizedBox(height: 12),

          // Kurzarbeitergeld
          _leistungCard(
            icon: Icons.timelapse,
            title: 'Kurzarbeitergeld',
            color: Colors.red,
            items: [
              _kvRow('Voraussetzung', 'Erheblicher Arbeitsausfall mit Entgeltausfall'),
              _kvRow('Höhe', '60% des Netto-Entgeltausfalls (67% mit Kind)'),
              _kvRow('Dauer', 'Bis zu 12 Monate'),
              _kvRow('Antrag', 'Arbeitgeber bei der Agentur für Arbeit'),
            ],
          ),
          const SizedBox(height: 12),

          // Insolvenzgeld
          _leistungCard(
            icon: Icons.warning_amber,
            title: 'Insolvenzgeld',
            color: Colors.brown,
            items: [
              _kvRow('Voraussetzung', 'Arbeitgeber ist insolvent'),
              _kvRow('Höhe', 'Netto-Entgelt für die letzten 3 Monate vor Insolvenz'),
              _kvRow('Antrag', 'Innerhalb von 2 Monaten nach Insolvenzereignis'),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  Widget _infoCard({
    required IconData icon,
    required String title,
    required String value,
    required String subtitle,
    required Color color,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ],
        ),
      ),
    );
  }

  TableRow _tableHeaderRow(List<String> cells) {
    return TableRow(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      children: cells
          .map((c) => Padding(
                padding: const EdgeInsets.all(10),
                child: Text(c, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ))
          .toList(),
    );
  }

  TableRow _tableRow(List<String> cells, {bool highlight = false, bool current = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: current
            ? Colors.green.shade50
            : highlight
                ? Colors.blue.shade50
                : null,
      ),
      children: cells
          .map((c) => Padding(
                padding: const EdgeInsets.all(10),
                child: Text(
                  c,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: current ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ))
          .toList(),
    );
  }

  Widget _egExplanation(String group, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 60,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.indigo.shade100,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              group,
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.indigo.shade800),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(description, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _brancheRow(String branche, String zuschlag) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          const SizedBox(width: 8),
          const Icon(Icons.circle, size: 6),
          const SizedBox(width: 8),
          Expanded(child: Text(branche, style: const TextStyle(fontSize: 13))),
          Text(zuschlag, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900)),
        ],
      ),
    );
  }

  Widget _leistungCard({
    required IconData icon,
    required String title,
    required Color color,
    required List<Widget> items,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 20),
            ...items,
          ],
        ),
      ),
    );
  }

  Widget _kvRow(String key, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 180,
            child: Text(key, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }
}
