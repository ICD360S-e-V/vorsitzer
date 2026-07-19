import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class BehordeLandratsamtContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeLandratsamtContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeLandratsamtContent> createState() => _BehordeLandratsamtContentState();
}

class _BehordeLandratsamtContentState extends State<BehordeLandratsamtContent> {
  Map<String, Map<String, dynamic>> _dbData = {};
  bool _loaded = false;
  Timer? _autoSaveTimer;

  @override
  void initState() {
    super.initState();
    _loadFromDB();
  }

  @override
  void dispose() {
    _autoSaveTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFromDB() async {
    final r = await widget.apiService.getLandratsamtData(widget.userId);
    if (!mounted) return;
    if (r['success'] == true && r['data'] is Map) {
      setState(() {
        final raw = r['data'] as Map;
        _dbData = {};
        for (final entry in raw.entries) {
          _dbData[entry.key.toString()] = Map<String, dynamic>.from(entry.value as Map);
        }
        _loaded = true;
      });
    } else {
      setState(() => _loaded = true);
    }
  }

  Future<void> _saveToDB() async {
    await widget.apiService.saveLandratsamtData(widget.userId, _dbData);
  }

  // Debounced auto-save — flushes 800ms after last edit.
  void _scheduleAutoSave() {
    _autoSaveTimer?.cancel();
    _autoSaveTimer = Timer(const Duration(milliseconds: 800), () { if (mounted) _saveToDB(); });
  }

  Map<String, dynamic> _bereich(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 7,
      child: Column(children: [
        TabBar(
          labelColor: Colors.brown.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.brown.shade700,
          isScrollable: true,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_bereich('amt')['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16), const SizedBox(width: 4), const Text('Zuständiges Landratsamt')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.report_problem, size: 16), const SizedBox(width: 4), const Text('Vorfall')])),
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.directions_car, size: 16), SizedBox(width: 4), Text('KFZ')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_bereich('fuehrerschein')['fs_nummer']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.badge, size: 16), const SizedBox(width: 4), const Text('Führerschein')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_bereich('bau')['genehmigung_nr']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.home_work, size: 16), const SizedBox(width: 4), const Text('Bau & Wohnen')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_bereich('umwelt')['biotonne']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.eco, size: 16), const SizedBox(width: 4), const Text('Umwelt & Natur')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_bereich('sonstiges')['waffenschein']?.toString() ?? '').isNotEmpty || (_bereich('sonstiges')['jagdschein']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.more_horiz, size: 16), const SizedBox(width: 4), const Text('Sonstiges')])),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _buildAmtTab(),
            _LandratsamtVorfallTab(apiService: widget.apiService, userId: widget.userId),
            _KfzTab(apiService: widget.apiService, userId: widget.userId),
            _buildFuehrerscheinTab(),
            _buildBauTab(),
            _buildUmweltTab(),
            _buildSonstigesTab(),
          ]),
        ),
      ]),
    );
  }

  // ============ AMT (zuständiges Landratsamt) ============
  static const _landratsamtListe = [
    {'name': 'Landratsamt Neu-Ulm', 'kurzname': 'LRA Neu-Ulm', 'adresse': 'Kantstraße 8', 'plz_ort': '89231 Neu-Ulm', 'telefon': '0731 7040-0', 'fax': '0731 7040-1199', 'email': 'poststelle@lra.neu-ulm.de', 'website': 'https://www.landkreis-nu.de', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeiten': 'KFZ-Zulassung, Führerscheinstelle, Bauordnung, Umwelt & Natur, Ausländerbehörde, Jugend & Familie, Soziale Leistungen, Jagd & Fischerei, Waffenrecht'},
    {'name': 'LRA Neu-Ulm — Außenstelle Illertissen', 'kurzname': 'LRA Illertissen', 'adresse': 'Ulmer Straße 20', 'plz_ort': '89257 Illertissen', 'telefon': '07303 9006-0', 'email': '', 'website': 'https://www.landkreis-nu.de', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeiten': 'KFZ-Zulassung (Außenstelle), Soziale Leistungen'},
    {'name': 'Landratsamt Alb-Donau-Kreis (Ulm)', 'kurzname': 'LRA Ulm', 'adresse': 'Schillerstraße 30', 'plz_ort': '89077 Ulm', 'telefon': '0731 185-0', 'email': 'info@alb-donau-kreis.de', 'website': 'https://www.alb-donau-kreis.de', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Do 14:00–17:30', 'zustaendigkeiten': 'KFZ-Zulassung, Führerschein, Baurecht, Umwelt'},
  ];

  Widget _buildAmtTab() {
    final amt = _bereich('amt');
    final selected = amt['name']?.toString() ?? '';
    final sel = _landratsamtListe.where((s) => s['name'] == selected).firstOrNull;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.account_balance, size: 20, color: Colors.brown.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständiges Landratsamt', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown.shade700))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: Text(selected.isEmpty ? 'Auswählen' : 'Ändern', style: const TextStyle(fontSize: 12)),
            onPressed: () => _showAmtSelectDialog(amt),
          ),
        ]),
        const SizedBox(height: 12),
        if (selected.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(children: [
              Icon(Icons.search, size: 40, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Kein Landratsamt ausgewählt', style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Tippen Sie auf "Auswählen" um das zuständige Amt zu suchen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          )
        else
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.brown.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.brown.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(selected, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown.shade900)),
              if (sel != null) ...[
                const SizedBox(height: 6),
                _infoRow(Icons.location_on, '${sel['adresse']}, ${sel['plz_ort']}'),
                _infoRow(Icons.phone, sel['telefon'] ?? ''),
                _infoRow(Icons.email, sel['email'] ?? ''),
                _infoRow(Icons.language, sel['website'] ?? ''),
                _infoRow(Icons.access_time, sel['oeffnungszeiten'] ?? ''),
                const SizedBox(height: 6),
                Text('Zuständig für:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.brown.shade700)),
                const SizedBox(height: 2),
                Text(sel['zustaendigkeiten'] ?? '', style: TextStyle(fontSize: 11, color: Colors.brown.shade600)),
              ],
            ]),
          ),
      ]),
    );
  }

  void _showAmtSelectDialog(Map<String, dynamic> amt) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.search, color: Colors.brown.shade700),
          const SizedBox(width: 8),
          const Text('Landratsamt auswählen'),
        ]),
        content: SizedBox(
          width: 500, height: 400,
          child: ListView(children: _landratsamtListe.map((s) {
            return InkWell(
              onTap: () {
                setState(() {
                  amt['name'] = s['name'];
                  amt['adresse'] = s['adresse'];
                  amt['plz_ort'] = s['plz_ort'];
                  amt['telefon'] = s['telefon'];
                  amt['email'] = s['email'];
                  amt['website'] = s['website'];
                  amt['oeffnungszeiten'] = s['oeffnungszeiten'];
                });
                _saveToDB();
                Navigator.pop(ctx);
              },
              borderRadius: BorderRadius.circular(10),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                child: Row(children: [
                  Icon(Icons.account_balance, size: 20, color: Colors.brown.shade600),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.brown.shade900)),
                    Text('${s['adresse']}, ${s['plz_ort']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    Text(s['zustaendigkeiten']!, style: TextStyle(fontSize: 10, color: Colors.brown.shade400, fontStyle: FontStyle.italic)),
                  ])),
                ]),
              ),
            );
          }).toList()),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      ),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    if (text.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
      ]),
    );
  }

  // ============ KFZ ZULASSUNGSSTELLE ============
  // KFZ ist jetzt eine eigene Liste (mehrere Fahrzeuge/Vorgänge pro Mitglied)
  // mit "+"-Button, Anlage-Modal und Detailansicht (Details / Dokumente /
  // Korrespondenz / Termine / ZB II / ZB I) → siehe _KfzTab am Dateiende.

  // ============ FÜHRERSCHEINSTELLE ============
  bool _fsEditing = false;

  Widget _buildFuehrerscheinTab() {
    final fs = _bereich('fuehrerschein');
    final termine = List<Map<String, dynamic>>.from(fs['termine'] is List ? fs['termine'] : []);
    final hasData = (fs['fs_nummer']?.toString() ?? '').isNotEmpty;
    final readOnly = hasData && !_fsEditing;

    return DefaultTabController(
      length: 2,
      child: Column(children: [
        TabBar(
          labelColor: Colors.green.shade700,
          indicatorColor: Colors.green.shade700,
          tabs: [
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: hasData ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.badge, size: 14), const SizedBox(width: 4), const Text('Führerschein')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: termine.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.calendar_month, size: 14), const SizedBox(width: 4), const Text('Termine')])),
          ],
        ),
        Expanded(child: TabBarView(children: [
          // === FÜHRERSCHEIN DATA (readonly + pencil edit) ===
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                _header(Icons.badge, 'Führerscheindaten', Colors.green),
                const Spacer(),
                if (hasData)
                  IconButton(
                    icon: Icon(_fsEditing ? Icons.check : Icons.edit, size: 20, color: Colors.green.shade700),
                    tooltip: _fsEditing ? 'Fertig' : 'Bearbeiten',
                    onPressed: () { if (_fsEditing) _saveToDB(); setState(() => _fsEditing = !_fsEditing); },
                  ),
              ]),
              const SizedBox(height: 12),
              if (readOnly) ...[
                _readOnlyRow(Icons.credit_card, 'FS-Nummer', fs['fs_nummer']),
                _readOnlyRow(Icons.calendar_today, 'Ausstellungsdatum', fs['ausstellungsdatum']),
                _readOnlyRow(Icons.event, 'Gültig bis', fs['gueltig_bis']),
                _readOnlyRow(Icons.account_balance, 'Ausstellende Behörde', fs['aussteller']),
                _readOnlyRow(Icons.category, 'Klassen', fs['klassen']),
                _readOnlyRow(Icons.language, 'Internationaler FS', fs['international']),
                _readOnlyRow(Icons.swap_horiz, 'Umtausch-Status', fs['umtausch']),
                _readOnlyRow(Icons.info, 'Auflagen', fs['auflagen']),
                _readOnlyRow(Icons.person, 'Sachbearbeiter', fs['sachbearbeiter']),
                _readOnlyRow(Icons.tag, 'Aktenzeichen', fs['aktenzeichen']),
                _readOnlyRow(Icons.note, 'Notizen', fs['notizen']),
              ] else ...[
                _field('Sachbearbeiter/in', fs, 'sachbearbeiter', Icons.person, hint: 'Name'),
                _field('Aktenzeichen', fs, 'aktenzeichen', Icons.tag),
                const Divider(height: 20),
                _field('Führerscheinnummer', fs, 'fs_nummer', Icons.credit_card, hint: 'Auf dem Führerschein'),
                _field('Ausstellungsdatum', fs, 'ausstellungsdatum', Icons.calendar_today, hint: 'TT.MM.JJJJ'),
                _field('Gültig bis', fs, 'gueltig_bis', Icons.event, hint: 'TT.MM.JJJJ (oder unbefristet)'),
                _field('Ausstellende Behörde', fs, 'aussteller', Icons.account_balance, hint: 'z.B. Landratsamt Neu-Ulm'),
                _field('Klassen', fs, 'klassen', Icons.category, hint: 'z.B. B, AM, L'),
                _dropDown('Internationaler FS', fs, 'international', Icons.language, {'': 'Nicht vorhanden', 'beantragt': 'Beantragt', 'vorhanden': 'Vorhanden'}),
                _dropDown('Umtausch-Status', fs, 'umtausch', Icons.swap_horiz, {'': 'Nicht erforderlich', 'faellig': 'Fällig (bis 2033)', 'beantragt': 'Umtausch beantragt', 'erledigt': 'Neuer FS erhalten'}),
                _field('Auflagen / Schlüsselzahlen', fs, 'auflagen', Icons.info, hint: 'z.B. 01.01 — Brille'),
                _field('Notizen', fs, 'notizen', Icons.note, hint: '', maxLines: 3),
              ],
            ]),
          ),
          // === TERMINE ===
          Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(children: [
                Icon(Icons.calendar_month, size: 20, color: Colors.green.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text('Termine Führerscheinstelle', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
                ElevatedButton.icon(
                  onPressed: () {
                    final datumC = TextEditingController();
                    final uhrzeitC = TextEditingController();
                    final notizenC = TextEditingController();
                    showDialog(context: context, builder: (ctx) => AlertDialog(
                      title: const Text('Neuer Termin'),
                      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                          final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
                        }),
                        const SizedBox(height: 8),
                        TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                        const SizedBox(height: 8),
                        TextField(controller: notizenC, maxLines: 3, decoration: InputDecoration(labelText: 'Anlass / Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                      ])),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                        FilledButton(onPressed: () {
                          if (datumC.text.isEmpty) return;
                          setState(() { termine.add({'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'notizen': notizenC.text}); fs['termine'] = termine; });
                          _saveToDB();
                          Navigator.pop(ctx);
                        }, child: const Text('Speichern')),
                      ],
                    ));
                  },
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Neuer Termin'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                ),
              ]),
            ),
            Expanded(
              child: termine.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.event_available, size: 48, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('Keine Termine', style: TextStyle(color: Colors.grey.shade500)),
                    ]))
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: termine.length,
                      itemBuilder: (_, i) {
                        final t = termine[i];
                        return Card(child: ListTile(
                          leading: Icon(Icons.event, color: Colors.green.shade700),
                          title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: (t['notizen']?.toString() ?? '').isNotEmpty ? Text(t['notizen'].toString(), style: const TextStyle(fontSize: 11)) : null,
                          trailing: IconButton(icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400), onPressed: () {
                            setState(() { termine.removeAt(i); fs['termine'] = termine; });
                            _saveToDB();
                          }),
                        ));
                      },
                    ),
            ),
          ]),
        ])),
      ]),
    );
  }

  Widget _readOnlyRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }

  // ============ BAU & WOHNEN ============
  Widget _buildBauTab() {
    final bau = _bereich('bau');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.home_work, 'Bauordnung & Wohnen', Colors.orange),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', bau, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', bau, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Baugenehmigung Nr.', bau, 'genehmigung_nr', Icons.description),
        _field('Objekt / Adresse', bau, 'objekt', Icons.location_on),
        _dropDown('Status', bau, 'status', Icons.check_circle, {'': '–', 'beantragt': 'Beantragt', 'genehmigt': 'Genehmigt', 'abgelehnt': 'Abgelehnt', 'im_bau': 'Im Bau', 'fertiggestellt': 'Fertiggestellt'}),
        _field('Notizen', bau, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ UMWELT & NATUR ============
  Widget _buildUmweltTab() {
    final umw = _bereich('umwelt');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.eco, 'Umwelt, Natur & Abfall', Colors.green),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', umw, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', umw, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Biotonne Nr.', umw, 'biotonne', Icons.delete),
        _field('Restmülltonne Nr.', umw, 'restmuell', Icons.delete_outline),
        _field('Wertstofftonne Nr.', umw, 'wertstoff', Icons.recycling),
        _field('Sperrmüll-Termin', umw, 'sperrmuell', Icons.calendar_today),
        _field('Notizen', umw, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ SONSTIGES ============
  Widget _buildSonstigesTab() {
    final son = _bereich('sonstiges');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.more_horiz, 'Sonstige Anliegen', Colors.grey),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', son, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', son, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Waffenschein', son, 'waffenschein', Icons.gavel, hint: 'Nr. oder Status'),
        _field('Jagdschein', son, 'jagdschein', Icons.park, hint: 'Nr. oder Status'),
        _field('Fischereischein', son, 'fischereischein', Icons.water, hint: 'Nr. oder Status'),
        _field('Notizen', son, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

  // ============ HELPERS ============
  Widget _header(IconData icon, String title, Color color) {
    return Row(children: [
      Icon(icon, size: 22, color: color),
      const SizedBox(width: 8),
      Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color)),
    ]);
  }

  Widget _field(String label, Map<String, dynamic> map, String key, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: TextEditingController(text: map[key]?.toString() ?? ''),
        maxLines: maxLines,
        onChanged: (v) { map[key] = v; _scheduleAutoSave(); },
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _dropDown(String label, Map<String, dynamic> map, String key, IconData icon, Map<String, String> options) {
    final current = map[key]?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 18),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: options.containsKey(current) ? current : '',
            isDense: true,
            isExpanded: true,
            items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) { setState(() => map[key] = v ?? ''); _saveToDB(); },
          ),
        ),
      ),
    );
  }
}

