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
            Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (_bereich('kfz')['kennzeichen']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.directions_car, size: 16), const SizedBox(width: 4), const Text('KFZ')])),
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
            _buildKfzTab(),
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
  Widget _buildKfzTab() {
    final kfz = _bereich('kfz');
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.directions_car, 'KFZ-Zulassungsstelle', Colors.blue),
        const SizedBox(height: 4),
        Text('Landratsamt Neu-Ulm · Kantstraße 8 · 89231 Neu-Ulm', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 16),
        _field('Sachbearbeiter/in', kfz, 'sachbearbeiter', Icons.person, hint: 'Name'),
        _field('Aktenzeichen', kfz, 'aktenzeichen', Icons.tag),
        const Divider(height: 20),
        _field('Kennzeichen', kfz, 'kennzeichen', Icons.confirmation_number, hint: 'z.B. NU-AB 1234'),
        _field('Fahrzeug', kfz, 'fahrzeug', Icons.directions_car, hint: 'z.B. VW Golf 7 1.6 TDI'),
        _field('FIN (Fahrgestell-Nr.)', kfz, 'fin', Icons.qr_code, hint: '17-stellig'),
        _field('Erstzulassung', kfz, 'erstzulassung', Icons.calendar_today, hint: 'TT.MM.JJJJ'),
        _field('Nächste HU/TÜV', kfz, 'naechste_hu', Icons.build, hint: 'MM/JJJJ'),
        _field('Versicherung', kfz, 'versicherung', Icons.shield, hint: 'z.B. HUK-COBURG'),
        _field('Versicherungsscheinnummer', kfz, 'evb_nr', Icons.tag, hint: 'eVB-Nr.'),
        _field('KFZ-Steuer €/Jahr', kfz, 'kfz_steuer', Icons.euro, hint: 'z.B. 120'),
        _dropDown('Status', kfz, 'status', Icons.check_circle, {'aktiv': 'Zugelassen', 'abgemeldet': 'Abgemeldet', 'stillgelegt': 'Stillgelegt', 'export': 'Exportiert'}),
        _field('Notizen', kfz, 'notizen', Icons.note, hint: '', maxLines: 3),
      ]),
    );
  }

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

const _landratsamtVorfallArten = [
  'Verfahrensbetreuung (Anordnung Betreuungsgericht)',
  'Betreuungsanregung',
  'Sozialbericht / Stellungnahme an Gericht',
  'Hausbesuch / Ermittlung',
  'Beratung Betroffene/r',
  'Beratung Angehörige',
  'Begleitung Anhörung Betreuungsgericht',
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
