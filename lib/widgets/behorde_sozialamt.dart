import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BehordeSozialamtContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final ApiService? apiService;

  const BehordeSozialamtContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    this.apiService,
  });

  static const type = 'sozialamt';

  @override
  State<BehordeSozialamtContent> createState() => _BehordeSozialamtContentState();
}

class _BehordeSozialamtContentState extends State<BehordeSozialamtContent> {
  static const type = 'sozialamt';

  Map<String, dynamic> get _data {
    final d = widget.getData(type);
    if (d.isEmpty && !widget.isLoading(type)) widget.loadData(type);
    return d;
  }

  void _save() => widget.saveData(type, _data);

  @override
  Widget build(BuildContext context) {
    if (widget.isLoading(type)) return const Center(child: CircularProgressIndicator());
    final data = _data;

    return DefaultTabController(
      length: 5,
      child: Column(children: [
        TabBar(
          labelColor: Colors.indigo.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.indigo.shade700,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Zuständige Behörde'),
            Tab(icon: Icon(Icons.person, size: 16), text: 'Mitarbeiter/in'),
            Tab(icon: Icon(Icons.description, size: 16), text: 'Anträge'),
            Tab(icon: Icon(Icons.check_circle, size: 16), text: 'Bewilligung'),
            Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildBehoerdeTab(data),
          _buildMitarbeiterTab(data),
          _buildAntraegeTab(data),
          _buildBewilligungTab(data),
          _buildKorrespondenzTab(data),
        ])),
      ]),
    );
  }

  // ============ TAB 1: ZUSTÄNDIGE BEHÖRDE ============
  Widget _buildBehoerdeTab(Map<String, dynamic> data) {
    final selected = data['behoerde_name']?.toString() ?? '';
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Zuständiges Sozialamt wählen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 12),
        ..._sozialamtListe.map((s) {
          final isSel = selected == s['name'];
          return InkWell(
            onTap: () {
              setState(() {
                data['behoerde_name'] = s['name'];
                data['behoerde_adresse'] = s['adresse'];
                data['behoerde_plz_ort'] = s['plz_ort'];
                data['behoerde_telefon'] = s['telefon'];
                data['behoerde_oeffnungszeiten'] = s['oeffnungszeiten'];
              });
              _save();
            },
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSel ? Colors.indigo.shade50 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isSel ? Colors.indigo.shade400 : Colors.grey.shade300, width: isSel ? 2 : 1),
              ),
              child: Row(children: [
                Icon(isSel ? Icons.check_circle : Icons.account_balance, size: 20, color: isSel ? Colors.indigo.shade700 : Colors.grey.shade500),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSel ? Colors.indigo.shade900 : Colors.black87)),
                  Text('${s['adresse']}, ${s['plz_ort']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  Text(s['zustaendigkeit']!, style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontStyle: FontStyle.italic)),
                ])),
              ]),
            ),
          );
        }),
        if (selected.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kontakt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
              const SizedBox(height: 6),
              _infoRow(Icons.location_on, '${data['behoerde_adresse'] ?? ''}, ${data['behoerde_plz_ort'] ?? ''}'),
              _infoRow(Icons.phone, data['behoerde_telefon'] ?? ''),
              _infoRow(Icons.access_time, data['behoerde_oeffnungszeiten'] ?? ''),
            ]),
          ),
        ],
        const SizedBox(height: 12),
        _textField(data, 'kundennummer', 'Kundennummer / Aktenzeichen', Icons.tag),
        _textField(data, 'notizen', 'Notizen', Icons.note, maxLines: 3),
        _saveButton(),
      ]),
    );
  }

  // ============ TAB 2: MITARBEITER/IN ============
  Widget _buildMitarbeiterTab(Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Zuständige/r Sachbearbeiter/in', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 12),
        _textField(data, 'sachbearbeiter_anrede', 'Anrede', Icons.person, hint: 'Frau / Herr'),
        _textField(data, 'sachbearbeiter_name', 'Name', Icons.badge),
        _textField(data, 'sachbearbeiter_tel', 'Telefon (direkt)', Icons.phone),
        _textField(data, 'sachbearbeiter_email', 'E-Mail', Icons.email),
        _textField(data, 'sachbearbeiter_zimmer', 'Zimmer / Raum', Icons.room),
        _textField(data, 'sachbearbeiter_sprechzeiten', 'Sprechzeiten', Icons.access_time),
        _textField(data, 'sachbearbeiter_notizen', 'Notizen', Icons.note, maxLines: 3),
        _saveButton(),
      ]),
    );
  }

  // ============ TAB 3: ANTRÄGE ============
  Widget _buildAntraegeTab(Map<String, dynamic> data) {
    final antraege = List<Map<String, dynamic>>.from(data['antraege'] ?? []);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.description, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Anträge (${antraege.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
          ElevatedButton.icon(
            onPressed: () => _showAntragDialog(data, antraege),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: antraege.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.description, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Anträge', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: antraege.length,
                itemBuilder: (_, i) {
                  final a = antraege[i];
                  return Card(child: ListTile(
                    leading: Icon(Icons.description, color: Colors.indigo.shade600),
                    title: Text(a['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('${a['datum'] ?? ''} • ${a['methode'] ?? ''}\n${a['status'] ?? ''}', style: const TextStyle(fontSize: 11)),
                    isThreeLine: true,
                    onTap: () => _showAntragDialog(data, antraege, editIndex: i),
                    trailing: IconButton(
                      icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                      onPressed: () { setState(() => antraege.removeAt(i)); data['antraege'] = antraege; _save(); },
                    ),
                  ));
                },
              ),
      ),
    ]);
  }

  // ============ TAB 4: BEWILLIGUNG ============
  Widget _buildBewilligungTab(Map<String, dynamic> data) {
    final bewilligungen = List<Map<String, dynamic>>.from(data['bewilligungen'] ?? []);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.check_circle, size: 20, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Bewilligungen (${bewilligungen.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
          ElevatedButton.icon(
            onPressed: () => _showBewilligungDialog(data, bewilligungen),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neue Bewilligung', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: bewilligungen.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Bewilligungen', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: bewilligungen.length,
                itemBuilder: (_, i) {
                  final b = bewilligungen[i];
                  final bewilligt = b['bewilligt'] == true || b['bewilligt'] == 'true';
                  return Card(child: ListTile(
                    leading: Icon(bewilligt ? Icons.check_circle : Icons.cancel, color: bewilligt ? Colors.green : Colors.red),
                    title: Text(b['leistung']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('${bewilligt ? 'Bewilligt' : 'Abgelehnt'} • ${b['datum'] ?? ''}\n${b['betrag'] != null ? '${b['betrag']} €/Monat' : ''}${(b['notiz']?.toString() ?? '').isNotEmpty ? ' • ${b['notiz']}' : ''}', style: const TextStyle(fontSize: 11)),
                    isThreeLine: true,
                    trailing: IconButton(
                      icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                      onPressed: () { setState(() => bewilligungen.removeAt(i)); data['bewilligungen'] = bewilligungen; _save(); },
                    ),
                  ));
                },
              ),
      ),
    ]);
  }

  // ============ TAB 5: KORRESPONDENZ ============
  Widget _buildKorrespondenzTab(Map<String, dynamic> data) {
    final korr = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: Text('${korr.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          FilledButton.icon(
            icon: const Icon(Icons.call_received, size: 14),
            label: const Text('Eingang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
            onPressed: () => _showKorrDialog(data, korr, 'eingang'),
          ),
          const SizedBox(width: 6),
          FilledButton.icon(
            icon: const Icon(Icons.call_made, size: 14),
            label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
            onPressed: () => _showKorrDialog(data, korr, 'ausgang'),
          ),
        ]),
      ),
      Expanded(
        child: korr.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 6),
                Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: korr.length,
                itemBuilder: (_, i) {
                  final k = korr[i];
                  final isEin = k['richtung'] == 'eingang';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
                    child: Row(children: [
                      Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                        Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ])),
                      IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () {
                        setState(() => korr.removeAt(i)); data['korrespondenz'] = korr; _save();
                      }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ============ DIALOGS ============
  void _showAntragDialog(Map<String, dynamic> data, List<Map<String, dynamic>> antraege, {int? editIndex}) {
    final existing = editIndex != null ? antraege[editIndex] : null;
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    String leistung = existing?['leistung']?.toString() ?? '';
    String methode = existing?['methode']?.toString() ?? '';
    String status = existing?['status']?.toString() ?? 'eingereicht';

    final leistungen = ['Grundsicherung im Alter', 'Grundsicherung bei Erwerbsminderung', 'Hilfe zum Lebensunterhalt', 'Eingliederungshilfe', 'Hilfe zur Pflege', 'Bildung und Teilhabe', 'Bestattungskosten', 'Blindengeld', 'Sonstige'];
    final methoden = [('online', 'Online'), ('persoenlich', 'Persönlich'), ('postalisch', 'Postalisch'), ('email', 'Per E-Mail')];
    final statusList = [('eingereicht', 'Eingereicht'), ('in_bearbeitung', 'In Bearbeitung'), ('bewilligt', 'Bewilligt'), ('abgelehnt', 'Abgelehnt'), ('widerspruch', 'Widerspruch')];

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: Text(editIndex != null ? 'Antrag bearbeiten' : 'Neuer Antrag'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(value: leistungen.contains(leistung) ? leistung : null, decoration: InputDecoration(labelText: 'Leistung *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: leistungen.map((l) => DropdownMenuItem(value: l, child: Text(l, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => leistung = v ?? '')),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
          final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
          if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: methoden.map((m) => ChoiceChip(label: Text(m.$2, style: TextStyle(fontSize: 11, color: methode == m.$1 ? Colors.white : Colors.black87)), selected: methode == m.$1, selectedColor: Colors.indigo, onSelected: (_) => setD(() => methode = m.$1))).toList()),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: statusList.map((s) => ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : Colors.black87)), selected: status == s.$1, selectedColor: Colors.teal, onSelected: (_) => setD(() => status = s.$1))).toList()),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (leistung.isEmpty || datumC.text.isEmpty) return;
          final entry = {'leistung': leistung, 'datum': datumC.text, 'methode': methode, 'status': status, 'notiz': notizC.text};
          setState(() { if (editIndex != null) antraege[editIndex] = entry; else antraege.insert(0, entry); data['antraege'] = antraege; });
          _save(); Navigator.pop(ctx);
        }, child: Text(editIndex != null ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  void _showBewilligungDialog(Map<String, dynamic> data, List<Map<String, dynamic>> bewilligungen) {
    final datumC = TextEditingController();
    final betragC = TextEditingController();
    final notizC = TextEditingController();
    String leistung = '';
    bool bewilligt = true;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      title: const Text('Neue Bewilligung'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: TextEditingController(text: leistung), onChanged: (v) => leistung = v, decoration: InputDecoration(labelText: 'Leistung *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Bescheid-Datum', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
          final p = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
          if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }),
        const SizedBox(height: 8),
        TextField(controller: betragC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Betrag €/Monat', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 8),
        Row(children: [
          ChoiceChip(label: const Text('Bewilligt', style: TextStyle(fontSize: 11)), selected: bewilligt, selectedColor: Colors.green, onSelected: (_) => setD(() => bewilligt = true)),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Abgelehnt', style: TextStyle(fontSize: 11)), selected: !bewilligt, selectedColor: Colors.red, onSelected: (_) => setD(() => bewilligt = false)),
        ]),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          if (leistung.isEmpty) return;
          setState(() { bewilligungen.insert(0, {'leistung': leistung, 'datum': datumC.text, 'betrag': betragC.text, 'bewilligt': bewilligt, 'notiz': notizC.text}); data['bewilligungen'] = bewilligungen; });
          _save(); Navigator.pop(ctx);
        }, child: const Text('Hinzufügen')),
      ],
    )));
  }

  void _showKorrDialog(Map<String, dynamic> data, List<Map<String, dynamic>> korr, String richtung) {
    final betreffC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Text(richtung == 'eingang' ? 'Eingang erfassen' : 'Ausgang erfassen'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () {
          setState(() { korr.insert(0, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()}); data['korrespondenz'] = korr; });
          _save(); Navigator.pop(ctx);
        }, child: const Text('Speichern')),
      ],
    ));
  }

  // ============ HELPERS ============
  static const _sozialamtListe = [
    {'name': 'Landratsamt Neu-Ulm — Soziale Leistungen', 'adresse': 'Albrecht-Berblinger-Straße 6', 'plz_ort': '89231 Neu-Ulm', 'telefon': '0731 7040-52020', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Blindengeld'},
    {'name': 'Landratsamt Neu-Ulm — Außenstelle Illertissen', 'adresse': 'Ulmer Straße 20', 'plz_ort': '89257 Illertissen', 'telefon': '07303 9006-0', 'oeffnungszeiten': 'Mo–Mi 07:30–12:30, Do 07:30–17:30, Fr 07:30–12:30', 'zustaendigkeit': 'Südlicher Landkreis'},
    {'name': 'Stadt Ulm — Soziales', 'adresse': 'Zeitblomstraße 28', 'plz_ort': '89073 Ulm', 'telefon': '0731 161-5101', 'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Di+Do 14:00–16:00', 'zustaendigkeit': 'Sozialhilfe, Grundsicherung, Wohngeld, Bildung+Teilhabe'},
  ];

  Widget _textField(Map<String, dynamic> data, String key, String label, IconData icon, {String hint = '', int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: TextEditingController(text: data[key]?.toString() ?? ''),
        maxLines: maxLines,
        onChanged: (v) => data[key] = v,
        decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: Icon(icon, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        style: const TextStyle(fontSize: 13),
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

  Widget _saveButton() {
    return Align(
      alignment: Alignment.centerRight,
      child: ElevatedButton.icon(
        onPressed: widget.isSaving(type) ? null : _save,
        icon: const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
      ),
    );
  }
}