// ============================================================
// VORFALL — separate state, eigene DB-Tabelle
// ============================================================

// Vorfall-Arten die ein Landratsamt federführend oder als Anlaufstelle
// bearbeitet. Praxisstruktur (bayerisches / BW-LRA):
//   • Betreuungsbehörde (§§ 5-11 BtOG)
//   • Schuldner-/Insolvenzberatung (§ 305 InsO Vorbereitung) — Anerkennung
//     als "geeignete Stelle" ist landesrechtlich geregelt; nicht jedes LRA
//     hat eine eigene anerkannte Stelle, viele delegieren an Caritas/
//     Diakonie/AWO. Deshalb neutrale Formulierung im Dropdown.
//   • Sozialhilfe im engeren Sinn (SGB XII / P-Konto).
// Reihenfolge § 305 InsO: Erstberatung → Gläubigerübersicht →
// Schuldenbereinigungsplan → außergerichtlicher Einigungsversuch →
// Bescheinigung → Insolvenzgericht.
const _landratsamtVorfallArten = [
  // === Betreuungsbehörde ===
  'Verfahrensbetreuung (Anordnung Betreuungsgericht)',
  'Betreuungsanregung',
  'Sozialbericht / Stellungnahme an Gericht',
  'Hausbesuch / Ermittlung',
  'Beratung Betroffene/r',
  'Beratung Angehörige',
  'Begleitung Anhörung Betreuungsgericht',
  'Vorsorgevollmacht / Betreuungsverfügung — Beglaubigung (§ 7 BtOG)',
  // === Schuldner-/Insolvenzberatung (§ 305 InsO Vorbereitung) ===
  'Schuldner-/Insolvenzberatung — Erstberatung',
  'Schuldnerberatung — Gläubigerübersicht / Forderungsaufstellung',
  'Schuldnerberatung — Schuldenbereinigungsplan erstellen',
  'Schuldnerberatung — Außergerichtlicher Einigungsversuch (§ 305 InsO)',
  'Insolvenzantrag — Bescheinigung § 305 Abs. 1 Nr. 1 InsO ausgestellt',
  'Insolvenzantrag — Antrag an Insolvenzgericht eingereicht',
  'P-Konto-Bescheinigung ausgestellt',
  // === Sozialhilfe (SGB XII) ===
  'Grundsicherung im Alter / bei Erwerbsminderung (SGB XII Kap. 4)',
  'Hilfe zum Lebensunterhalt (SGB XII Kap. 3)',
  'Sonstiges',
];

