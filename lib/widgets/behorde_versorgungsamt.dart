import 'package:flutter/material.dart';
import '../services/api_service.dart';

/// Versorgungsamt content — similar structure to Arzt tabs:
/// [Amt | Termine | Korrespondenz | Schwerbehindertenausweis | GdB]
class BehordeVersorgungsamtContent extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeVersorgungsamtContent({
    super.key,
    required this.apiService,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeVersorgungsamtContent> createState() => _BehordeVersorgungsamtContentState();
}

class _BehordeVersorgungsamtContentState extends State<BehordeVersorgungsamtContent> {
  static const type = 'versorgungsamt';

  late TextEditingController _sachbearbeiterC;
  late TextEditingController _aktenzeichenC;
  late TextEditingController _notizenC;
  // Schwerbehindertenausweis
  late TextEditingController _ausweisNrC;
  late TextEditingController _ausweisAusgestelltC;
  late TextEditingController _ausweisGueltigBisC;
  // GdB
  late TextEditingController _gdbAktuellC;
  late TextEditingController _gdbFeststellungC;
  late TextEditingController _gdbBescheidC;

  bool _controllersInit = false;

  void _initControllers(Map<String, dynamic> data) {
    _sachbearbeiterC = TextEditingController(text: data['sachbearbeiter'] ?? '');
    _aktenzeichenC = TextEditingController(text: data['aktenzeichen'] ?? '');
    _notizenC = TextEditingController(text: data['notizen'] ?? '');
    _ausweisNrC = TextEditingController(text: data['ausweis_nr'] ?? '');
    _ausweisAusgestelltC = TextEditingController(text: data['ausweis_ausgestellt_am'] ?? '');
    _ausweisGueltigBisC = TextEditingController(text: data['ausweis_gueltig_bis'] ?? '');
    _gdbAktuellC = TextEditingController(text: data['gdb_aktuell']?.toString() ?? '');
    _gdbFeststellungC = TextEditingController(text: data['gdb_feststellung_datum'] ?? '');
    _gdbBescheidC = TextEditingController(text: data['gdb_bescheid_datum'] ?? '');
    _controllersInit = true;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isLoading(type) && widget.getData(type).isEmpty) {
      widget.loadData(type);
    }
  }

  @override
  void dispose() {
    if (_controllersInit) {
      _sachbearbeiterC.dispose();
      _aktenzeichenC.dispose();
      _notizenC.dispose();
      _ausweisNrC.dispose();
      _ausweisAusgestelltC.dispose();
      _ausweisGueltigBisC.dispose();
      _gdbAktuellC.dispose();
      _gdbFeststellungC.dispose();
      _gdbBescheidC.dispose();
    }
    super.dispose();
  }

  void _saveAll(Map<String, dynamic> data) {
    data['sachbearbeiter'] = _sachbearbeiterC.text.trim();
    data['aktenzeichen'] = _aktenzeichenC.text.trim();
    data['notizen'] = _notizenC.text.trim();
    data['ausweis_nr'] = _ausweisNrC.text.trim();
    data['ausweis_ausgestellt_am'] = _ausweisAusgestelltC.text.trim();
    data['ausweis_gueltig_bis'] = _ausweisGueltigBisC.text.trim();
    data['gdb_aktuell'] = int.tryParse(_gdbAktuellC.text.trim()) ?? 0;
    data['gdb_feststellung_datum'] = _gdbFeststellungC.text.trim();
    data['gdb_bescheid_datum'] = _gdbBescheidC.text.trim();
    widget.saveData(type, data);
  }

  Future<void> _pickVersorgungsamt(Map<String, dynamic> data) async {
    final result = await widget.apiService.searchVersorgungsaemter(bundesland: 'Bayern');
    if (!mounted) return;
    final amter = (result['aerzte'] as List?) ?? (result['data'] as List?) ?? (result['versorgungsaemter'] as List?) ?? [];

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Versorgungsamt auswählen'),
        content: SizedBox(
          width: 460,
          height: 400,
          child: amter.isEmpty
              ? const Center(child: Text('Keine Versorgungsämter gefunden'))
              : ListView.builder(
                  itemCount: amter.length,
                  itemBuilder: (_, i) {
                    final a = Map<String, dynamic>.from(amter[i] as Map);
                    return Card(
                      child: ListTile(
                        leading: Icon(Icons.account_balance, color: Colors.indigo.shade700),
                        title: Text(a['name']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: Text(
                          '${a['strasse'] ?? ''}\n${a['plz_ort'] ?? ''}\nTel: ${a['telefon'] ?? '-'}',
                          style: const TextStyle(fontSize: 11),
                        ),
                        isThreeLine: true,
                        onTap: () {
                          setState(() {
                            data['selected_amt_id'] = a['id'];
                            data['selected_amt'] = a;
                          });
                          _saveAll(data);
                          Navigator.pop(ctx);
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = Map<String, dynamic>.from(widget.getData(type));
    if (widget.isLoading(type)) return const Center(child: CircularProgressIndicator());
    if (!_controllersInit) _initControllers(data);

    return DefaultTabController(
      length: 5,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.indigo.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.indigo.shade700,
            isScrollable: true,
            tabs: const [
              Tab(icon: Icon(Icons.account_balance, size: 16), text: 'Amt'),
              Tab(icon: Icon(Icons.calendar_month, size: 16), text: 'Termine'),
              Tab(icon: Icon(Icons.mail, size: 16), text: 'Korrespondenz'),
              Tab(icon: Icon(Icons.badge, size: 16), text: 'SB-Ausweis'),
              Tab(icon: Icon(Icons.accessible, size: 16), text: 'GdB'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAmtTab(data),
                _buildTermineTab(data),
                _buildKorrespondenzTab(data),
                _buildAusweisTab(data),
                _buildGdbTab(data),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmtTab(Map<String, dynamic> data) {
    final selAmt = (data['selected_amt'] is Map) ? Map<String, dynamic>.from(data['selected_amt']) : <String, dynamic>{};
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (selAmt.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(children: [
                Icon(Icons.account_balance, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Kein Versorgungsamt zugewiesen', style: TextStyle(color: Colors.grey.shade600)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.search, size: 18),
                  label: const Text('Versorgungsamt auswählen'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                  onPressed: () => _pickVersorgungsamt(data),
                ),
              ]),
            )
          else ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    backgroundColor: Colors.indigo.shade100,
                    child: Icon(Icons.account_balance, color: Colors.indigo.shade700, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(selAmt['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      if (selAmt['kurzname'] != null)
                        Text(selAmt['kurzname'].toString(), style: TextStyle(fontSize: 11, color: Colors.indigo.shade700)),
                    ]),
                  ),
                  TextButton.icon(
                    onPressed: () => _pickVersorgungsamt(data),
                    icon: const Icon(Icons.edit, size: 14),
                    label: const Text('Ändern', style: TextStyle(fontSize: 11)),
                  ),
                ]),
                const Divider(),
                _infoRow(Icons.location_on, '${selAmt['strasse'] ?? ''}, ${selAmt['plz_ort'] ?? ''}'),
                if ((selAmt['postanschrift']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.mail, selAmt['postanschrift'].toString()),
                if ((selAmt['telefon']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.phone, selAmt['telefon'].toString()),
                if ((selAmt['telefax']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.print, selAmt['telefax'].toString()),
                if ((selAmt['email']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.email, selAmt['email'].toString()),
                if ((selAmt['website']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.language, selAmt['website'].toString()),
                if ((selAmt['oeffnungszeiten']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Öffnungszeiten:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                  Text(selAmt['oeffnungszeiten'].toString(), style: const TextStyle(fontSize: 11)),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _sachbearbeiterC,
              decoration: const InputDecoration(labelText: 'Sachbearbeiter', prefixIcon: Icon(Icons.person_pin, size: 18), border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _saveAll(data),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _aktenzeichenC,
              decoration: const InputDecoration(labelText: 'Aktenzeichen', prefixIcon: Icon(Icons.tag, size: 18), border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _saveAll(data),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _notizenC,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Notizen', prefixIcon: Icon(Icons.note, size: 18), border: OutlineInputBorder(), isDense: true),
              onChanged: (_) => _saveAll(data),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTermineTab(Map<String, dynamic> data) {
    final termine = List<Map<String, dynamic>>.from(data['termine'] ?? []);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.calendar_month, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Text('Termine beim Versorgungsamt', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showTerminDialog(data),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Termin'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: termine.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.event_available, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Termine eingetragen', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: termine.length,
                itemBuilder: (_, i) {
                  final t = termine[i];
                  final typ = t['typ']?.toString() ?? 'normal';
                  final color = typ == 'anfrage' ? Colors.orange : (typ == 'absage' ? Colors.red : (typ == 'verschoben' ? Colors.blue : Colors.teal));
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(backgroundColor: color.shade100, child: Icon(Icons.event, color: color.shade700, size: 20)),
                      title: Text('${t['datum'] ?? ''}${t['uhrzeit'] != null && t['uhrzeit'].toString().isNotEmpty ? ' um ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${typ.toUpperCase()}${(t['notizen']?.toString() ?? '').isNotEmpty ? '\n${t['notizen']}' : ''}', style: const TextStyle(fontSize: 11)),
                      isThreeLine: (t['notizen']?.toString() ?? '').isNotEmpty,
                      trailing: IconButton(
                        icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                        onPressed: () {
                          setState(() => termine.removeAt(i));
                          data['termine'] = termine;
                          widget.saveData(type, data);
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildKorrespondenzTab(Map<String, dynamic> data) {
    final korr = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.mail, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Text('Korrespondenz', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showKorrDialog(data),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Eintrag'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: korr.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.mark_email_unread, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: korr.length,
                itemBuilder: (_, i) {
                  final k = korr[i];
                  final richt = k['richtung']?.toString() ?? 'eingehend';
                  final icon = richt == 'ausgehend' ? Icons.outbox : Icons.inbox;
                  final color = richt == 'ausgehend' ? Colors.blue : Colors.green;
                  return Card(
                    child: ListTile(
                      leading: Icon(icon, color: color),
                      title: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${k['datum'] ?? ''} • ${richt.toUpperCase()}${(k['inhalt']?.toString() ?? '').isNotEmpty ? '\n${k['inhalt']}' : ''}', style: const TextStyle(fontSize: 11)),
                      isThreeLine: (k['inhalt']?.toString() ?? '').isNotEmpty,
                      trailing: IconButton(
                        icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                        onPressed: () {
                          setState(() => korr.removeAt(i));
                          data['korrespondenz'] = korr;
                          widget.saveData(type, data);
                        },
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _buildAusweisTab(Map<String, dynamic> data) {
    final merkzeichen = [
      ('g', 'G – Erhebliche Gehbehinderung'),
      ('aG', 'aG – Außergewöhnliche Gehbehinderung'),
      ('B', 'B – Begleitperson erforderlich'),
      ('H', 'H – Hilflos'),
      ('RF', 'RF – Rundfunkbeitragsermäßigung'),
      ('Bl', 'Bl – Blind'),
      ('Gl', 'Gl – Gehörlos'),
      ('TBl', 'TBl – Taubblind'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Schwerbehindertenausweis', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 12),
        TextField(
          controller: _ausweisNrC,
          decoration: const InputDecoration(labelText: 'Ausweisnummer', prefixIcon: Icon(Icons.badge, size: 18), border: OutlineInputBorder(), isDense: true),
          onChanged: (_) => _saveAll(data),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _datePicker(context, _ausweisAusgestelltC, 'Ausgestellt am', () => _saveAll(data))),
          const SizedBox(width: 12),
          Expanded(child: _datePicker(context, _ausweisGueltigBisC, 'Gültig bis', () => _saveAll(data))),
        ]),
        const SizedBox(height: 16),
        Text('Merkzeichen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: merkzeichen.map((m) {
            final key = 'merkzeichen_${m.$1.toLowerCase()}';
            final sel = data[key] == true;
            return FilterChip(
              label: Text(m.$2, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.indigo.shade700)),
              selected: sel,
              selectedColor: Colors.indigo.shade600,
              backgroundColor: Colors.indigo.shade50,
              checkmarkColor: Colors.white,
              side: BorderSide(color: sel ? Colors.indigo.shade600 : Colors.indigo.shade200),
              onSelected: (v) {
                setState(() => data[key] = v);
                widget.saveData(type, data);
              },
            );
          }).toList(),
        ),
      ]),
    );
  }

  Widget _buildGdbTab(Map<String, dynamic> data) {
    final historie = List<Map<String, dynamic>>.from(data['gdb_historie'] ?? []);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Grad der Behinderung (GdB)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Aktueller GdB', style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: _gdbAktuellC,
              keyboardType: TextInputType.number,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(suffixText: '%', border: OutlineInputBorder(), isDense: true, hintText: '50'),
              onChanged: (_) => _saveAll(data),
            ),
          ]),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _datePicker(context, _gdbFeststellungC, 'Feststellung am', () => _saveAll(data))),
          const SizedBox(width: 12),
          Expanded(child: _datePicker(context, _gdbBescheidC, 'Bescheid vom', () => _saveAll(data))),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          Icon(Icons.history, size: 16, color: Colors.indigo.shade700),
          const SizedBox(width: 6),
          Text('Verlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _showGdbHistoryDialog(data),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Eintrag hinzufügen', style: TextStyle(fontSize: 11)),
          ),
        ]),
        if (historie.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Keine früheren GdB-Einträge', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
          )
        else
          ...historie.asMap().entries.map((e) {
            final h = e.value;
            return Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                dense: true,
                leading: CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Text('${h['gdb'] ?? '?'}', style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.bold))),
                title: Text('GdB ${h['gdb'] ?? '?'}%', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Text('${h['datum'] ?? ''}${(h['notiz']?.toString() ?? '').isNotEmpty ? ' • ${h['notiz']}' : ''}', style: const TextStyle(fontSize: 11)),
                trailing: IconButton(
                  icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                  onPressed: () {
                    setState(() => historie.removeAt(e.key));
                    data['gdb_historie'] = historie;
                    widget.saveData(type, data);
                  },
                ),
              ),
            );
          }),
      ]),
    );
  }

  // ========== Helpers ==========

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.indigo.shade600),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
      ]),
    );
  }

  Widget _datePicker(BuildContext ctx, TextEditingController c, String label, VoidCallback onChange) {
    return TextField(
      controller: c,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.calendar_today, size: 16),
        border: const OutlineInputBorder(),
        isDense: true,
        suffixIcon: IconButton(
          icon: const Icon(Icons.edit_calendar, size: 16),
          onPressed: () async {
            final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(1950), lastDate: DateTime(2060), locale: const Locale('de'));
            if (picked != null) {
              c.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
              onChange();
            }
          },
        ),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }

  void _showTerminDialog(Map<String, dynamic> data) {
    final datumC = TextEditingController();
    final uhrzeitC = TextEditingController();
    final notizenC = TextEditingController();
    String typ = 'normal';
    final typen = [('normal', 'Normal', Colors.teal), ('anfrage', 'Anfrage', Colors.orange), ('absage', 'Absage', Colors.red), ('verschoben', 'Verschoben', Colors.blue)];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Neuer Termin'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(
              spacing: 6,
              children: typen.map((t) {
                final sel = typ == t.$1;
                return ChoiceChip(
                  label: Text(t.$2, style: TextStyle(fontSize: 11, color: sel ? Colors.white : t.$3.shade700)),
                  selected: sel,
                  selectedColor: t.$3.shade600,
                  onSelected: (_) => setD(() => typ = t.$1),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            _datePicker(ctx, datumC, 'Datum *', () => setD(() {})),
            const SizedBox(height: 12),
            TextField(controller: uhrzeitC, decoration: const InputDecoration(labelText: 'Uhrzeit (z.B. 14:00)', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            TextField(controller: notizenC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder(), isDense: true)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (datumC.text.isEmpty) return;
              final termine = List<Map<String, dynamic>>.from(data['termine'] ?? []);
              termine.add({'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'typ': typ, 'notizen': notizenC.text});
              termine.sort((a, b) => (b['datum'] ?? '').toString().compareTo((a['datum'] ?? '').toString()));
              setState(() => data['termine'] = termine);
              widget.saveData(type, data);
              Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      )),
    );
  }

  void _showKorrDialog(Map<String, dynamic> data) {
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final inhaltC = TextEditingController();
    String richt = 'eingehend';
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Neue Korrespondenz'),
        content: SizedBox(
          width: 400,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('Eingehend', style: TextStyle(fontSize: 11)), selected: richt == 'eingehend', selectedColor: Colors.green.shade600, onSelected: (_) => setD(() => richt = 'eingehend')),
              ChoiceChip(label: const Text('Ausgehend', style: TextStyle(fontSize: 11)), selected: richt == 'ausgehend', selectedColor: Colors.blue.shade600, onSelected: (_) => setD(() => richt = 'ausgehend')),
            ]),
            const SizedBox(height: 12),
            _datePicker(ctx, datumC, 'Datum *', () => setD(() {})),
            const SizedBox(height: 12),
            TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff *', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            TextField(controller: inhaltC, maxLines: 5, decoration: const InputDecoration(labelText: 'Inhalt / Zusammenfassung', border: OutlineInputBorder(), isDense: true)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (datumC.text.isEmpty || betreffC.text.isEmpty) return;
              final korr = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
              korr.add({'datum': datumC.text, 'richtung': richt, 'betreff': betreffC.text, 'inhalt': inhaltC.text});
              korr.sort((a, b) => (b['datum'] ?? '').toString().compareTo((a['datum'] ?? '').toString()));
              setState(() => data['korrespondenz'] = korr);
              widget.saveData(type, data);
              Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      )),
    );
  }

  void _showGdbHistoryDialog(Map<String, dynamic> data) {
    final gdbC = TextEditingController();
    final datumC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('GdB-Eintrag hinzufügen'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: gdbC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'GdB *', suffixText: '%', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            _datePicker(ctx, datumC, 'Datum *', () => setD(() {})),
            const SizedBox(height: 12),
            TextField(controller: notizC, decoration: const InputDecoration(labelText: 'Notiz', border: OutlineInputBorder(), isDense: true)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              final gdb = int.tryParse(gdbC.text.trim());
              if (gdb == null || datumC.text.isEmpty) return;
              final historie = List<Map<String, dynamic>>.from(data['gdb_historie'] ?? []);
              historie.add({'gdb': gdb, 'datum': datumC.text, 'notiz': notizC.text});
              historie.sort((a, b) => (b['datum'] ?? '').toString().compareTo((a['datum'] ?? '').toString()));
              setState(() => data['gdb_historie'] = historie);
              widget.saveData(type, data);
              Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      )),
    );
  }
}
