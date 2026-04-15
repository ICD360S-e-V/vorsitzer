import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_service.dart';
import '../services/termin_service.dart';

/// Versorgungsamt content with tabs similar to Arzt structure.
class BehordeVersorgungsamtContent extends StatefulWidget {
  final ApiService apiService;
  final TerminService terminService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeVersorgungsamtContent({
    super.key,
    required this.apiService,
    required this.terminService,
    required this.userId,
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

  // Sachbearbeiter
  String _sbAnrede = '';
  late TextEditingController _sbNameC;
  late TextEditingController _sbTelC;
  late TextEditingController _sbFaxC;
  bool _sbEditing = false;

  // Aktenzeichen split 4-4
  late TextEditingController _aktPart1C;
  late TextEditingController _aktPart2C;

  late TextEditingController _notizenC;
  // Schwerbehindertenausweis
  late TextEditingController _ausweisNrC;
  late TextEditingController _ausweisAusgestelltC;
  late TextEditingController _ausweisGueltigBisC;
  bool _ausweisUnbefristet = false;
  // GdB
  int _gdbAktuell = 0;
  late TextEditingController _gdbFeststellungC;
  late TextEditingController _gdbBescheidC;

  bool _controllersInit = false;

  // GdB options — short dropdown labels
  static const List<(int, String)> _gdbOptions = [
    (0, 'Nicht festgestellt'),
    (20, 'GdB 20'),
    (30, 'GdB 30'),
    (40, 'GdB 40'),
    (50, 'GdB 50 – Schwerbehindert'),
    (60, 'GdB 60'),
    (70, 'GdB 70'),
    (80, 'GdB 80'),
    (90, 'GdB 90'),
    (100, 'GdB 100'),
  ];

  /// Detailed list of Nachteilsausgleiche per GdB level.
  /// Source: schwerbehinderung-vorteile.de — cumulative (higher GdB inherits lower benefits)
  static const Map<int, List<String>> _gdbBenefits = {
    20: [
      'Steuerfreibetrag: 384 €/Jahr',
      'Gleichstellung mit schwerbehinderten Menschen möglich (§ 2 Abs. 3 SGB IX)',
    ],
    30: [
      'Steuerfreibetrag: 620 €/Jahr',
      'Gleichstellung mit schwerbehinderten Menschen möglich',
      'Kündigungsschutz nach Gleichstellung',
      'Unterstützung beim Jobcenter / Integrationsfachdienst',
      'Hilfe zur Erhaltung des Arbeitsplatzes',
    ],
    40: [
      'Steuerfreibetrag: 860 €/Jahr',
      'Gleichstellung mit schwerbehinderten Menschen möglich',
      'Kündigungsschutz nach Gleichstellung',
      'Integrationsfachdienst-Unterstützung',
    ],
    50: [
      'Steuerfreibetrag: 1.140 €/Jahr',
      'Offizieller Status "schwerbehindert" + Schwerbehindertenausweis',
      'Besonderer Kündigungsschutz (§ 168 SGB IX)',
      '5 Tage Zusatzurlaub pro Jahr',
      'Freistellung von Mehrarbeit (§ 207 SGB IX)',
      'Vorzeitige Altersrente (mit Abschlägen)',
      'Bevorzugte Einstellung bei öffentlichen Arbeitgebern',
      'Arbeitsplatz-/Wohnraumanpassung durch Integrationsamt',
      'Kündigungsschutz bei Mietwohnung',
      'KFZ-Rabatte beim Neuwagenkauf',
      'Gebührenermäßigung bei Behördengängen',
      'Krankenkassen-Zuzahlungsgrenze: max. 1% vom Bruttoeinkommen',
      'KFZ-Pauschale: 0,30 €/km oder tatsächliche Kosten',
      'Ermäßigte BahnCard möglich',
      'Kurtaxen-Ermäßigung',
    ],
    60: [
      'Steuerfreibetrag: 1.440 €/Jahr',
      'Alle Vorteile ab GdB 50',
      'Zusätzliche Rabatte bei Mobilitätshilfen',
    ],
    70: [
      'Steuerfreibetrag: 1.780 €/Jahr',
      'Alle Vorteile ab GdB 50',
      'BahnCard 25/50 zum halben Preis',
      'KFZ-Pauschale: 3.000 €/Jahr (statt tatsächlicher Kosten)',
    ],
    80: [
      'Steuerfreibetrag: 2.120 €/Jahr',
      'Alle Vorteile ab GdB 70',
      'Höhere Freibeträge bei Mietminderung',
    ],
    90: [
      'Steuerfreibetrag: 2.460 €/Jahr',
      'Alle Vorteile ab GdB 80',
      'Erweiterter Pauschbetrag im Steuerrecht',
    ],
    100: [
      'Steuerfreibetrag: 2.840 €/Jahr (maximal)',
      'Alle Vorteile ab GdB 90',
      'Vorzeitige Verfügung über Bausparkassen-Guthaben',
      'Vorzeitige Altersrente (für besonders betroffene)',
      'Pflege-Pauschbetrag (bei Pflegegrad)',
      'KFZ-Steuerbefreiung (mit Merkzeichen H/Bl/aG) oder Ermäßigung (-50%)',
    ],
  };

  void _migrateLegacy(Map<String, dynamic> data) {
    if (data['versorgungsamt'] is Map) {
      final legacy = Map<String, dynamic>.from(data['versorgungsamt'] as Map);
      data['sachbearbeiter_anrede'] ??= legacy['sachbearbeiter_anrede'];
      data['sachbearbeiter'] ??= legacy['sachbearbeiter_name'];
      data['aktenzeichen'] ??= legacy['aktenzeichen'];
      data['notizen'] ??= legacy['notizen'];
      data['ausweis_gueltig_bis'] ??= legacy['gueltig_bis'];
      data['ausweis_unbefristet'] ??= (legacy['befristung']?.toString() == 'unbefristet');
      final legacyGdb = legacy['gdb'];
      if (data['gdb_aktuell'] == null && legacyGdb != null && legacyGdb.toString().isNotEmpty) {
        data['gdb_aktuell'] = int.tryParse(legacyGdb.toString()) ?? 0;
      }
      if (data['selected_amt'] == null && legacy['behoerde'] is Map) {
        data['selected_amt'] = Map<String, dynamic>.from(legacy['behoerde'] as Map);
        data['selected_amt_id'] = (legacy['behoerde'] as Map)['id'];
      }
      if (legacy['merkzeichen_list'] is List) {
        final list = (legacy['merkzeichen_list'] as List).map((e) => e.toString().toLowerCase()).toSet();
        for (final m in ['g', 'ag', 'b', 'h', 'rf', 'bl', 'gl', 'tbl']) {
          final key = 'merkzeichen_$m';
          data[key] ??= list.contains(m);
        }
      }
    }
    if (data['korrespondenz'] == null && data['verlauf'] is List) {
      data['korrespondenz'] = (data['verlauf'] as List).map((e) {
        final v = Map<String, dynamic>.from(e as Map);
        return {
          'datum': v['datum'] ?? v['created_at'],
          'richtung': (v['type']?.toString() == 'ausgang') ? 'ausgehend' : 'eingehend',
          'methode': v['method'] ?? '',
          'betreff': v['betreff'] ?? '',
          'inhalt': v['inhalt'] ?? v['notizen'] ?? '',
          'dokumente': v['documents'] ?? [],
        };
      }).toList();
    }
  }

  (String, String) _splitAkt(String raw) {
    final parts = raw.split('-');
    if (parts.length >= 2) return (parts[0].substring(0, parts[0].length.clamp(0, 4)), parts.sublist(1).join('-'));
    return (raw.length > 4 ? raw.substring(0, 4) : raw, raw.length > 4 ? raw.substring(4) : '');
  }

  String _joinAkt() {
    final p1 = _aktPart1C.text.trim();
    final p2 = _aktPart2C.text.trim();
    if (p1.isEmpty && p2.isEmpty) return '';
    if (p2.isEmpty) return p1;
    return '$p1-$p2';
  }

  void _initControllers(Map<String, dynamic> data) {
    _migrateLegacy(data);
    _sbAnrede = data['sachbearbeiter_anrede']?.toString() ?? '';
    _sbNameC = TextEditingController(text: data['sachbearbeiter'] ?? '');
    _sbTelC = TextEditingController(text: data['sachbearbeiter_telefon'] ?? '');
    _sbFaxC = TextEditingController(text: data['sachbearbeiter_fax'] ?? '');
    final (p1, p2) = _splitAkt((data['aktenzeichen'] ?? '').toString());
    _aktPart1C = TextEditingController(text: p1);
    _aktPart2C = TextEditingController(text: p2);
    _notizenC = TextEditingController(text: data['notizen'] ?? '');
    _ausweisNrC = TextEditingController(text: data['ausweis_nr'] ?? '');
    _ausweisAusgestelltC = TextEditingController(text: data['ausweis_ausgestellt_am'] ?? '');
    _ausweisGueltigBisC = TextEditingController(text: data['ausweis_gueltig_bis'] ?? '');
    _ausweisUnbefristet = data['ausweis_unbefristet'] == true;
    _gdbAktuell = (data['gdb_aktuell'] as num?)?.toInt() ?? 0;
    _gdbFeststellungC = TextEditingController(text: data['gdb_feststellung_datum'] ?? '');
    _gdbBescheidC = TextEditingController(text: data['gdb_bescheid_datum'] ?? '');
    _controllersInit = true;
  }

  @override
  void initState() {
    super.initState();
    if (!widget.isLoading(type) && widget.getData(type).isEmpty) widget.loadData(type);
  }

  @override
  void dispose() {
    if (_controllersInit) {
      _sbNameC.dispose();
      _sbTelC.dispose();
      _sbFaxC.dispose();
      _aktPart1C.dispose();
      _aktPart2C.dispose();
      _notizenC.dispose();
      _ausweisNrC.dispose();
      _ausweisAusgestelltC.dispose();
      _ausweisGueltigBisC.dispose();
      _gdbFeststellungC.dispose();
      _gdbBescheidC.dispose();
    }
    super.dispose();
  }

  void _saveAll(Map<String, dynamic> data) {
    data['sachbearbeiter_anrede'] = _sbAnrede;
    data['sachbearbeiter'] = _sbNameC.text.trim();
    data['sachbearbeiter_telefon'] = _sbTelC.text.trim();
    data['sachbearbeiter_fax'] = _sbFaxC.text.trim();
    data['aktenzeichen'] = _joinAkt();
    data['notizen'] = _notizenC.text.trim();
    data['ausweis_nr'] = _ausweisNrC.text.trim();
    data['ausweis_ausgestellt_am'] = _ausweisAusgestelltC.text.trim();
    data['ausweis_gueltig_bis'] = _ausweisUnbefristet ? '' : _ausweisGueltigBisC.text.trim();
    data['ausweis_unbefristet'] = _ausweisUnbefristet;
    data['gdb_aktuell'] = _gdbAktuell;
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
                        subtitle: Text('${a['strasse'] ?? ''}\n${a['plz_ort'] ?? ''}\nTel: ${a['telefon'] ?? '-'}', style: const TextStyle(fontSize: 11)),
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

  // ============ TAB 1: AMT ============

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
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade300)),
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
              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.indigo.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(backgroundColor: Colors.indigo.shade100, child: Icon(Icons.account_balance, color: Colors.indigo.shade700, size: 22)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(selAmt['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (selAmt['kurzname'] != null) Text(selAmt['kurzname'].toString(), style: TextStyle(fontSize: 11, color: Colors.indigo.shade700)),
                  ])),
                  TextButton.icon(onPressed: () => _pickVersorgungsamt(data), icon: const Icon(Icons.edit, size: 14), label: const Text('Ändern', style: TextStyle(fontSize: 11))),
                ]),
                const Divider(),
                _infoRow(Icons.location_on, '${selAmt['strasse'] ?? ''}, ${selAmt['plz_ort'] ?? ''}'),
                if ((selAmt['postanschrift']?.toString() ?? '').isNotEmpty) _infoRow(Icons.mail, selAmt['postanschrift'].toString()),
                if ((selAmt['telefon']?.toString() ?? '').isNotEmpty) _infoRow(Icons.phone, selAmt['telefon'].toString()),
                if ((selAmt['telefax']?.toString() ?? '').isNotEmpty) _infoRow(Icons.print, selAmt['telefax'].toString()),
                if ((selAmt['email']?.toString() ?? '').isNotEmpty) _infoRow(Icons.email, selAmt['email'].toString()),
                if ((selAmt['website']?.toString() ?? '').isNotEmpty) _infoRow(Icons.language, selAmt['website'].toString()),
                if ((selAmt['oeffnungszeiten']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text('Öffnungszeiten:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                  Text(selAmt['oeffnungszeiten'].toString(), style: const TextStyle(fontSize: 11)),
                ],
              ]),
            ),
            const SizedBox(height: 16),
            _buildSachbearbeiterCard(data),
            const SizedBox(height: 16),
            _buildAktenzeichenRow(data),
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

  Widget _buildSachbearbeiterCard(Map<String, dynamic> data) {
    final readOnly = !_sbEditing;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.person_pin, size: 18, color: Colors.indigo.shade700),
          const SizedBox(width: 6),
          Text('Sachbearbeiter/in', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          IconButton(
            icon: Icon(_sbEditing ? Icons.check : Icons.edit, size: 18, color: _sbEditing ? Colors.green.shade700 : Colors.grey.shade600),
            tooltip: _sbEditing ? 'Speichern' : 'Bearbeiten',
            onPressed: () {
              setState(() => _sbEditing = !_sbEditing);
              if (!_sbEditing) _saveAll(data);
            },
          ),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Container(
            width: 100,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(6)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _sbAnrede.isEmpty ? null : _sbAnrede,
                hint: const Text('Anrede', style: TextStyle(fontSize: 12)),
                isDense: true,
                isExpanded: true,
                items: const [
                  DropdownMenuItem(value: 'Frau', child: Text('Frau', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'Herr', child: Text('Herr', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: 'Divers', child: Text('Divers', style: TextStyle(fontSize: 12))),
                ],
                onChanged: readOnly ? null : (v) {
                  setState(() => _sbAnrede = v ?? '');
                  _saveAll(data);
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _sbNameC,
            readOnly: readOnly,
            decoration: InputDecoration(labelText: 'Name', isDense: true, border: const OutlineInputBorder(), filled: readOnly, fillColor: readOnly ? Colors.grey.shade100 : null),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => _saveAll(data),
          )),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(
            controller: _sbTelC,
            readOnly: readOnly,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 16), isDense: true, border: const OutlineInputBorder(), filled: readOnly, fillColor: readOnly ? Colors.grey.shade100 : null),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => _saveAll(data),
          )),
          const SizedBox(width: 8),
          Expanded(child: TextField(
            controller: _sbFaxC,
            readOnly: readOnly,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(labelText: 'Fax', prefixIcon: const Icon(Icons.print, size: 16), isDense: true, border: const OutlineInputBorder(), filled: readOnly, fillColor: readOnly ? Colors.grey.shade100 : null),
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => _saveAll(data),
          )),
        ]),
      ]),
    );
  }

  Widget _buildAktenzeichenRow(Map<String, dynamic> data) {
    return Row(children: [
      const Icon(Icons.tag, size: 18, color: Colors.grey),
      const SizedBox(width: 8),
      const SizedBox(width: 90, child: Text('Aktenzeichen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      SizedBox(
        width: 70,
        child: TextField(
          controller: _aktPart1C,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: '', border: OutlineInputBorder(), isDense: true, hintText: '0000'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          onChanged: (_) => _saveAll(data),
        ),
      ),
      const SizedBox(width: 8),
      const Text('–', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(width: 8),
      SizedBox(
        width: 70,
        child: TextField(
          controller: _aktPart2C,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(counterText: '', border: OutlineInputBorder(), isDense: true, hintText: '0000'),
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
          onChanged: (_) => _saveAll(data),
        ),
      ),
    ]);
  }

  // ============ TAB 2: TERMINE ============

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
            _timePicker(ctx, uhrzeitC, 'Uhrzeit', () => setD(() {})),
            const SizedBox(height: 12),
            TextField(controller: notizenC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notizen', border: OutlineInputBorder(), isDense: true)),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () async {
              if (datumC.text.isEmpty) return;
              final termine = List<Map<String, dynamic>>.from(data['termine'] ?? []);
              final newT = {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'typ': typ, 'notizen': notizenC.text};
              termine.add(newT);
              termine.sort((a, b) => (b['datum'] ?? '').toString().compareTo((a['datum'] ?? '').toString()));
              setState(() => data['termine'] = termine);
              widget.saveData(type, data);
              // Also create entry in global Terminverwaltung
              try {
                final selAmt = data['selected_amt'] is Map ? Map<String, dynamic>.from(data['selected_amt'] as Map) : <String, dynamic>{};
                final amtName = selAmt['kurzname']?.toString() ?? selAmt['name']?.toString() ?? 'Termin';
                final timePart = uhrzeitC.text.isEmpty ? '09:00' : uhrzeitC.text;
                final terminDate = DateTime.parse('${datumC.text} $timePart:00');
                final loc = ['${selAmt['strasse'] ?? ''}', '${selAmt['plz_ort'] ?? ''}'].where((s) => s.trim().isNotEmpty).join(', ');
                await widget.terminService.createTermin(
                  title: 'Versorgungsamt: $amtName',
                  category: 'sonstiges',
                  description: notizenC.text.isEmpty ? 'Termin beim Versorgungsamt' : notizenC.text,
                  terminDate: terminDate,
                  durationMinutes: 60,
                  location: loc,
                  participantIds: [widget.userId],
                );
              } catch (_) {}
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      )),
    );
  }

  // ============ TAB 3: KORRESPONDENZ ============

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
                  final method = k['methode']?.toString() ?? '';
                  final docs = k['dokumente'] is List ? (k['dokumente'] as List).length : 0;
                  final icon = richt == 'ausgehend' ? Icons.outbox : Icons.inbox;
                  final color = richt == 'ausgehend' ? Colors.blue : Colors.green;
                  final methodLabel = {'post': 'Post', 'email': 'E-Mail', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax'}[method] ?? method;
                  return Card(
                    child: ListTile(
                      leading: Icon(icon, color: color),
                      title: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Text('${k['datum'] ?? ''} • ${richt.toUpperCase()}${methodLabel.isNotEmpty ? ' • $methodLabel' : ''}${docs > 0 ? ' • 📎 $docs' : ''}${(k['inhalt']?.toString() ?? '').isNotEmpty ? '\n${k['inhalt']}' : ''}', style: const TextStyle(fontSize: 11)),
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

  void _showKorrDialog(Map<String, dynamic> data) {
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final inhaltC = TextEditingController();
    String richt = 'eingehend';
    String methode = '';
    final dokumente = <Map<String, String>>[];

    final methodOptions = {
      'post': ('Per Post', Icons.local_post_office),
      'email': ('Per E-Mail', Icons.email),
      'online': ('Online', Icons.language),
      'fax': ('Per Fax', Icons.print),
      'persoenlich': ('Persönlich', Icons.person),
    };

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('Neue Korrespondenz'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Richtung', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, children: [
              ChoiceChip(label: const Text('Eingang (vom Amt)', style: TextStyle(fontSize: 11)), selected: richt == 'eingehend', selectedColor: Colors.green.shade600, onSelected: (_) => setD(() => richt = 'eingehend')),
              ChoiceChip(label: const Text('Ausgang (ans Amt)', style: TextStyle(fontSize: 11)), selected: richt == 'ausgehend', selectedColor: Colors.blue.shade600, onSelected: (_) => setD(() => richt = 'ausgehend')),
            ]),
            const SizedBox(height: 12),
            const Text('Methode *', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Wrap(spacing: 4, runSpacing: 4, children: methodOptions.entries.map((e) {
              final sel = methode == e.key;
              return ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(e.value.$2, size: 12, color: sel ? Colors.white : Colors.indigo.shade700),
                  const SizedBox(width: 4),
                  Text(e.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.indigo.shade700)),
                ]),
                selected: sel,
                selectedColor: Colors.indigo.shade600,
                onSelected: (_) => setD(() => methode = e.key),
              );
            }).toList()),
            const SizedBox(height: 12),
            _datePicker(ctx, datumC, 'Datum *', () => setD(() {})),
            const SizedBox(height: 10),
            TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff *', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 10),
            TextField(controller: inhaltC, maxLines: 5, decoration: const InputDecoration(labelText: 'Inhalt / Zusammenfassung', border: OutlineInputBorder(), isDense: true)),
            const SizedBox(height: 12),
            Row(children: [
              const Text('Dokumente:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.upload_file, size: 14),
                label: const Text('Hochladen', style: TextStyle(fontSize: 11)),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                  if (result == null) return;
                  for (final f in result.files) {
                    if (f.path == null) continue;
                    try {
                      final bytes = await File(f.path!).readAsBytes();
                      final b64 = base64Encode(bytes);
                      dokumente.add({'name': f.name, 'size': f.size.toString(), 'data': b64});
                      setD(() {});
                    } catch (_) {}
                  }
                },
              ),
            ]),
            if (dokumente.isEmpty)
              Text('Keine Dokumente angehängt', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic))
            else
              ...dokumente.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(Icons.attach_file, size: 14, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.value['name']!, style: const TextStyle(fontSize: 11))),
                  InkWell(onTap: () { dokumente.removeAt(e.key); setD(() {}); }, child: Icon(Icons.close, size: 14, color: Colors.red.shade400)),
                ]),
              )),
          ])),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: () {
              if (datumC.text.isEmpty || betreffC.text.isEmpty || methode.isEmpty) return;
              final korr = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
              korr.add({
                'datum': datumC.text,
                'richtung': richt,
                'methode': methode,
                'betreff': betreffC.text,
                'inhalt': inhaltC.text,
                'dokumente': dokumente,
              });
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

  // ============ TAB 4: SB-AUSWEIS ============

  Widget _buildAusweisTab(Map<String, dynamic> data) {
    final merkzeichen = [
      ('g', 'G – Erhebliche Gehbehinderung'),
      ('ag', 'aG – Außergewöhnliche Gehbehinderung'),
      ('b', 'B – Begleitperson erforderlich'),
      ('h', 'H – Hilflos'),
      ('rf', 'RF – Rundfunkbeitragsermäßigung'),
      ('bl', 'Bl – Blind'),
      ('gl', 'Gl – Gehörlos'),
      ('tbl', 'TBl – Taubblind'),
    ];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Schwerbehindertenausweis', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 4),
        Text('Ausweis im Bankkarten-Format seit 2013', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
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
          Expanded(
            child: AbsorbPointer(
              absorbing: _ausweisUnbefristet,
              child: Opacity(
                opacity: _ausweisUnbefristet ? 0.5 : 1.0,
                child: _datePicker(context, _ausweisGueltigBisC, 'Gültig bis', () => _saveAll(data)),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          Checkbox(
            value: _ausweisUnbefristet,
            onChanged: (v) {
              setState(() => _ausweisUnbefristet = v ?? false);
              _saveAll(data);
            },
          ),
          const Text('Unbefristet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 16),
        Text('Merkzeichen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: merkzeichen.map((m) {
            final key = 'merkzeichen_${m.$1}';
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

  // ============ TAB 5: GDB ============

  Widget _buildGdbTab(Map<String, dynamic> data) {
    final historie = List<Map<String, dynamic>>.from(data['gdb_historie'] ?? []);
    final bescheidDocs = List<Map<String, dynamic>>.from(data['bescheid_dokumente'] ?? []);

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
            DropdownButtonFormField<int>(
              value: _gdbAktuell,
              decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
              items: _gdbOptions.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) {
                setState(() => _gdbAktuell = v ?? 0);
                _saveAll(data);
              },
            ),
          ]),
        ),
        const SizedBox(height: 12),
        if (_gdbBenefits.containsKey(_gdbAktuell)) _buildGdbBenefitsCard(),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _datePicker(context, _gdbFeststellungC, 'Feststellung am', () => _saveAll(data))),
          const SizedBox(width: 12),
          Expanded(child: _datePicker(context, _gdbBescheidC, 'Bescheid vom', () => _saveAll(data))),
        ]),
        const SizedBox(height: 16),
        // Bescheid upload
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.description, size: 16, color: Colors.indigo.shade700),
              const SizedBox(width: 6),
              Text('Bescheid-Dokumente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
              const Spacer(),
              TextButton.icon(
                icon: const Icon(Icons.upload_file, size: 14),
                label: const Text('Bescheid hochladen', style: TextStyle(fontSize: 11)),
                onPressed: () async {
                  final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                  if (result == null) return;
                  for (final f in result.files) {
                    if (f.path == null) continue;
                    try {
                      final bytes = await File(f.path!).readAsBytes();
                      bescheidDocs.add({
                        'name': f.name,
                        'size': f.size,
                        'data': base64Encode(bytes),
                        'uploaded_at': DateTime.now().toIso8601String(),
                      });
                    } catch (_) {}
                  }
                  setState(() => data['bescheid_dokumente'] = bescheidDocs);
                  widget.saveData(type, data);
                },
              ),
            ]),
            if (bescheidDocs.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Noch kein Bescheid hochgeladen', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
              )
            else
              ...bescheidDocs.asMap().entries.map((e) => Container(
                margin: const EdgeInsets.only(top: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6)),
                child: Row(children: [
                  Icon(Icons.picture_as_pdf, size: 14, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text(e.value['name']?.toString() ?? '', style: const TextStyle(fontSize: 11))),
                  InkWell(
                    onTap: () {
                      bescheidDocs.removeAt(e.key);
                      setState(() => data['bescheid_dokumente'] = bescheidDocs);
                      widget.saveData(type, data);
                    },
                    child: Icon(Icons.close, size: 14, color: Colors.red.shade400),
                  ),
                ]),
              )),
          ]),
        ),
        const SizedBox(height: 16),
        // Verlauf
        Row(children: [
          Icon(Icons.history, size: 16, color: Colors.indigo.shade700),
          const SizedBox(width: 6),
          Text('Verlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          TextButton.icon(onPressed: () => _showGdbHistoryDialog(data), icon: const Icon(Icons.add, size: 14), label: const Text('Eintrag hinzufügen', style: TextStyle(fontSize: 11))),
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

  void _showGdbHistoryDialog(Map<String, dynamic> data) {
    int gdbSel = 0;
    final datumC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setD) => AlertDialog(
        title: const Text('GdB-Eintrag hinzufügen'),
        content: SizedBox(
          width: 400,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            DropdownButtonFormField<int>(
              value: gdbSel,
              decoration: const InputDecoration(labelText: 'GdB *', border: OutlineInputBorder(), isDense: true),
              items: _gdbOptions.map((o) => DropdownMenuItem(value: o.$1, child: Text(o.$2, style: const TextStyle(fontSize: 12)))).toList(),
              onChanged: (v) => setD(() => gdbSel = v ?? 0),
            ),
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
              if (datumC.text.isEmpty) return;
              final historie = List<Map<String, dynamic>>.from(data['gdb_historie'] ?? []);
              historie.add({'gdb': gdbSel, 'datum': datumC.text, 'notiz': notizC.text});
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

  Widget _buildGdbBenefitsCard() {
    final benefits = _gdbBenefits[_gdbAktuell] ?? [];
    if (benefits.isEmpty) return const SizedBox.shrink();
    final color = _gdbAktuell >= 50 ? Colors.green : (_gdbAktuell >= 30 ? Colors.blue : Colors.amber);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.verified, size: 18, color: color.shade700),
          const SizedBox(width: 6),
          Text('Vorteile bei GdB $_gdbAktuell', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
        ]),
        const SizedBox(height: 8),
        ...benefits.map((b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.check_circle, size: 13, color: color.shade600),
            const SizedBox(width: 6),
            Expanded(child: Text(b, style: const TextStyle(fontSize: 11, height: 1.35))),
          ]),
        )),
        const SizedBox(height: 4),
        Text('Quelle: schwerbehinderung-vorteile.de', style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  // ============ HELPERS ============

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

  Widget _timePicker(BuildContext ctx, TextEditingController c, String label, VoidCallback onChange) {
    return TextField(
      controller: c,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.access_time, size: 16),
        border: const OutlineInputBorder(),
        isDense: true,
        hintText: 'z.B. 14:00',
        suffixIcon: IconButton(
          icon: const Icon(Icons.schedule, size: 16),
          onPressed: () async {
            final now = TimeOfDay.now();
            final picked = await showTimePicker(
              context: ctx,
              initialTime: TimeOfDay(hour: c.text.isNotEmpty && c.text.contains(':') ? int.tryParse(c.text.split(':')[0]) ?? now.hour : 9, minute: 0),
              builder: (ctxB, child) => MediaQuery(data: MediaQuery.of(ctxB).copyWith(alwaysUse24HourFormat: true), child: child!),
            );
            if (picked != null) {
              c.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
              onChange();
            }
          },
        ),
      ),
      style: const TextStyle(fontSize: 13),
    );
  }
}