class _LandratsamtVorfallTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _LandratsamtVorfallTab({required this.apiService, required this.userId});

  @override
  State<_LandratsamtVorfallTab> createState() => _LandratsamtVorfallTabState();
}

class _LandratsamtVorfallTabState extends State<_LandratsamtVorfallTab> {
  List<Map<String, dynamic>> _vorfaelle = [];
  Map<int, Map<String, dynamic>> _gerichtById = {};
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listLandratsamtVorfaelle(widget.userId);
    final gR = await widget.apiService.listGerichtVorfaelle(widget.userId, 'betreuungsgericht');
    if (!mounted) return;
    setState(() {
      _vorfaelle = (r['success'] == true && r['data'] is List)
          ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      _gerichtById = {};
      if (gR['success'] == true && gR['data'] is List) {
        for (final g in (gR['data'] as List)) {
          final m = Map<String, dynamic>.from(g as Map);
          final id = int.tryParse(m['id']?.toString() ?? '');
          if (id != null) _gerichtById[id] = m;
        }
      }
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.report_problem, size: 20, color: Colors.brown.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text('Vorfälle (${_vorfaelle.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown.shade700))),
        ElevatedButton.icon(
          onPressed: () => _openDialog(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neuer Vorfall', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: _vorfaelle.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.folder_open, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Keine Vorfälle', style: TextStyle(color: Colors.grey.shade500)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _vorfaelle.length,
              itemBuilder: (_, i) {
                final v = _vorfaelle[i];
                final gId = int.tryParse(v['gericht_vorfall_id']?.toString() ?? '');
                final gLink = gId != null ? _gerichtById[gId] : null;
                return Card(child: ListTile(
                  leading: Icon(Icons.report_problem, color: Colors.brown.shade700, size: 28),
                  title: Text(v['art']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${v['datum'] ?? ''}  ·  Az.: ${v['aktenzeichen'] ?? '–'}', style: const TextStyle(fontSize: 11)),
                    if ((v['sachbearbeiter']?.toString() ?? '').isNotEmpty)
                      Text(v['sachbearbeiter'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    if (gLink != null) Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.deepPurple.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.deepPurple.shade300),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.gavel, size: 11, color: Colors.deepPurple.shade700),
                          const SizedBox(width: 3),
                          Text('Betreuungsgericht: ${gLink['titel'] ?? ''} · Az. ${gLink['aktenzeichen'] ?? '–'}',
                            style: TextStyle(fontSize: 10, color: Colors.deepPurple.shade900)),
                        ]),
                      ),
                    ),
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                      onPressed: () async {
                        final id = int.tryParse(v['id']?.toString() ?? '');
                        if (id != null) {
                          await widget.apiService.deleteLandratsamtVorfall(id);
                          await _load();
                        }
                      }),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ]),
                  onTap: () => _openDetail(v),
                ));
              },
            )),
    ]);
  }

  Future<void> _openDialog({Map<String, dynamic>? existing}) async {
    final id = int.tryParse(existing?['id']?.toString() ?? '');
    final artC = TextEditingController(text: existing?['art']?.toString() ?? '');
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final aktenC = TextEditingController(text: existing?['aktenzeichen']?.toString() ?? '');
    final sachC = TextEditingController(text: existing?['sachbearbeiter']?.toString() ?? '');
    final telC = TextEditingController(text: existing?['sachbearbeiter_tel']?.toString() ?? '');
    final emailC = TextEditingController(text: existing?['sachbearbeiter_email']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    int? linkedGerichtId = int.tryParse(existing?['gericht_vorfall_id']?.toString() ?? '');
    bool submitting = false;

    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(id != null ? 'Vorfall bearbeiten' : 'Neuer Vorfall', style: TextStyle(color: Colors.brown.shade700)),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            initialValue: _landratsamtVorfallArten.contains(artC.text) ? artC.text : null,
            decoration: InputDecoration(labelText: 'Art *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _landratsamtVorfallArten.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setD(() => artC.text = v ?? ''),
          ),
          const SizedBox(height: 8),
          TextField(controller: datumC, readOnly: true,
            decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async {
              final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
            }),
          const SizedBox(height: 8),
          TextField(controller: aktenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.tag, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: sachC, decoration: InputDecoration(labelText: 'Sachbearbeiter/in (Person)', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: telC, decoration: InputDecoration(labelText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: emailC, decoration: InputDecoration(labelText: 'E-Mail', prefixIcon: const Icon(Icons.email, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.gavel, size: 16, color: Colors.deepPurple.shade700),
                const SizedBox(width: 6),
                Text('Verknüpfung Betreuungsgericht-Vorfall', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
              ]),
              const SizedBox(height: 6),
              if (_gerichtById.isEmpty)
                Text('Keine Vorfälle in Betreuungsgericht angelegt.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))
              else
                DropdownButtonFormField<int?>(
                  initialValue: linkedGerichtId,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: 'Betreuungsgericht-Vorfall', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('— keine Verknüpfung —', style: TextStyle(fontSize: 12))),
                    ..._gerichtById.entries.map((e) => DropdownMenuItem<int?>(
                      value: e.key,
                      child: Text('${e.value['titel'] ?? ''} · Az. ${e.value['aktenzeichen'] ?? '–'} · ${e.value['datum'] ?? ''}', style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis),
                    )),
                  ],
                  onChanged: (v) => setD(() => linkedGerichtId = v),
                ),
            ]),
          ),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              if (artC.text.trim().isEmpty || datumC.text.trim().isEmpty) return;
              setD(() => submitting = true);
              await widget.apiService.saveLandratsamtVorfall(widget.userId, {
                if (id != null) 'id': id,
                'art': artC.text.trim(),
                'datum': datumC.text.trim(),
                'aktenzeichen': aktenC.text.trim(),
                'sachbearbeiter': sachC.text.trim(),
                'sachbearbeiter_tel': telC.text.trim(),
                'sachbearbeiter_email': emailC.text.trim(),
                'notiz': notizC.text.trim(),
                'gericht_vorfall_id': linkedGerichtId,
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  void _openDetail(Map<String, dynamic> v) {
    final vid = int.tryParse(v['id']?.toString() ?? '');
    if (vid == null) return;
    final gId = int.tryParse(v['gericht_vorfall_id']?.toString() ?? '');
    final gLink = gId != null ? _gerichtById[gId] : null;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 760, height: 640,
          child: _LandratsamtVorfallDetailView(
            apiService: widget.apiService,
            userId: widget.userId,
            vorfallId: vid,
            vorfall: v,
            gerichtLink: gLink,
            onEdit: () { Navigator.pop(ctx); _openDialog(existing: v); },
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      ),
    ).then((_) => _load());
  }
}

class _LandratsamtVorfallDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int vorfallId;
  final Map<String, dynamic> vorfall;
  final Map<String, dynamic>? gerichtLink;
  final VoidCallback onEdit;
  final VoidCallback onClose;
  const _LandratsamtVorfallDetailView({
    required this.apiService, required this.userId, required this.vorfallId, required this.vorfall,
    required this.gerichtLink, required this.onEdit, required this.onClose,
  });

  @override
  State<_LandratsamtVorfallDetailView> createState() => _LandratsamtVorfallDetailViewState();
}

