import 'package:flutter/material.dart';
import '../services/api_service.dart';

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
  static const type = 'landratsamt';
  Map<String, Map<String, dynamic>> _dbData = {};
  bool _loaded = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadFromDB();
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
    setState(() => _saving = true);
    await widget.apiService.saveLandratsamtData(widget.userId, _dbData);
    if (mounted) setState(() => _saving = false);
  }

  Map<String, dynamic> _bereich(String key) {
    _dbData[key] ??= {};
    return _dbData[key]!;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return DefaultTabController(
      length: 6,
      child: Column(children: [
        TabBar(
          labelColor: Colors.brown.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.brown.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Amt'),
            Tab(icon: Icon(Icons.directions_car, size: 16), text: 'KFZ'),
            Tab(icon: Icon(Icons.badge, size: 16), text: 'Führerschein'),
            Tab(icon: Icon(Icons.home_work, size: 16), text: 'Bau & Wohnen'),
            Tab(icon: Icon(Icons.eco, size: 16), text: 'Umwelt & Natur'),
            Tab(icon: Icon(Icons.more_horiz, size: 16), text: 'Sonstiges'),
          ],
        ),
        Expanded(
          child: TabBarView(children: [
            _buildAmtTab(),
            _buildKfzTab(),
            _buildFuehrerscheinTab(),
            _buildBauTab(),
            _buildUmweltTab(),
            _buildSonstigesTab(),
          ]),
        ),
        _buildSaveFooter(),
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
          tabs: const [
            Tab(icon: Icon(Icons.badge, size: 14), text: 'Führerschein'),
            Tab(icon: Icon(Icons.calendar_month, size: 14), text: 'Termine'),
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
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
                  onPressed: () { _saveToDB(); setState(() => _fsEditing = false); },
                  icon: const Icon(Icons.save, size: 16),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
                )),
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
        onChanged: (v) => map[key] = v,
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
            onChanged: (v) => setState(() => map[key] = v ?? ''),
          ),
        ),
      ),
    );
  }

  Widget _buildSaveFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Colors.grey.shade300))),
      child: Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton.icon(
          onPressed: _saving ? null : () => _saveToDB(),
          icon: _saving
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.brown, foregroundColor: Colors.white),
        ),
      ),
    );
  }
}