class _LandratsamtVorfallDetailViewState extends State<_LandratsamtVorfallDetailView> {
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _termine = [];
  Map<String, dynamic> _amt = {};
  bool _loadedKorr = false;
  bool _loadedTermine = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final kR = await widget.apiService.listLandratsamtVorfallKorr(widget.vorfallId);
    final tR = await widget.apiService.listLandratsamtVorfallTermine(widget.vorfallId);
    final aR = await widget.apiService.getLandratsamtData(widget.userId);
    if (!mounted) return;
    setState(() {
      _korr = (kR['success'] == true && kR['data'] is List)
          ? (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _termine = (tR['success'] == true && tR['data'] is List)
          ? (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      if (aR['success'] == true && aR['data'] is Map) {
        final raw = aR['data'] as Map;
        final amt = raw['amt'];
        _amt = amt is Map ? Map<String, dynamic>.from(amt) : {};
      } else {
        _amt = {};
      }
      _loadedKorr = true;
      _loadedTermine = true;
    });
  }

  // "Landratsamt Neu-Ulm, Kantstraße 8, 89231 Neu-Ulm" — frei weglassbar.
  String _amtAdresseInline() {
    final parts = <String>[];
    final name = _amt['name']?.toString().trim() ?? '';
    final adr = _amt['adresse']?.toString().trim() ?? '';
    final plz = _amt['plz_ort']?.toString().trim() ?? '';
    if (name.isNotEmpty) parts.add(name);
    if (adr.isNotEmpty) parts.add(adr);
    if (plz.isNotEmpty) parts.add(plz);
    return parts.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          decoration: BoxDecoration(color: Colors.brown.shade50, border: Border(bottom: BorderSide(color: Colors.brown.shade200))),
          child: Row(children: [
            Icon(Icons.report_problem, color: Colors.brown.shade700, size: 22),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.vorfall['art']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.brown.shade900)),
              Text('${widget.vorfall['datum'] ?? ''} · Az.: ${widget.vorfall['aktenzeichen'] ?? '–'}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ])),
            IconButton(icon: const Icon(Icons.edit, size: 18), onPressed: widget.onEdit, tooltip: 'Bearbeiten'),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: widget.onClose, tooltip: 'Schließen'),
          ]),
        ),
        TabBar(
          labelColor: Colors.brown.shade700,
          indicatorColor: Colors.brown.shade700,
          isScrollable: true,
          tabs: [
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.info_outline, size: 14), SizedBox(width: 4), Text('Details')])),
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.folder_open, size: 14), SizedBox(width: 4), Text('Dokumente')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.mail_outline, size: 14), const SizedBox(width: 4), Text('Korrespondenz (${_korr.length})')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event, size: 14), const SizedBox(width: 4), Text('Termin (${_termine.length})')])),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildDetailsTab(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: KorrAttachmentsWidget(
              apiService: widget.apiService,
              modul: 'landratsamt_vorfall',
              korrespondenzId: widget.vorfallId,
            ),
          ),
          _buildKorrTab(),
          _buildTerminTab(),
        ])),
      ]),
    );
  }

  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _kv(Icons.label, 'Art', widget.vorfall['art']),
        _kv(Icons.calendar_today, 'Datum', widget.vorfall['datum']),
        _kv(Icons.tag, 'Aktenzeichen', widget.vorfall['aktenzeichen']),
        const Divider(height: 20),
        _kv(Icons.person, 'Sachbearbeiter/in', widget.vorfall['sachbearbeiter']),
        _kv(Icons.phone, 'Telefon', widget.vorfall['sachbearbeiter_tel']),
        _kv(Icons.email, 'E-Mail', widget.vorfall['sachbearbeiter_email']),
        const Divider(height: 20),
        _kv(Icons.note, 'Notiz', widget.vorfall['notiz']),
        if (widget.gerichtLink != null) ...[
          const Divider(height: 20),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.gavel, size: 16, color: Colors.deepPurple.shade700),
                const SizedBox(width: 6),
                Text('Verknüpfter Betreuungsgericht-Vorfall', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
              ]),
              const SizedBox(height: 6),
              _kv(Icons.label, 'Art', widget.gerichtLink!['titel']),
              _kv(Icons.tag, 'Aktenzeichen', widget.gerichtLink!['aktenzeichen']),
              _kv(Icons.calendar_today, 'Datum', widget.gerichtLink!['datum']),
              _kv(Icons.person, 'Richter', widget.gerichtLink!['sachbearbeiter']),
              _kv(Icons.flag, 'Status', widget.gerichtLink!['status']),
              if ((widget.gerichtLink!['notiz']?.toString() ?? '').isNotEmpty) _kv(Icons.note, 'Notiz', widget.gerichtLink!['notiz']),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _buildKorrTab() {
    if (!_loadedKorr) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
        Icon(Icons.mail_outline, size: 18, color: Colors.brown.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Korrespondenz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.brown.shade700))),
        ElevatedButton.icon(
          onPressed: _addKorr,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
        ),
      ])),
      Expanded(child: _korr.isEmpty
          ? Center(child: Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _korr.length,
              itemBuilder: (_, i) {
                final k = _korr[i];
                final kid = int.tryParse(k['id']?.toString() ?? '');
                final rich = k['richtung']?.toString() ?? 'eingang';
                final isEin = rich == 'eingang';
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(isEin ? Icons.call_received : Icons.call_made,
                          color: isEin ? Colors.green.shade600 : Colors.blue.shade600, size: 22),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k['betreff']?.toString() ?? '(ohne Betreff)',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('${k['datum'] ?? ''}  ·  ${isEin ? 'Eingang' : 'Ausgang'}  ·  ${k['methode'] ?? '–'}',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          if ((k['notiz']?.toString() ?? '').isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 2),
                              child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 11))),
                        ])),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          onPressed: () async {
                            if (kid != null) { await widget.apiService.deleteLandratsamtVorfallKorr(kid); await _load(); }
                          },
                        ),
                      ]),
                      if (kid != null) Padding(
                        padding: const EdgeInsets.only(top: 6, left: 30),
                        child: KorrAttachmentsWidget(
                          apiService: widget.apiService,
                          modul: 'landratsamt_vorfall_korr',
                          korrespondenzId: kid,
                        ),
                      ),
                    ]),
                  ),
                );
              },
            )),
    ]);
  }

  Future<void> _addKorr() async {
    String richtung = 'eingang';
    String methode = 'post';
    bool submitting = false;
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Korrespondenz'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_received, size: 14, color: richtung == 'eingang' ? Colors.white : Colors.green.shade600),
              const SizedBox(width: 4), Text('Eingang', style: TextStyle(fontSize: 12, color: richtung == 'eingang' ? Colors.white : Colors.black87)),
            ]), selected: richtung == 'eingang', selectedColor: Colors.green.shade600, onSelected: (_) => setD(() => richtung = 'eingang'))),
            const SizedBox(width: 8),
            Expanded(child: ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_made, size: 14, color: richtung == 'ausgang' ? Colors.white : Colors.blue.shade600),
              const SizedBox(width: 4), Text('Ausgang', style: TextStyle(fontSize: 12, color: richtung == 'ausgang' ? Colors.white : Colors.black87)),
            ]), selected: richtung == 'ausgang', selectedColor: Colors.blue.shade600, onSelected: (_) => setD(() => richtung = 'ausgang'))),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: methode,
            decoration: InputDecoration(labelText: 'Methode', prefixIcon: const Icon(Icons.send, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: const [
              DropdownMenuItem(value: 'post', child: Text('Post')),
              DropdownMenuItem(value: 'online', child: Text('Online (E-Mail / Portal)')),
              DropdownMenuItem(value: 'fax', child: Text('Fax')),
              DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')),
            ],
            onChanged: (v) => setD(() => methode = v ?? 'post'),
          ),
          const SizedBox(height: 8),
          TextField(controller: datumC, readOnly: true,
            decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async {
              final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
            }),
          const SizedBox(height: 8),
          TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', prefixIcon: const Icon(Icons.title, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              if (datumC.text.trim().isEmpty) return;
              setD(() => submitting = true);
              await widget.apiService.saveLandratsamtVorfallKorr(widget.vorfallId, widget.userId, {
                'richtung': richtung,
                'methode': methode,
                'datum': datumC.text.trim(),
                'betreff': betreffC.text.trim(),
                'notiz': notizC.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  Widget _buildTerminTab() {
    if (!_loadedTermine) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
        Icon(Icons.event, size: 18, color: Colors.brown.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Termine', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.brown.shade700))),
        ElevatedButton.icon(
          onPressed: _addTermin,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
        ),
      ])),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text(
              'Termine werden automatisch in die Terminverwaltung übernommen (mit Institution + Sachbearbeiter).',
              style: TextStyle(fontSize: 10, color: Colors.blue.shade900),
            )),
          ]),
        ),
      ),
      Expanded(child: _termine.isEmpty
          ? Center(child: Text('Keine Termine', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: _termine.length,
              itemBuilder: (_, i) {
                final t = _termine[i];
                final hasGlobal = (t['termin_id']?.toString() ?? '').isNotEmpty && t['termin_id'] != null;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.event, color: Colors.brown.shade700, size: 22),
                    title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? '  ·  ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((t['ort']?.toString() ?? '').isNotEmpty) Text('Ort: ${t['ort']}', style: const TextStyle(fontSize: 11)),
                      if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: const TextStyle(fontSize: 11)),
                      if (hasGlobal) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Icon(Icons.check_circle, size: 10, color: Colors.green.shade600),
                          const SizedBox(width: 3),
                          Text('In Terminverwaltung übernommen', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                      onPressed: () async {
                        final id = int.tryParse(t['id']?.toString() ?? '');
                        if (id != null) { await widget.apiService.deleteLandratsamtVorfallTermin(id); await _load(); }
                      },
                    ),
                  ),
                );
              },
            )),
    ]);
  }

  Future<void> _addTermin() async {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController(text: _amtAdresseInline());
    final notizC = TextEditingController();
    bool submitting = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Neuer Termin'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: datumC, readOnly: true,
              decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
              })),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: uhrzeitC, readOnly: true,
              decoration: InputDecoration(labelText: 'Uhrzeit *', prefixIcon: const Icon(Icons.access_time, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final t = await showTimePicker(context: ctx2, initialTime: const TimeOfDay(hour: 9, minute: 0));
                if (t != null) uhrzeitC.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              })),
          ]),
          const SizedBox(height: 8),
          TextField(controller: ortC, decoration: InputDecoration(labelText: 'Ort', prefixIcon: const Icon(Icons.place, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz / Anlass', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text(
                'Termin wird automatisch in der Terminverwaltung erstellt mit Institution & Sachbearbeiter aus diesem Vorfall.',
                style: TextStyle(fontSize: 10, color: Colors.blue.shade900),
              )),
            ]),
          ),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              if (datumC.text.trim().isEmpty || uhrzeitC.text.trim().isEmpty) return;
              setD(() => submitting = true);
              await widget.apiService.saveLandratsamtVorfallTermin(widget.vorfallId, widget.userId, {
                'datum': datumC.text.trim(),
                'uhrzeit': uhrzeitC.text.trim(),
                'ort': ortC.text.trim(),
                'notiz': notizC.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  Widget _kv(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}

// ============================================================
// KFZ-ZULASSUNG — mehrere Fahrzeuge/Vorgänge pro Mitglied.
// Liste + "+" (Anlage-Modal) + Detailansicht mit Tabs:
//   Details · Dokumente · Korrespondenz · Termine
//   · Brief groß (ZB Teil II / Fahrzeugbrief)
//   · Brief klein (ZB Teil I / Fahrzeugschein)
// Eigene Tabelle (kfz_zulassung), Spalten-Encryption + felder-JSON-Blob
// mit den EU-codierten Zulassungsbescheinigungs-Feldern.
// ============================================================

const _kfzVorgangsarten = {
  'neuzulassung': 'Neuzulassung (Neufahrzeug)',
  'erstzulassung_gebraucht': 'Erstzulassung Gebrauchtwagen',
  'umschreibung': 'Umschreibung (Halterwechsel)',
  'ummeldung': 'Ummeldung (Umzug)',
  'wiederzulassung': 'Wiederzulassung',
  'adressaenderung': 'Adressänderung',
  'kennzeichenwechsel': 'Kennzeichenwechsel / Wunschkennzeichen',
  'saison': 'Saisonkennzeichen',
  'abmeldung': 'Abmeldung / Außerbetriebsetzung',
  'export': 'Ausfuhr / Export',
  'verlust_ersatz': 'Verlust / Ersatz Dokumente',
  'sonstiges': 'Sonstiges',
};

const _kfzStatusLabels = {
  'in_bearbeitung': 'In Bearbeitung',
  'zugelassen': 'Zugelassen',
  'abgemeldet': 'Abgemeldet',
  'stillgelegt': 'Stillgelegt',
  'export': 'Exportiert',
};

MaterialColor _kfzStatusColor(String s) {
  switch (s) {
    case 'zugelassen': return Colors.green;
    case 'in_bearbeitung': return Colors.orange;
    case 'export': return Colors.indigo;
    case 'abgemeldet':
    case 'stillgelegt': return Colors.grey;
    default: return Colors.blueGrey;
  }
}

class _KfzTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _KfzTab({required this.apiService, required this.userId});

  @override
  State<_KfzTab> createState() => _KfzTabState();
}

class _KfzTabState extends State<_KfzTab> {
  List<Map<String, dynamic>> _kfzListe = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r = await widget.apiService.listKfzZulassung(widget.userId);
    if (!mounted) return;
    setState(() {
      _kfzListe = (r['success'] == true && r['data'] is List)
          ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.directions_car, size: 20, color: Colors.blue.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text('KFZ-Zulassungen (${_kfzListe.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade700))),
        ElevatedButton.icon(
          onPressed: () => _openDialog(),
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neues KFZ', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
        ),
      ])),
      Expanded(child: _kfzListe.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.no_crash, size: 48, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Keine Fahrzeuge angelegt', style: TextStyle(color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text('Auf "Neues KFZ" tippen, um einen Zulassungsvorgang anzulegen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _kfzListe.length,
              itemBuilder: (_, i) {
                final k = _kfzListe[i];
                final kennz = k['kennzeichen']?.toString() ?? '';
                final marke = k['marke']?.toString() ?? '';
                final fin = k['fin']?.toString() ?? '';
                final vart = k['vorgangsart']?.toString() ?? '';
                final status = k['status']?.toString() ?? '';
                return Card(child: ListTile(
                  leading: CircleAvatar(
                    radius: 18,
                    backgroundColor: Colors.blue.shade50,
                    child: Icon(Icons.directions_car, color: Colors.blue.shade700, size: 20),
                  ),
                  title: Text(kennz.isNotEmpty ? kennz : (marke.isNotEmpty ? marke : '(ohne Kennzeichen)'),
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (marke.isNotEmpty && kennz.isNotEmpty) Text(marke, style: const TextStyle(fontSize: 12)),
                    if (fin.isNotEmpty) Text('FIN: $fin', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    Padding(padding: const EdgeInsets.only(top: 4), child: Wrap(spacing: 6, runSpacing: 4, children: [
                      if (vart.isNotEmpty) _tag(_kfzVorgangsarten[vart] ?? vart, Colors.blue),
                      if (status.isNotEmpty) _tag(_kfzStatusLabels[status] ?? status, _kfzStatusColor(status)),
                    ])),
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                      onPressed: () => _confirmDelete(k)),
                    Icon(Icons.chevron_right, color: Colors.grey.shade400),
                  ]),
                  onTap: () => _openDetail(k),
                ));
              },
            )),
    ]);
  }

  Widget _tag(String text, MaterialColor c) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(color: c.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: c.shade200)),
    child: Text(text, style: TextStyle(fontSize: 10, color: c.shade800, fontWeight: FontWeight.w600)),
  );

  Future<void> _confirmDelete(Map<String, dynamic> k) async {
    final id = int.tryParse(k['id']?.toString() ?? '');
    if (id == null) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Fahrzeug löschen?'),
      content: Text('„${k['kennzeichen'] ?? k['marke'] ?? 'Fahrzeug'}" inkl. Korrespondenz, Termine und Dokumente unwiderruflich löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton(style: FilledButton.styleFrom(backgroundColor: Colors.red), onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen')),
      ],
    ));
    if (ok == true) { await widget.apiService.deleteKfzZulassung(id); await _load(); }
  }

  // Anlage-Modal (neuer Datensatz). Stammdaten hier, Detailfelder (ZB I/II)
  // werden anschließend in der Detailansicht ausgefüllt.
  Future<void> _openDialog() async {
    String vorgangsart = 'neuzulassung';
    String status = 'in_bearbeitung';
    final datumC = TextEditingController();
    final kennzC = TextEditingController();
    final markeC = TextEditingController();
    final finC = TextEditingController();
    final halterC = TextEditingController();
    final sachC = TextEditingController();
    final telC = TextEditingController();
    final emailC = TextEditingController();
    final aktenC = TextEditingController();
    final notizC = TextEditingController();
    bool submitting = false;

    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [Icon(Icons.directions_car, color: Colors.blue.shade700), const SizedBox(width: 8), const Text('Neues KFZ / Vorgang')]),
        content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          DropdownButtonFormField<String>(
            initialValue: vorgangsart,
            isExpanded: true,
            decoration: InputDecoration(labelText: 'Vorgangsart *', prefixIcon: const Icon(Icons.category, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _kfzVorgangsarten.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) => setD(() => vorgangsart = v ?? 'neuzulassung'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: DropdownButtonFormField<String>(
              initialValue: status,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Status', prefixIcon: const Icon(Icons.flag, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: _kfzStatusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setD(() => status = v ?? 'in_bearbeitung'),
            )),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: datumC, readOnly: true,
              decoration: InputDecoration(labelText: 'Vorgangsdatum', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
                if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
              })),
          ]),
          const Divider(height: 20),
          Row(children: [
            Expanded(child: TextField(controller: kennzC, textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(labelText: 'Kennzeichen', hintText: 'z.B. NU-AB 1234', prefixIcon: const Icon(Icons.confirmation_number, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: markeC,
              decoration: InputDecoration(labelText: 'Fahrzeug / Marke', hintText: 'z.B. VW Golf 7', prefixIcon: const Icon(Icons.directions_car, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: finC, textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: 'FIN (Fahrzeug-Ident-Nr.)', hintText: '17-stellig', prefixIcon: const Icon(Icons.qr_code, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: halterC,
            decoration: InputDecoration(labelText: 'Halter (Name)', prefixIcon: const Icon(Icons.person_pin, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const Divider(height: 20),
          TextField(controller: sachC, decoration: InputDecoration(labelText: 'Sachbearbeiter/in', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: telC, decoration: InputDecoration(labelText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: emailC, decoration: InputDecoration(labelText: 'E-Mail', prefixIcon: const Icon(Icons.email, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 8),
          TextField(controller: aktenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.tag, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Die Fahrzeugbrief- (ZB II) und Fahrzeugschein-Daten (ZB I) werden anschließend in der Detailansicht erfasst.', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
            ]),
          ),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              setD(() => submitting = true);
              await widget.apiService.saveKfzZulassung(widget.userId, {
                'vorgangsart': vorgangsart,
                'status': status,
                'datum': datumC.text.trim(),
                'kennzeichen': kennzC.text.trim(),
                'marke': markeC.text.trim(),
                'fin': finC.text.trim(),
                'halter_name': halterC.text.trim(),
                'sachbearbeiter': sachC.text.trim(),
                'sachbearbeiter_tel': telC.text.trim(),
                'sachbearbeiter_email': emailC.text.trim(),
                'aktenzeichen': aktenC.text.trim(),
                'notiz': notizC.text.trim(),
                'felder': <String, dynamic>{},
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Anlegen'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  void _openDetail(Map<String, dynamic> k) {
    final kid = int.tryParse(k['id']?.toString() ?? '');
    if (kid == null) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 820, height: 660,
          child: _KfzDetailView(
            apiService: widget.apiService,
            userId: widget.userId,
            kfzId: kid,
            kfz: k,
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      ),
    ).then((_) => _load());
  }
}

class _KfzDetailView extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final int kfzId;
  final Map<String, dynamic> kfz;
  final VoidCallback onClose;
  const _KfzDetailView({
    required this.apiService, required this.userId, required this.kfzId,
    required this.kfz, required this.onClose,
  });

  @override
  State<_KfzDetailView> createState() => _KfzDetailViewState();
}

class _KfzDetailViewState extends State<_KfzDetailView> {
  late Map<String, dynamic> _kfz;
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _termine = [];
  bool _loaded = false;
  bool _decoding = false;
  Timer? _saveTimer;

  Map<String, dynamic> get _felder => _kfz['felder'] as Map<String, dynamic>;

  @override
  void initState() {
    super.initState();
    _kfz = Map<String, dynamic>.from(widget.kfz);
    final f = _kfz['felder'];
    _kfz['felder'] = f is Map ? Map<String, dynamic>.from(f) : <String, dynamic>{};
    _load();
  }

  @override
  void dispose() { _saveTimer?.cancel(); super.dispose(); }

  Future<void> _load() async {
    final kR = await widget.apiService.listKfzZulassungKorr(widget.kfzId);
    final tR = await widget.apiService.listKfzZulassungTermine(widget.kfzId);
    if (!mounted) return;
    setState(() {
      _korr = (kR['success'] == true && kR['data'] is List)
          ? (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _termine = (tR['success'] == true && tR['data'] is List)
          ? (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList() : [];
      _loaded = true;
    });
  }

  Map<String, dynamic> _payload() => {
    'id': widget.kfzId,
    'datum': _kfz['datum'],
    'vorgangsart': _kfz['vorgangsart'] ?? '',
    'status': _kfz['status'] ?? '',
    'sachbearbeiter': _kfz['sachbearbeiter'] ?? '',
    'sachbearbeiter_tel': _kfz['sachbearbeiter_tel'] ?? '',
    'sachbearbeiter_email': _kfz['sachbearbeiter_email'] ?? '',
    'aktenzeichen': _kfz['aktenzeichen'] ?? '',
    'kennzeichen': _kfz['kennzeichen'] ?? '',
    'marke': _kfz['marke'] ?? '',
    'fin': _kfz['fin'] ?? '',
    'halter_name': _kfz['halter_name'] ?? '',
    'notiz': _kfz['notiz'] ?? '',
    'felder': _felder,
  };

  Future<void> _saveNow() async {
    await widget.apiService.saveKfzZulassung(widget.userId, _payload());
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 800), () { if (mounted) _saveNow(); });
  }

  // ---- FIN-Decoder (Proxy → NHTSA vPIC über internen Server) ----
  static const _finLabels = {
    'marke': 'Marke (D.1)',
    'd2_typ': 'Typ / Variante (D.2)',
    'd3_handelsbezeichnung': 'Modell / Handelsbez. (D.3)',
    'hsn': 'HSN (2.1)',
    'tsn': 'TSN (2.2)',
    'j_fahrzeugklasse': 'Fahrzeugklasse (J)',
    'k_eg_typgenehmigung': 'EG-Typgenehmigung (K)',
    'f1_zul_gesamtmasse': 'zul. Gesamtmasse (F.1)',
    'g_leermasse': 'Leermasse (G)',
    'p1_hubraum': 'Hubraum cm³ (P.1)',
    'p2_leistung_kw': 'Leistung kW (P.2)',
    'p3_kraftstoff': 'Kraftstoff (P.3)',
    'q_leistungsgewicht': 'Leistungsgewicht (Q)',
    's1_sitzplaetze': 'Sitzplätze (S.1)',
    't_hoechstgeschwindigkeit': 'Höchstgeschw. (T)',
    'u1_standgeraeusch': 'Standgeräusch (U.1)',
    'v7_co2': 'CO₂ (V.7)',
    'v9_emissionsklasse': 'Emissionsklasse (V.9)',
    'feld14_emissionsschluessel': 'Emissionsschlüssel (14)',
    'feld15_bereifung': 'Bereifung (15)',
    'laenge': 'Länge (18)',
    'breite': 'Breite (19)',
    'hoehe': 'Höhe (20)',
  };

  Widget _finDecodeButton() => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: SizedBox(width: double.infinity, child: OutlinedButton.icon(
      onPressed: _decoding ? null : _decodeVin,
      icon: _decoding
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.travel_explore, size: 18),
      label: Text(_decoding ? 'Frage NHTSA-Datenbank ab…' : 'FIN dekodieren — Fahrzeugdaten abrufen'),
      style: OutlinedButton.styleFrom(foregroundColor: Colors.blue.shade700, side: BorderSide(color: Colors.blue.shade300)),
    )),
  );

  Future<void> _decodeVin() async {
    final vin = (_kfz['fin']?.toString() ?? '').trim();
    if (vin.replaceAll(RegExp(r'\s'), '').length < 11) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte zuerst eine gültige FIN (17 Zeichen) im Feld eintragen.')));
      return;
    }
    setState(() => _decoding = true);
    final r = await widget.apiService.decodeKfzVin(
      vin,
      hsn: _felder['hsn']?.toString(),
      tsn: _felder['tsn']?.toString(),
    );
    if (!mounted) return;
    setState(() => _decoding = false);
    if (r['success'] != true || r['data'] is! Map) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(r['message']?.toString() ?? 'Decodierung fehlgeschlagen.')));
      return;
    }
    final data = Map<String, dynamic>.from(r['data'] as Map);
    final mapped = data['mapped'] is Map ? Map<String, dynamic>.from(data['mapped'] as Map) : <String, dynamic>{};
    final info = data['info'] is Map ? Map<String, dynamic>.from(data['info'] as Map) : <String, dynamic>{};
    final source = (info['source']?.toString() ?? '').isNotEmpty ? info['source'].toString() : 'externe Fahrzeug-Datenbank';
    if (mapped.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Keine übernehmbaren Daten gefunden (evtl. reines EU-Modell).')));
      return;
    }
    final apply = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Row(children: [Icon(Icons.directions_car, color: Colors.blue.shade700), const SizedBox(width: 8), const Expanded(child: Text('Gefundene Fahrzeugdaten'))]),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Diese Werte werden in die Felder übernommen:', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        const SizedBox(height: 8),
        ..._finLabels.entries.where((e) => (mapped[e.key]?.toString() ?? '').isNotEmpty).map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle, size: 15, color: Colors.green.shade600),
            const SizedBox(width: 8),
            SizedBox(width: 170, child: Text(e.value, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
            Expanded(child: Text(mapped[e.key].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
          ]),
        )),
        const Divider(height: 20),
        Text('Zur Info (nicht übernommen):', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
        const SizedBox(height: 4),
        ...[
          ['Modelljahr', info['model_year']],
          ['Werk', info['plant']],
          ['Zylinder', info['cylinders']],
          ['Antrieb', info['drive']],
          ['Leistung PS', info['engine_hp']],
          ['Karosserie', info['body_class']],
        ].where((e) => (e[1]?.toString() ?? '').isNotEmpty).map((e) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Text('${e[0]}: ${e[1]}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        )),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade200)),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.info_outline, size: 13, color: Colors.amber.shade800),
            const SizedBox(width: 6),
            Expanded(child: Text('Quelle: $source (nur techn. Daten). HSN/TSN & exakte dt. Schlüsselnummern sind nicht per FIN abrufbar — bitte vom Fahrzeugschein übertragen.', style: TextStyle(fontSize: 10, color: Colors.brown.shade800))),
          ]),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        FilledButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.download_done, size: 16), label: const Text('Übernehmen')),
      ],
    ));
    if (apply == true) {
      setState(() {
        mapped.forEach((k, v) {
          final s = v?.toString() ?? '';
          if (s.isEmpty) return;
          if (k == 'marke') { _kfz['marke'] = s; } else { _felder[k] = s; }
        });
      });
      await _saveNow();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fahrzeugdaten übernommen.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final kennz = _kfz['kennzeichen']?.toString() ?? '';
    final marke = _kfz['marke']?.toString() ?? '';
    final status = _kfz['status']?.toString() ?? '';
    return DefaultTabController(
      length: 6,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
          decoration: BoxDecoration(color: Colors.blue.shade50, border: Border(bottom: BorderSide(color: Colors.blue.shade200))),
          child: Row(children: [
            Icon(Icons.directions_car, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(kennz.isNotEmpty ? kennz : (marke.isNotEmpty ? marke : 'Fahrzeug'), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              Text('${marke.isNotEmpty ? '$marke · ' : ''}${_kfzStatusLabels[status] ?? status}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
            ])),
            IconButton(icon: const Icon(Icons.close, size: 20), onPressed: widget.onClose, tooltip: 'Schließen'),
          ]),
        ),
        TabBar(
          labelColor: Colors.blue.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.blue.shade700,
          isScrollable: true,
          tabs: [
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.info_outline, size: 14), SizedBox(width: 4), Text('Details')])),
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.folder_open, size: 14), SizedBox(width: 4), Text('Dokumente')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.mail_outline, size: 14), const SizedBox(width: 4), Text('Korrespondenz (${_korr.length})')])),
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.event, size: 14), const SizedBox(width: 4), Text('Termine (${_termine.length})')])),
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.menu_book, size: 14), SizedBox(width: 4), Text('Brief groß · ZB II')])),
            const Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.article, size: 14), SizedBox(width: 4), Text('Brief klein · ZB I')])),
          ],
        ),
        Expanded(child: _loaded ? TabBarView(children: [
          _buildDetailsTab(),
          Padding(
            padding: const EdgeInsets.all(12),
            child: KorrAttachmentsWidget(
              apiService: widget.apiService,
              modul: 'kfz_zulassung',
              korrespondenzId: widget.kfzId,
            ),
          ),
          _buildKorrTab(),
          _buildTerminTab(),
          _buildZb2Tab(),
          _buildZb1Tab(),
        ]) : const Center(child: CircularProgressIndicator())),
      ]),
    );
  }

  // ---- Feld-Helfer (mit Auto-Save) ----
  Widget _f(String label, Map<String, dynamic> map, String key, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: TextEditingController(text: map[key]?.toString() ?? ''),
        maxLines: maxLines,
        onChanged: (v) { map[key] = v; _scheduleSave(); },
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          prefixIcon: Icon(icon, size: 18), isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        style: const TextStyle(fontSize: 13),
      ),
    );
  }

  Widget _dd(String label, Map<String, dynamic> map, String key, IconData icon, Map<String, String> options) {
    final current = map[key]?.toString() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        child: DropdownButtonHideUnderline(child: DropdownButton<String>(
          value: options.containsKey(current) ? current : null,
          isDense: true, isExpanded: true,
          items: options.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
          onChanged: (v) { setState(() => map[key] = v ?? ''); _saveNow(); },
        )),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(top: 6, bottom: 8),
    child: Row(children: [
      Container(width: 3, height: 14, color: Colors.blue.shade400),
      const SizedBox(width: 6),
      Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
    ]),
  );

  // ---- DETAILS (Stammdaten Vorgang, editierbar) ----
  Widget _buildDetailsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _dd('Vorgangsart', _kfz, 'vorgangsart', Icons.category, _kfzVorgangsarten),
        _dd('Status', _kfz, 'status', Icons.flag, _kfzStatusLabels),
        Padding(padding: const EdgeInsets.only(bottom: 10), child: TextField(
          controller: TextEditingController(text: _kfz['datum']?.toString() ?? ''),
          readOnly: true,
          decoration: InputDecoration(labelText: 'Vorgangsdatum', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          style: const TextStyle(fontSize: 13),
          onTap: () async {
            final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
            if (p != null) { setState(() => _kfz['datum'] = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'); _saveNow(); }
          },
        )),
        const Divider(height: 20),
        _f('Kennzeichen', _kfz, 'kennzeichen', Icons.confirmation_number, hint: 'z.B. NU-AB 1234'),
        _f('Fahrzeug / Marke', _kfz, 'marke', Icons.directions_car, hint: 'z.B. VW Golf 7 1.6 TDI'),
        _f('FIN (Fahrzeug-Ident-Nr.)', _kfz, 'fin', Icons.qr_code, hint: '17-stellig'),
        _finDecodeButton(),
        _f('Halter (Name)', _kfz, 'halter_name', Icons.person_pin, hint: ''),
        _f('Anschrift Halter', _felder, 'halter_anschrift', Icons.location_on, hint: 'Straße, PLZ Ort'),
        const Divider(height: 20),
        _f('Sachbearbeiter/in', _kfz, 'sachbearbeiter', Icons.person),
        _f('Telefon', _kfz, 'sachbearbeiter_tel', Icons.phone),
        _f('E-Mail', _kfz, 'sachbearbeiter_email', Icons.email),
        _f('Aktenzeichen', _kfz, 'aktenzeichen', Icons.tag),
        _f('Notiz', _kfz, 'notiz', Icons.note, maxLines: 3),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.checklist, size: 16, color: Colors.amber.shade800),
              const SizedBox(width: 6),
              Text('Für die Zulassung benötigte Unterlagen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
            ]),
            const SizedBox(height: 6),
            ...[
              'Personalausweis / Reisepass des Halters',
              'eVB-Nummer (elektr. Versicherungsbestätigung)',
              'SEPA-Lastschriftmandat (KFZ-Steuer)',
              'Zulassungsbescheinigung Teil II (Fahrzeugbrief)',
              'Zulassungsbescheinigung Teil I (Fahrzeugschein) — bei Gebrauchtwagen',
              'HU-Bericht (TÜV) — bei Gebrauchtwagen',
              'CoC-Bescheinigung — bei Neufahrzeug',
              'ggf. Vollmacht + Ausweis der bevollmächtigten Person',
            ].map((t) => Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.chevron_right, size: 14, color: Colors.amber.shade700),
                Expanded(child: Text(t, style: TextStyle(fontSize: 11, color: Colors.brown.shade800))),
              ]),
            )),
          ]),
        ),
      ]),
    );
  }

  // ---- BRIEF GROSS · ZB Teil II (Fahrzeugbrief) ----
  Widget _buildZb2Tab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.menu_book, size: 16, color: Colors.indigo.shade700), const SizedBox(width: 6),
              Text('Zulassungsbescheinigung Teil II', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))]),
            Text('„großer Brief" — Fahrzeugbrief (Eigentumsnachweis, bleibt zu Hause)', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600)),
          ]),
        ),
        const SizedBox(height: 12),
        _f('Nummer der ZB Teil II', _felder, 'zb2_nummer', Icons.pin, hint: 'oben rechts auf dem Brief'),
        _f('Ausstellungsdatum', _felder, 'zb2_ausstellungsdatum', Icons.event, hint: 'TT.MM.JJJJ'),
        _f('Ausstellende Behörde', _felder, 'ausstellende_behoerde', Icons.account_balance, hint: 'z.B. Landratsamt Neu-Ulm'),
        _sectionLabel('Halter & Vorbesitzer'),
        _f('Halter (aktuell)', _kfz, 'halter_name', Icons.person_pin),
        _f('Anschrift Halter', _felder, 'halter_anschrift', Icons.location_on),
        _f('Anzahl bisheriger Halter', _felder, 'anzahl_vorhalter', Icons.people, hint: 'Zahl'),
        _f('Letzter Vorbesitzer (Name/Anschrift)', _felder, 'vorbesitzer', Icons.history, maxLines: 2),
        _sectionLabel('Fahrzeug-Identität (D · E · J · K)'),
        _f('D.1 Marke (Hersteller)', _kfz, 'marke', Icons.factory),
        _f('D.2 Typ / Variante / Version', _felder, 'd2_typ', Icons.tune),
        _f('D.3 Handelsbezeichnung', _felder, 'd3_handelsbezeichnung', Icons.label),
        _f('E FIN (Fahrzeug-Ident-Nr.)', _kfz, 'fin', Icons.qr_code, hint: '17-stellig'),
        _f('J Fahrzeugklasse / Aufbau', _felder, 'j_fahrzeugklasse', Icons.category),
        _f('K EG-Typgenehmigungsnr.', _felder, 'k_eg_typgenehmigung', Icons.verified),
        _f('B Datum der Erstzulassung', _felder, 'b_erstzulassung', Icons.calendar_today, hint: 'TT.MM.JJJJ'),
      ]),
    );
  }

  // ---- BRIEF KLEIN · ZB Teil I (Fahrzeugschein) — komplette EU-Codes ----
  Widget _buildZb1Tab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: double.infinity, padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.article, size: 16, color: Colors.teal.shade700), const SizedBox(width: 6),
              Text('Zulassungsbescheinigung Teil I', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800))]),
            Text('„kleiner Brief" — Fahrzeugschein (im Fahrzeug mitzuführen)', style: TextStyle(fontSize: 10, color: Colors.teal.shade600)),
          ]),
        ),
        const SizedBox(height: 12),
        _f('A Kennzeichen', _kfz, 'kennzeichen', Icons.confirmation_number),
        _f('B Datum der Erstzulassung', _felder, 'b_erstzulassung', Icons.calendar_today, hint: 'TT.MM.JJJJ'),
        _f('I Datum Zulassung auf Halter', _felder, 'i_zulassung_halter', Icons.event_available, hint: 'TT.MM.JJJJ'),
        _sectionLabel('Halter (C)'),
        _f('C.1 Halter (Name)', _kfz, 'halter_name', Icons.person_pin),
        _f('C.1.3 Anschrift', _felder, 'halter_anschrift', Icons.location_on),
        _sectionLabel('Fahrzeug (D · E)'),
        _f('D.1 Marke', _kfz, 'marke', Icons.factory),
        _f('D.2 Typ / Variante / Version', _felder, 'd2_typ', Icons.tune),
        _f('D.3 Handelsbezeichnung', _felder, 'd3_handelsbezeichnung', Icons.label),
        _f('E Fahrzeug-Identifizierungsnr.', _kfz, 'fin', Icons.qr_code, hint: '17-stellig'),
        _finDecodeButton(),
        _sectionLabel('Schlüsselnummern (zu 2)'),
        Row(children: [
          Expanded(child: _f('zu 2.1 HSN', _felder, 'hsn', Icons.vpn_key, hint: 'Herstellerschlüssel')),
          const SizedBox(width: 8),
          Expanded(child: _f('zu 2.2 TSN', _felder, 'tsn', Icons.vpn_key, hint: 'Typschlüssel')),
        ]),
        _sectionLabel('Massen (F · G)'),
        _f('F.1 techn. zul. Gesamtmasse (kg)', _felder, 'f1_zul_gesamtmasse', Icons.scale),
        _f('G Masse in Betrieb / Leermasse (kg)', _felder, 'g_leermasse', Icons.scale_outlined),
        _sectionLabel('Klasse & Genehmigung (J · K)'),
        _f('J Fahrzeugklasse', _felder, 'j_fahrzeugklasse', Icons.category),
        _f('J Art des Aufbaus', _felder, 'aufbau', Icons.directions_car_filled),
        _f('K EG-Typgenehmigungsnr.', _felder, 'k_eg_typgenehmigung', Icons.verified),
        _sectionLabel('Motor & Antrieb (P · Q)'),
        Row(children: [
          Expanded(child: _f('P.1 Hubraum (cm³)', _felder, 'p1_hubraum', Icons.settings)),
          const SizedBox(width: 8),
          Expanded(child: _f('P.2 Nennleistung (kW)', _felder, 'p2_leistung_kw', Icons.bolt)),
        ]),
        _f('P.3 Kraftstoff / Energiequelle', _felder, 'p3_kraftstoff', Icons.local_gas_station, hint: 'z.B. Diesel, Benzin, Elektro'),
        _f('Q Leistungsgewicht (kW/kg)', _felder, 'q_leistungsgewicht', Icons.speed, hint: 'nur Krafträder'),
        _sectionLabel('Plätze & Fahrleistung (S · T · U)'),
        Row(children: [
          Expanded(child: _f('S.1 Sitzplätze', _felder, 's1_sitzplaetze', Icons.event_seat)),
          const SizedBox(width: 8),
          Expanded(child: _f('T Höchstgeschw. (km/h)', _felder, 't_hoechstgeschwindigkeit', Icons.speed)),
        ]),
        _f('U.1 Standgeräusch (dB(A))', _felder, 'u1_standgeraeusch', Icons.volume_up),
        _sectionLabel('Emissionen (V · 14)'),
        Row(children: [
          Expanded(child: _f('V.7 CO₂ (g/km)', _felder, 'v7_co2', Icons.cloud)),
          const SizedBox(width: 8),
          Expanded(child: _f('V.9 Emissionsklasse', _felder, 'v9_emissionsklasse', Icons.eco, hint: 'z.B. Euro 6d')),
        ]),
        _f('14 Emissionsschlüssel / Umweltplakette', _felder, 'feld14_emissionsschluessel', Icons.local_parking, hint: 'z.B. grün'),
        _sectionLabel('Bereifung & Maße (15 · 18–20)'),
        _f('15 Bereifung (15.1 / 15.2 / 15.3)', _felder, 'feld15_bereifung', Icons.tire_repair, maxLines: 2),
        Row(children: [
          Expanded(child: _f('18 Länge (mm)', _felder, 'laenge', Icons.straighten)),
          const SizedBox(width: 8),
          Expanded(child: _f('19 Breite (mm)', _felder, 'breite', Icons.straighten)),
          const SizedBox(width: 8),
          Expanded(child: _f('20 Höhe (mm)', _felder, 'hoehe', Icons.height)),
        ]),
        _sectionLabel('HU & Bemerkungen (22)'),
        _f('Nächste HU/TÜV (MM/JJJJ)', _felder, 'naechste_hu', Icons.build),
        _f('22 Bemerkungen und Ausnahmen', _felder, 'bemerkungen', Icons.notes, maxLines: 2),
        _sectionLabel('Versicherung & Steuer (für Zulassung)'),
        _f('Versicherer', _felder, 'versicherung', Icons.shield, hint: 'z.B. HUK-COBURG'),
        _f('eVB-Nummer', _felder, 'evb_nr', Icons.numbers, hint: '7-stellig'),
        _f('Versicherungsscheinnummer', _felder, 'versicherungsscheinnummer', Icons.description),
        _f('SEPA-Mandat / IBAN (KFZ-Steuer)', _felder, 'sepa_iban', Icons.account_balance),
        _f('KFZ-Steuer €/Jahr', _felder, 'kfz_steuer', Icons.euro, hint: 'z.B. 120'),
      ]),
    );
  }

  // ---- KORRESPONDENZ ----
  Widget _buildKorrTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
        Icon(Icons.mail_outline, size: 18, color: Colors.blue.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Korrespondenz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700))),
        ElevatedButton.icon(
          onPressed: _addKorr,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
        ),
      ])),
      Expanded(child: _korr.isEmpty
          ? Center(child: Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
          : ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _korr.length,
              itemBuilder: (_, i) {
                final k = _korr[i];
                final kid = int.tryParse(k['id']?.toString() ?? '');
                final isEin = (k['richtung']?.toString() ?? 'eingang') == 'eingang';
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.green.shade600 : Colors.blue.shade600, size: 22),
                        const SizedBox(width: 8),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(k['betreff']?.toString() ?? '(ohne Betreff)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                          Text('${k['datum'] ?? ''}  ·  ${isEin ? 'Eingang' : 'Ausgang'}  ·  ${k['methode'] ?? '–'}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          if ((k['notiz']?.toString() ?? '').isNotEmpty)
                            Padding(padding: const EdgeInsets.only(top: 2), child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 11))),
                        ])),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          onPressed: () async { if (kid != null) { await widget.apiService.deleteKfzZulassungKorr(kid); await _load(); } },
                        ),
                      ]),
                      if (kid != null) Padding(
                        padding: const EdgeInsets.only(top: 6, left: 30),
                        child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'kfz_zulassung_korr', korrespondenzId: kid),
                      ),
                    ]),
                  ),
                );
              },
            )),
    ]);
  }

  Future<void> _addKorr() async {
    String richtung = 'eingang';
    String methode = 'post';
    bool submitting = false;
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Korrespondenz'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_received, size: 14, color: richtung == 'eingang' ? Colors.white : Colors.green.shade600),
              const SizedBox(width: 4), Text('Eingang', style: TextStyle(fontSize: 12, color: richtung == 'eingang' ? Colors.white : Colors.black87)),
            ]), selected: richtung == 'eingang', selectedColor: Colors.green.shade600, onSelected: (_) => setD(() => richtung = 'eingang'))),
            const SizedBox(width: 8),
            Expanded(child: ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.call_made, size: 14, color: richtung == 'ausgang' ? Colors.white : Colors.blue.shade600),
              const SizedBox(width: 4), Text('Ausgang', style: TextStyle(fontSize: 12, color: richtung == 'ausgang' ? Colors.white : Colors.black87)),
            ]), selected: richtung == 'ausgang', selectedColor: Colors.blue.shade600, onSelected: (_) => setD(() => richtung = 'ausgang'))),
          ]),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: methode,
            decoration: InputDecoration(labelText: 'Methode', prefixIcon: const Icon(Icons.send, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: const [
              DropdownMenuItem(value: 'post', child: Text('Post')),
              DropdownMenuItem(value: 'online', child: Text('Online (E-Mail / Portal / i-Kfz)')),
              DropdownMenuItem(value: 'fax', child: Text('Fax')),
              DropdownMenuItem(value: 'persoenlich', child: Text('Persönlich')),
            ],
            onChanged: (v) => setD(() => methode = v ?? 'post'),
          ),
          const SizedBox(height: 8),
          TextField(controller: datumC, readOnly: true,
            decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async {
              final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
            }),
          const SizedBox(height: 8),
          TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', prefixIcon: const Icon(Icons.title, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              if (datumC.text.trim().isEmpty) return;
              setD(() => submitting = true);
              await widget.apiService.saveKfzZulassungKorr(widget.kfzId, widget.userId, {
                'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(),
                'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }

  // ---- TERMINE ----
  Widget _buildTerminTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: Row(children: [
        Icon(Icons.event, size: 18, color: Colors.blue.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Termine', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700))),
        ElevatedButton.icon(
          onPressed: _addTermin,
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10)),
        ),
      ])),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
          child: Row(children: [
            Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text('Termine werden automatisch in die Terminverwaltung übernommen (mit Kennzeichen + Sachbearbeiter).', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
          ]),
        ),
      ),
      Expanded(child: _termine.isEmpty
          ? Center(child: Text('Keine Termine', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              itemCount: _termine.length,
              itemBuilder: (_, i) {
                final t = _termine[i];
                final hasGlobal = (t['termin_id']?.toString() ?? '').isNotEmpty && t['termin_id'] != null;
                return Card(
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    dense: true,
                    leading: Icon(Icons.event, color: Colors.blue.shade700, size: 22),
                    title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? '  ·  ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((t['ort']?.toString() ?? '').isNotEmpty) Text('Ort: ${t['ort']}', style: const TextStyle(fontSize: 11)),
                      if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: const TextStyle(fontSize: 11)),
                      if (hasGlobal) Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Icon(Icons.check_circle, size: 10, color: Colors.green.shade600),
                          const SizedBox(width: 3),
                          Text('In Terminverwaltung übernommen', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ]),
                    trailing: IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                      onPressed: () async {
                        final id = int.tryParse(t['id']?.toString() ?? '');
                        if (id != null) { await widget.apiService.deleteKfzZulassungTermin(id); await _load(); }
                      },
                    ),
                  ),
                );
              },
            )),
    ]);
  }

  Future<void> _addTermin() async {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final ortC = TextEditingController(text: 'KFZ-Zulassungsstelle, Landratsamt Neu-Ulm, Kantstraße 8, 89231 Neu-Ulm');
    final notizC = TextEditingController();
    bool submitting = false;
    if (!mounted) return;
    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Neuer Termin'),
        content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: TextField(controller: datumC, readOnly: true,
              decoration: InputDecoration(labelText: 'Datum *', prefixIcon: const Icon(Icons.calendar_today, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime(2040), locale: const Locale('de'));
                if (p != null) datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
              })),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: uhrzeitC, readOnly: true,
              decoration: InputDecoration(labelText: 'Uhrzeit *', prefixIcon: const Icon(Icons.access_time, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              onTap: () async {
                final t = await showTimePicker(context: ctx2, initialTime: const TimeOfDay(hour: 9, minute: 0));
                if (t != null) uhrzeitC.text = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
              })),
          ]),
          const SizedBox(height: 8),
          TextField(controller: ortC, maxLines: 2, decoration: InputDecoration(labelText: 'Ort', prefixIcon: const Icon(Icons.place, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 8),
          TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz / Anlass', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text('Termin wird automatisch in der Terminverwaltung erstellt mit Kennzeichen & Sachbearbeiter aus diesem Vorgang.', style: TextStyle(fontSize: 10, color: Colors.blue.shade900))),
            ]),
          ),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              if (datumC.text.trim().isEmpty || uhrzeitC.text.trim().isEmpty) return;
              setD(() => submitting = true);
              await widget.apiService.saveKfzZulassungTermin(widget.kfzId, widget.userId, {
                'datum': datumC.text.trim(), 'uhrzeit': uhrzeitC.text.trim(),
                'ort': ortC.text.trim(), 'notiz': notizC.text.trim(),
              });
              if (ctx.mounted) Navigator.pop(ctx, true);
            },
            child: submitting ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await _load();
  }
}
