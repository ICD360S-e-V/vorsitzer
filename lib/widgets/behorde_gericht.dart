import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

class BehordeGerichtContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeGerichtContent({
    super.key,
    required this.user,
    required this.apiService,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeGerichtContent> createState() => _BehordeGerichtContentState();
}

class _BehordeGerichtContentState extends State<BehordeGerichtContent> {
  static const type = 'gericht';

  Widget _gerichtInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 100, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 11))),
      ],
    );
  }

  // Betreuungsgerichte Datenbank (Bayern - Schwaben Region)
  static const List<Map<String, String>> _betreuungsgerichte = [
    {
      'name': 'Amtsgericht Neu-Ulm',
      'adresse': 'Schützenstraße 60, 89231 Neu-Ulm',
      'telefon': '0731 / 70793 -422, -424 oder -425',
      'fax': '+49/9621/962410752',
      'email': 'betreuungsgericht@ag-nu.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00 Uhr',
      'zustaendigkeit': 'Betreuungsverfahren, Vormundschaft, Pflegschaft',
      'hinweis': 'Die E-Mail-Adresse eröffnet keinen Zugang für formbedürftige Erklärungen in Rechtssachen.',
    },
    {
      'name': 'Amtsgericht Ulm',
      'adresse': 'Olgastraße 109, 89073 Ulm',
      'telefon': '0731 / 189-0',
      'fax': '0731 / 189-197',
      'email': 'poststelle@agulm.justiz.bwl.de',
      'oeffnungszeiten': 'Mo–Fr 08:30–12:00, Di+Do 13:00–15:30',
      'zustaendigkeit': 'Betreuungsverfahren',
    },
    {
      'name': 'Amtsgericht Memmingen',
      'adresse': 'Bodenseestraße 4, 87700 Memmingen',
      'telefon': '08331 / 100-0',
      'fax': '08331 / 100-299',
      'email': 'poststelle@ag-mm.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Di 13:30–15:30',
      'zustaendigkeit': 'Betreuungsverfahren, Vormundschaft',
    },
    {
      'name': 'Amtsgericht Augsburg',
      'adresse': 'Am Alten Einlaß 1, 86150 Augsburg',
      'telefon': '0821 / 3187-0',
      'fax': '0821 / 3187-269',
      'email': 'poststelle@ag-a.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00, Di+Mi 13:00–15:00',
      'zustaendigkeit': 'Betreuungsverfahren, Vormundschaft, Pflegschaft',
    },
    {
      'name': 'Amtsgericht Günzburg',
      'adresse': 'Ichenhauser Str. 20, 89312 Günzburg',
      'telefon': '08221 / 206-0',
      'fax': '08221 / 206-299',
      'email': 'poststelle@ag-gz.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Betreuungsverfahren',
    },
    {
      'name': 'Amtsgericht Kempten',
      'adresse': 'Residenzplatz 4, 87435 Kempten',
      'telefon': '0831 / 5407-0',
      'fax': '0831 / 5407-209',
      'email': 'poststelle@ag-ke.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Betreuungsverfahren, Vormundschaft',
    },
    {
      'name': 'Amtsgericht Kaufbeuren',
      'adresse': 'Ganghoferstraße 8, 87600 Kaufbeuren',
      'telefon': '08341 / 802-0',
      'fax': '08341 / 802-199',
      'email': 'poststelle@ag-kf.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Betreuungsverfahren',
    },
    {
      'name': 'Amtsgericht Lindau',
      'adresse': 'Bregenzer Str. 31, 88131 Lindau',
      'telefon': '08382 / 9180-0',
      'fax': '08382 / 9180-30',
      'email': 'poststelle@ag-li.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Betreuungsverfahren',
    },
  ];

  // Sozialgerichte Datenbank (Bayern - Schwaben Region)
  static const List<Map<String, String>> _sozialgerichte = [
    {
      'name': 'Sozialgericht Augsburg',
      'adresse': 'Am Alten Einla\u00DF 1, 86150 Augsburg',
      'telefon': '0821 / 3102-0',
      'fax': '0821 / 3102-200',
      'email': 'poststelle@sg-a.bayern.de',
      'oeffnungszeiten': 'Mo\u2013Fr 08:00\u201312:00',
      'zustaendigkeit': 'Sozialversicherung, SGB II/XII, Schwerbehindertenrecht, Pflegeversicherung',
    },
    {
      'name': 'Sozialgericht Ulm',
      'adresse': 'Olgastra\u00DFe 109, 89073 Ulm',
      'telefon': '0731 / 189-0',
      'fax': '0731 / 189-197',
      'email': 'poststelle@sgulm.justiz.bwl.de',
      'oeffnungszeiten': 'Mo\u2013Fr 08:30\u201312:00',
      'zustaendigkeit': 'Sozialversicherung, Grundsicherung, Arbeitslosenversicherung',
    },
    {
      'name': 'Sozialgericht M\u00FCnchen',
      'adresse': 'Bayerstra\u00DFe 32, 80335 M\u00FCnchen',
      'telefon': '089 / 54677-0',
      'fax': '089 / 54677-400',
      'email': 'poststelle@sg-m.bayern.de',
      'oeffnungszeiten': 'Mo\u2013Fr 08:00\u201312:00',
      'zustaendigkeit': 'Sozialversicherung, SGB II/XII, Schwerbehindertenrecht',
    },
    {
      'name': 'Sozialgericht Landshut',
      'adresse': 'Gestütstra\u00DFe 10, 84028 Landshut',
      'telefon': '0871 / 96214-0',
      'fax': '0871 / 96214-199',
      'email': 'poststelle@sg-la.bayern.de',
      'oeffnungszeiten': 'Mo\u2013Fr 08:00\u201312:00',
      'zustaendigkeit': 'Sozialversicherung, Grundsicherung',
    },
    {
      'name': 'Landessozialgericht Bayern',
      'adresse': 'Ludwigstra\u00DFe 15, 80539 M\u00FCnchen',
      'telefon': '089 / 21032-0',
      'fax': '089 / 21032-100',
      'email': 'poststelle@lsg-m.bayern.de',
      'oeffnungszeiten': 'Mo\u2013Fr 08:00\u201312:00',
      'zustaendigkeit': 'Berufungsinstanz f\u00FCr alle Sozialgerichte in Bayern',
    },
  ];

  // Arbeitsgerichte Datenbank
  static const List<Map<String, String>> _arbeitsgerichte = [
    {
      'name': 'Arbeitsgericht Ulm',
      'adresse': 'Olgastraße 109, 89073 Ulm',
      'telefon': '0731 / 189-0',
      'fax': '0731 / 189-197',
      'email': 'poststelle@arbgulm.justiz.bwl.de',
      'oeffnungszeiten': 'Mo–Fr 08:30–12:00',
      'zustaendigkeit': 'Arbeitsrechtliche Streitigkeiten, Kündigungsschutz, Lohnklagen',
    },
    {
      'name': 'Arbeitsgericht Augsburg',
      'adresse': 'Frohsinnstraße 22, 86150 Augsburg',
      'telefon': '0821 / 327-0',
      'fax': '0821 / 327-100',
      'email': 'poststelle@arbg-a.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Arbeitsrechtliche Streitigkeiten, Kündigungsschutz',
    },
    {
      'name': 'Arbeitsgericht Kempten',
      'adresse': 'Residenzplatz 4, 87435 Kempten',
      'telefon': '0831 / 5407-300',
      'fax': '0831 / 5407-309',
      'email': 'poststelle@arbg-ke.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Arbeitsrechtliche Streitigkeiten',
    },
    {
      'name': 'Arbeitsgericht Memmingen',
      'adresse': 'Bodenseestraße 4, 87700 Memmingen',
      'telefon': '08331 / 100-300',
      'fax': '08331 / 100-399',
      'email': 'poststelle@arbg-mm.bayern.de',
      'oeffnungszeiten': 'Mo–Fr 08:00–12:00',
      'zustaendigkeit': 'Arbeitsrechtliche Streitigkeiten',
    },
  ];

  @override
  Widget build(BuildContext context) {
    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type)) {
      widget.loadData(type);
    }
    if (widget.isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }
    return DefaultTabController(
      length: 3,
      child: StatefulBuilder(
        builder: (context, setLocalState) {
          return Column(
            children: [
              TabBar(
                labelColor: Colors.indigo.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.indigo.shade700,
                tabs: const [
                  Tab(icon: Icon(Icons.work, size: 16), text: 'Arbeitsgericht'),
                  Tab(icon: Icon(Icons.balance, size: 16), text: 'Sozialgericht'),
                  Tab(icon: Icon(Icons.family_restroom, size: 16), text: 'Betreuungsgericht'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildGerichtTab(data, 'arbeitsgericht', _arbeitsgerichte, Colors.orange, setLocalState),
                    _buildGerichtTab(data, 'sozialgericht', _sozialgerichte, Colors.teal, setLocalState),
                    _buildGerichtTab(data, 'betreuungsgericht', _betreuungsgerichte, Colors.deepPurple, setLocalState),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGerichtTab(Map<String, dynamic> data, String gerichtTyp, List<Map<String, String>> gerichtListe, MaterialColor themeColor, void Function(void Function()) setLocalState) {
    final subKey = '${gerichtTyp}_data';
    final subData = data[subKey] is Map ? Map<String, dynamic>.from(data[subKey] as Map) : <String, dynamic>{};
    String selectedGericht = subData['gericht_name']?.toString() ?? '';
    final selected = gerichtListe.where((g) => g['name'] == selectedGericht).firstOrNull;
    final termine = List<Map<String, dynamic>>.from(subData['termine'] ?? []);
    final korrespondenz = List<Map<String, dynamic>>.from(subData['korrespondenz'] ?? []);

    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          TabBar(
            labelColor: themeColor.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: themeColor.shade700,
            tabs: const [
              Tab(icon: Icon(Icons.account_balance, size: 14), text: 'Zuständiges Gericht'),
              Tab(icon: Icon(Icons.calendar_month, size: 14), text: 'Termine'),
              Tab(icon: Icon(Icons.mail, size: 14), text: 'Korrespondenz'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                // === ZUSTÄNDIGES GERICHT ===
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Zuständiges Gericht wählen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: themeColor.shade800)),
                    const SizedBox(height: 8),
                    ...gerichtListe.map((g) {
                      final isSel = selectedGericht == g['name'];
                      return InkWell(
                        onTap: () {
                          setLocalState(() {
                            subData['gericht_name'] = g['name'];
                            data[subKey] = subData;
                          });
                          widget.saveData(type, data);
                        },
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: isSel ? themeColor.shade50 : Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: isSel ? themeColor.shade400 : Colors.grey.shade300, width: isSel ? 2 : 1),
                          ),
                          child: Row(children: [
                            Icon(isSel ? Icons.check_circle : Icons.account_balance, size: 20, color: isSel ? themeColor.shade700 : Colors.grey.shade500),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(g['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isSel ? themeColor.shade900 : Colors.black87)),
                              Text(g['adresse']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              if (g['zustaendigkeit'] != null)
                                Text(g['zustaendigkeit']!, style: TextStyle(fontSize: 10, color: themeColor.shade400, fontStyle: FontStyle.italic)),
                            ])),
                          ]),
                        ),
                      );
                    }),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(color: themeColor.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: themeColor.shade200)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Kontakt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: themeColor.shade800)),
                          const SizedBox(height: 6),
                          _gerichtInfoRow(Icons.phone, 'Telefon', selected['telefon'] ?? ''),
                          _gerichtInfoRow(Icons.print, 'Fax', selected['fax'] ?? ''),
                          _gerichtInfoRow(Icons.email, 'E-Mail', selected['email'] ?? ''),
                          _gerichtInfoRow(Icons.access_time, 'Öffnungszeiten', selected['oeffnungszeiten'] ?? ''),
                        ]),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: TextEditingController(text: subData['aktenzeichen']?.toString() ?? ''),
                      onChanged: (v) { subData['aktenzeichen'] = v; data[subKey] = subData; },
                      decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.tag, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: subData['sachbearbeiter']?.toString() ?? ''),
                      onChanged: (v) { subData['sachbearbeiter'] = v; data[subKey] = subData; },
                      decoration: InputDecoration(labelText: 'Sachbearbeiter/in', prefixIcon: const Icon(Icons.person, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: TextEditingController(text: subData['notizen']?.toString() ?? ''),
                      onChanged: (v) { subData['notizen'] = v; data[subKey] = subData; },
                      maxLines: 3,
                      decoration: InputDecoration(labelText: 'Notizen', prefixIcon: const Icon(Icons.note, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: () => widget.saveData(type, data),
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Speichern'),
                        style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white),
                      ),
                    ),
                  ]),
                ),
                // === TERMINE ===
                Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(children: [
                      Icon(Icons.calendar_month, size: 20, color: themeColor.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Termine', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: themeColor.shade700))),
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
                              TextField(controller: notizenC, maxLines: 3, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                            ])),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                              FilledButton(onPressed: () {
                                if (datumC.text.isEmpty) return;
                                setLocalState(() {
                                  termine.add({'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'notizen': notizenC.text});
                                  subData['termine'] = termine;
                                  data[subKey] = subData;
                                });
                                widget.saveData(type, data);
                                Navigator.pop(ctx);
                              }, child: const Text('Speichern')),
                            ],
                          ));
                        },
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('Neuer Termin'),
                        style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white),
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
                                leading: Icon(Icons.event, color: themeColor.shade700),
                                title: Text('${t['datum'] ?? ''}${(t['uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${t['uhrzeit']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                                subtitle: (t['notizen']?.toString() ?? '').isNotEmpty ? Text(t['notizen'].toString(), style: const TextStyle(fontSize: 11)) : null,
                                trailing: IconButton(icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400), onPressed: () {
                                  setLocalState(() { termine.removeAt(i); subData['termine'] = termine; data[subKey] = subData; });
                                  widget.saveData(type, data);
                                }),
                              ));
                            },
                          ),
                  ),
                ]),
                // === KORRESPONDENZ ===
                Column(children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    child: Row(children: [
                      Expanded(child: Text('${korrespondenz.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                      FilledButton.icon(
                        icon: const Icon(Icons.call_received, size: 14),
                        label: const Text('Eingang', style: TextStyle(fontSize: 11)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                        onPressed: () => _showGerichtKorrDialog(data, subKey, subData, korrespondenz, 'eingang', setLocalState),
                      ),
                      const SizedBox(width: 6),
                      FilledButton.icon(
                        icon: const Icon(Icons.call_made, size: 14),
                        label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                        onPressed: () => _showGerichtKorrDialog(data, subKey, subData, korrespondenz, 'ausgang', setLocalState),
                      ),
                    ]),
                  ),
                  Expanded(
                    child: korrespondenz.isEmpty
                        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 6),
                            Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ]))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: korrespondenz.length,
                            itemBuilder: (_, i) {
                              final k = korrespondenz[i];
                              final isEin = k['richtung'] == 'eingang';
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
                                child: Row(children: [
                                  Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text(k['betreff']?.toString() ?? 'Ohne Betreff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  ])),
                                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () {
                                    setLocalState(() { korrespondenz.removeAt(i); subData['korrespondenz'] = korrespondenz; data[subKey] = subData; });
                                    widget.saveData(type, data);
                                  }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
                                ]),
                              );
                            },
                          ),
                  ),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showGerichtKorrDialog(Map<String, dynamic> data, String subKey, Map<String, dynamic> subData, List<Map<String, dynamic>> korrespondenz, String richtung, void Function(void Function()) setLocalState) {
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
          setLocalState(() {
            korrespondenz.insert(0, {'richtung': richtung, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
            subData['korrespondenz'] = korrespondenz;
            data[subKey] = subData;
          });
          widget.saveData(type, data);
          Navigator.pop(ctx);
        }, child: const Text('Speichern')),
      ],
    ));
  }

  // LEGACY: old build content that used ChoiceChip (kept for reference)
  Widget _buildLegacyContent() {
    final data = widget.getData(type);
    String gerichtTyp = data['gericht_typ'] ?? 'betreuungsgericht';
    String selectedGericht = data['gericht_name'] ?? '';
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final gerichtListe = gerichtTyp == 'betreuungsgericht' ? _betreuungsgerichte : gerichtTyp == 'sozialgericht' ? _sozialgerichte : _arbeitsgerichte;
        final selected = gerichtListe.where((g) => g['name'] == selectedGericht).firstOrNull;
        final themeColor = gerichtTyp == 'betreuungsgericht' ? Colors.deepPurple : gerichtTyp == 'sozialgericht' ? Colors.teal : Colors.orange;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // OLD ChoiceChip removed — now using TabBar
                  ),
                  ChoiceChip(
                    avatar: Icon(Icons.work, size: 16, color: gerichtTyp == 'arbeitsgericht' ? Colors.white : Colors.orange.shade800),
                    label: Text('Arbeitsgericht', style: TextStyle(fontSize: 12, color: gerichtTyp == 'arbeitsgericht' ? Colors.white : Colors.black87)),
                    selected: gerichtTyp == 'arbeitsgericht',
                    selectedColor: Colors.orange.shade700,
                    onSelected: (_) => setLocalState(() {
                      gerichtTyp = 'arbeitsgericht'; selectedGericht = '';
                      data['gericht_typ'] = gerichtTyp;
                      data['gericht_name'] = '';
                    }),
                  ),
                  ChoiceChip(
                    avatar: Icon(Icons.health_and_safety, size: 16, color: gerichtTyp == 'sozialgericht' ? Colors.white : Colors.teal.shade700),
                    label: Text('Sozialgericht', style: TextStyle(fontSize: 12, color: gerichtTyp == 'sozialgericht' ? Colors.white : Colors.black87)),
                    selected: gerichtTyp == 'sozialgericht',
                    selectedColor: Colors.teal.shade600,
                    onSelected: (_) => setLocalState(() {
                      gerichtTyp = 'sozialgericht'; selectedGericht = '';
                      data['gericht_typ'] = gerichtTyp;
                      data['gericht_name'] = '';
                    }),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Zuständiges Gericht Selector
              Text('Zuständiges Gericht *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: themeColor.shade300), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedGericht.isEmpty ? null : selectedGericht,
                    isExpanded: true,
                    hint: Text('Bitte ${gerichtTyp == "betreuungsgericht" ? "Betreuungsgericht" : gerichtTyp == "sozialgericht" ? "Sozialgericht" : "Arbeitsgericht"} ausw\u00E4hlen...', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                    icon: Icon(Icons.gavel, color: themeColor.shade600),
                    items: gerichtListe.map((g) => DropdownMenuItem(
                      value: g['name'],
                      child: Row(children: [
                        Icon(Icons.account_balance, size: 16, color: themeColor.shade600),
                        const SizedBox(width: 8),
                        Text(g['name']!, style: const TextStyle(fontSize: 13)),
                      ]),
                    )).toList(),
                    onChanged: (val) => setLocalState(() {
                      selectedGericht = val ?? '';
                      
                      data['gericht_name'] = selectedGericht;
                    }),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Info card for selected Gericht
              if (selected != null) ...[
                Card(
                  elevation: 0,
                  color: themeColor.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(gerichtTyp == 'betreuungsgericht' ? Icons.family_restroom : gerichtTyp == 'sozialgericht' ? Icons.health_and_safety : Icons.work, size: 18, color: themeColor.shade700),
                          const SizedBox(width: 8),
                          Expanded(child: Text(selected['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: themeColor.shade700))),
                        ]),
                        const Divider(height: 16),
                        _gerichtInfoRow(Icons.location_on, 'Adresse', selected['adresse'] ?? ''),
                        const SizedBox(height: 6),
                        _gerichtInfoRow(Icons.phone, 'Telefon', selected['telefon'] ?? ''),
                        const SizedBox(height: 6),
                        if ((selected['fax'] ?? '').isNotEmpty) ...[
                          _gerichtInfoRow(Icons.fax, 'Telefax', selected['fax']!),
                          const SizedBox(height: 6),
                        ],
                        if ((selected['email'] ?? '').isNotEmpty) ...[
                          _gerichtInfoRow(Icons.email, 'E-Mail', selected['email']!),
                          const SizedBox(height: 6),
                        ],
                        _gerichtInfoRow(Icons.access_time, 'Öffnungszeiten', selected['oeffnungszeiten'] ?? ''),
                        const SizedBox(height: 6),
                        _gerichtInfoRow(Icons.info_outline, 'Zuständigkeit', selected['zustaendigkeit'] ?? ''),
                        if ((selected['hinweis'] ?? '').isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade200)),
                            child: Row(children: [
                              Icon(Icons.warning_amber, size: 14, color: Colors.amber.shade800),
                              const SizedBox(width: 6),
                              Expanded(child: Text(selected['hinweis']!, style: TextStyle(fontSize: 10, color: Colors.amber.shade900))),
                            ]),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // ═══ BERATUNGSHILFE SECTION ═══
              const Divider(height: 32),
              Row(children: [
                Icon(Icons.gavel, size: 18, color: Colors.indigo.shade700),
                const SizedBox(width: 8),
                Text('Beratungshilfe (Amtsgericht)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                const Spacer(),
              ]),
              const SizedBox(height: 8),
              Card(elevation: 0, color: Colors.indigo.shade50, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.account_balance, size: 16, color: Colors.indigo.shade700), const SizedBox(width: 8),
                    Text('Amtsgericht Neu-Ulm \u2013 Beratungshilfe', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                  ]),
                  const Divider(height: 16),
                  _gerichtInfoRow(Icons.location_on, 'Adresse', 'Sch\u00FCtzenstra\u00DFe 60, 89231 Neu-Ulm'),
                  const SizedBox(height: 4),
                  _gerichtInfoRow(Icons.phone, 'Telefon', '0731 / 70793-214'),
                  const SizedBox(height: 4),
                  _gerichtInfoRow(Icons.email, 'E-Mail', 'zivilabteilung@ag-nu.bayern.de'),
                  const SizedBox(height: 4),
                  _gerichtInfoRow(Icons.access_time, '\u00D6ffnungszeiten', 'Mo\u2013Fr 08:00\u201312:00 (sp\u00E4testens 11:30 erscheinen)'),
                  const SizedBox(height: 4),
                  _gerichtInfoRow(Icons.euro, 'Geb\u00FChr', '15,00 \u20AC (Beratungsperson kann darauf verzichten)'),
                  const SizedBox(height: 8),
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade200)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, size: 14, color: Colors.amber.shade800), const SizedBox(width: 6),
                      Expanded(child: Text('Antrag kann m\u00FCndlich oder schriftlich gestellt werden. Bei direktem Gang zum Anwalt muss der Antrag binnen 4 Wochen beim Amtsgericht eingehen.',
                        style: TextStyle(fontSize: 10, color: Colors.amber.shade900))),
                    ]),
                  ),
                ])),
              ),

              // ═══ ANTRÄGE SECTION ═══
              const Divider(height: 32),
              Row(children: [
                Icon(Icons.description, size: 18, color: themeColor.shade700),
                const SizedBox(width: 8),
                Text('Antr\u00E4ge', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: themeColor.shade700)),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Neuer Antrag', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(foregroundColor: themeColor.shade700),
                  onPressed: () {
                    _showNewGerichtAntragDialog(context, data, gerichtTyp, setLocalState);
                  },
                ),
              ]),
              const SizedBox(height: 8),

              // Anträge list
              if ((data['antraege'] as List?)?.isEmpty ?? true)
                Card(
                  elevation: 0,
                  color: Colors.grey.shade50,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(child: Column(children: [
                      Icon(Icons.inbox, size: 32, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('Keine Anträge vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                      const SizedBox(height: 4),
                      Text('Klicken Sie auf "Neuer Antrag" um einen Antrag zu erstellen', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                    ])),
                  ),
                )
              else
                ...List.generate((data['antraege'] as List).length, (idx) {
                  final antrag = (data['antraege'] as List)[idx] as Map<String, dynamic>;
                  final statusColor = antrag['status'] == 'offen' ? Colors.orange
                      : antrag['status'] == 'bewilligt' ? Colors.green
                      : antrag['status'] == 'abgelehnt' ? Colors.red
                      : antrag['status'] == 'in_bearbeitung' ? Colors.blue
                      : antrag['status'] == 'warten_gericht' ? Colors.indigo
                      : antrag['status'] == 'warten_kunde' ? Colors.teal
                      : Colors.grey;
                  final statusLabel = {
                    'offen': 'Offen', 'in_bearbeitung': 'In Bearbeitung',
                    'warten_gericht': 'Warten auf Antwort vom Gericht',
                    'warten_kunde': 'Warten auf Antwort vom Kunden',
                    'bewilligt': 'Bewilligt', 'abgelehnt': 'Abgelehnt', 'erledigt': 'Erledigt',
                  }[antrag['status']] ?? 'Offen';

                  return Card(
                    elevation: 0,
                    margin: const EdgeInsets.only(bottom: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: themeColor.shade100)),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        _showGerichtAntragDialog(context, data, idx, gerichtTyp, setLocalState);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(children: [
                          Icon(Icons.description, size: 20, color: themeColor.shade400),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                (antrag['titel'] as String?)?.isNotEmpty == true ? antrag['titel'] : 'Antrag ${idx + 1}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Row(children: [
                                if ((antrag['aktenzeichen'] as String?)?.isNotEmpty == true) ...[
                                  Icon(Icons.folder, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 3),
                                  Text(antrag['aktenzeichen'], style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  const SizedBox(width: 10),
                                ],
                                if ((antrag['datum'] as String?)?.isNotEmpty == true) ...[
                                  Icon(Icons.event, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 3),
                                  Text(antrag['datum'], style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                ],
                              ]),
                            ],
                          )),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
                            child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
                          ),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                        ]),
                      ),
                    ),
                  );
                }),
            ],
          ),
        );
      },
    );
  }

  List<String> _getAntragTypen(String gerichtTyp) {
    switch (gerichtTyp) {
      case 'betreuungsgericht':
        return ['Antrag auf Betreuungsverfahren', 'Antrag auf Aufhebung der Betreuung', 'Antrag auf Betreuerwechsel', 'Antrag auf Erweiterung der Betreuung', 'Antrag auf Einschränkung der Betreuung', 'Eilantrag / Vorläufige Betreuung', 'Sonstiges'];
      case 'sozialgericht':
        return ['Klage gegen Jobcenter-Bescheid', 'Klage gegen Krankenkasse', 'Klage Schwerbehindertenrecht', 'Klage Rentenversicherung', 'Eilantrag / Einstweiliger Rechtsschutz', 'Widerspruchsverfahren', 'Sonstiges'];
      default:
        return ['K\u00FCndigungsschutzklage', 'Lohnklage', 'Zeugnisklage', 'Antrag auf einstweilige Verf\u00FCgung', 'G\u00FCteverhandlung', 'Sonstiges'];
    }
  }

  Widget _buildAntragFormFields(String gerichtTyp, MaterialColor themeColor, {
    required TextEditingController titelController,
    required TextEditingController datumController,
    required TextEditingController aktenzeichenController,
    required TextEditingController sachbearbeiterController,
    required TextEditingController sachbearbeiterTelController,
    required TextEditingController sachbearbeiterEmailController,
    required TextEditingController notizenController,
    required String status,
    required void Function(String) onStatusChanged,
    required void Function(void Function()) setDState,
    required BuildContext dialogCtx,
    bool readOnly = false,
  }) {
    final antragTypen = _getAntragTypen(gerichtTyp);
    final statusMap = {'offen': 'Offen', 'in_bearbeitung': 'In Bearbeitung', 'warten_gericht': 'Warten auf Antwort vom Gericht', 'warten_kunde': 'Warten auf Antwort vom Kunden', 'bewilligt': 'Bewilligt', 'abgelehnt': 'Abgelehnt', 'erledigt': 'Erledigt'};
    final statusColorMap = {'offen': Colors.orange, 'in_bearbeitung': Colors.blue, 'warten_gericht': Colors.indigo, 'warten_kunde': Colors.teal, 'bewilligt': Colors.green, 'abgelehnt': Colors.red, 'erledigt': Colors.grey};

    if (readOnly) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _readOnlyField(Icons.description, 'Art des Antrags', titelController.text, themeColor),
          _readOnlyField(Icons.event, 'Datum', datumController.text, themeColor),
          _readOnlyField(Icons.folder, 'Aktenzeichen', aktenzeichenController.text, themeColor),
          const SizedBox(height: 10),
          Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: (statusColorMap[status] ?? Colors.grey).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(statusMap[status] ?? status, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: statusColorMap[status] ?? Colors.grey)),
          ),
          const SizedBox(height: 10),
          _readOnlyField(Icons.person, 'Sachbearbeiter/in', sachbearbeiterController.text, themeColor),
          _readOnlyField(Icons.phone, 'Telefon', sachbearbeiterTelController.text, themeColor),
          _readOnlyField(Icons.email, 'E-Mail', sachbearbeiterEmailController.text, themeColor),
          _readOnlyField(Icons.notes, 'Notizen', notizenController.text, themeColor),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Art des Antrags *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(border: Border.all(color: themeColor.shade200), borderRadius: BorderRadius.circular(8)),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: titelController.text.isEmpty ? null : (antragTypen.contains(titelController.text) ? titelController.text : null),
              isExpanded: true,
              hint: const Text('Bitte auswählen...', style: TextStyle(fontSize: 13)),
              items: antragTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (val) => setDState(() => titelController.text = val ?? ''),
            ),
          ),
        ),
        if (titelController.text.isEmpty || !antragTypen.contains(titelController.text)) ...[
          const SizedBox(height: 8),
          TextField(controller: titelController, decoration: InputDecoration(hintText: 'Oder Titel manuell eingeben', prefixIcon: const Icon(Icons.edit, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true)),
        ],
        const SizedBox(height: 14),
        Text('Datum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(
          controller: datumController, readOnly: true,
          decoration: InputDecoration(
            prefixIcon: Icon(Icons.event, size: 18, color: themeColor.shade400),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true,
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 16), onPressed: () async {
              final picked = await showDatePicker(context: dialogCtx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (picked != null) setDState(() => datumController.text = DateFormat('dd.MM.yyyy').format(picked));
            }),
          ),
        ),
        const SizedBox(height: 14),
        Text('Aktenzeichen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: aktenzeichenController, decoration: InputDecoration(hintText: 'Aktenzeichen des Verfahrens', prefixIcon: const Icon(Icons.folder, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true)),
        const SizedBox(height: 14),
        Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in [('offen', 'Offen', Colors.orange), ('in_bearbeitung', 'In Bearbeitung', Colors.blue), ('warten_gericht', 'Warten Antwort Gericht', Colors.indigo), ('warten_kunde', 'Warten Antwort Kunde', Colors.teal), ('bewilligt', 'Bewilligt', Colors.green), ('abgelehnt', 'Abgelehnt', Colors.red), ('erledigt', 'Erledigt', Colors.grey)])
            ChoiceChip(label: Text(s.$2, style: TextStyle(fontSize: 11, color: status == s.$1 ? Colors.white : Colors.black87)), selected: status == s.$1, selectedColor: s.$3, onSelected: (_) { onStatusChanged(s.$1); setDState(() {}); }),
        ]),
        const SizedBox(height: 14),
        Text('Sachbearbeiter/in / Richter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: sachbearbeiterController, decoration: InputDecoration(hintText: 'Name', prefixIcon: const Icon(Icons.person, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: sachbearbeiterTelController, decoration: InputDecoration(hintText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: sachbearbeiterEmailController, decoration: InputDecoration(hintText: 'E-Mail', prefixIcon: const Icon(Icons.email, size: 16), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true))),
        ]),
        const SizedBox(height: 14),
        Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(controller: notizenController, maxLines: 3, decoration: InputDecoration(hintText: 'Weitere Informationen...', border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), isDense: true)),
      ],
    );
  }

  Widget _readOnlyField(IconData icon, String label, String value, MaterialColor themeColor) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: themeColor.shade400),
          const SizedBox(width: 10),
          SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Map<String, dynamic> _collectAntragData(String? existingId, {
    required TextEditingController titelController,
    required TextEditingController aktenzeichenController,
    required TextEditingController sachbearbeiterController,
    required TextEditingController sachbearbeiterTelController,
    required TextEditingController sachbearbeiterEmailController,
    required TextEditingController datumController,
    required TextEditingController notizenController,
    required String status,
  }) {
    return {
      'id': existingId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      'titel': titelController.text.trim(),
      'aktenzeichen': aktenzeichenController.text.trim(),
      'sachbearbeiter': sachbearbeiterController.text.trim(),
      'sachbearbeiter_tel': sachbearbeiterTelController.text.trim(),
      'sachbearbeiter_email': sachbearbeiterEmailController.text.trim(),
      'status': status,
      'datum': datumController.text.trim(),
      'notizen': notizenController.text.trim(),
    };
  }

  /// NEW ANTRAG — opens form dialog, saves on Speichern
  void _showNewGerichtAntragDialog(BuildContext ctx, Map<String, dynamic> data, String gerichtTyp, void Function(void Function()) setParentState) {
    final themeColor = gerichtTyp == 'betreuungsgericht' ? Colors.deepPurple : gerichtTyp == 'sozialgericht' ? Colors.teal : Colors.orange;
    final titelC = TextEditingController();
    final aktenC = TextEditingController();
    final sachC = TextEditingController();
    final sachTelC = TextEditingController();
    final sachEmailC = TextEditingController();
    final datumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    final notizC = TextEditingController();
    String status = 'offen';

    showDialog(
      context: ctx,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx2, setDState) => AlertDialog(
          titlePadding: EdgeInsets.zero,
          title: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            decoration: BoxDecoration(color: themeColor.shade50, borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28))),
            child: Row(children: [
              Icon(Icons.add_circle, size: 20, color: themeColor.shade700),
              const SizedBox(width: 8),
              Text('Neuer Antrag', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: themeColor.shade700)),
              const Spacer(),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dCtx)),
            ]),
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: _buildAntragFormFields(gerichtTyp, themeColor,
                titelController: titelC, datumController: datumC, aktenzeichenController: aktenC,
                sachbearbeiterController: sachC, sachbearbeiterTelController: sachTelC, sachbearbeiterEmailController: sachEmailC,
                notizenController: notizC, status: status, onStatusChanged: (s) => status = s, setDState: setDState, dialogCtx: dCtx2),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Erstellen'),
              style: FilledButton.styleFrom(backgroundColor: themeColor.shade600),
              onPressed: () {
                if (titelC.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Bitte Art des Antrags ausw\u00E4hlen'), backgroundColor: Colors.orange));
                  return;
                }
                final newAntrag = _collectAntragData(null, titelController: titelC, aktenzeichenController: aktenC, sachbearbeiterController: sachC, sachbearbeiterTelController: sachTelC, sachbearbeiterEmailController: sachEmailC, datumController: datumC, notizenController: notizC, status: status);
                newAntrag['korrespondenz'] = [];
                final antraege = List<Map<String, dynamic>>.from(data['antraege'] ?? []);
                antraege.add(newAntrag);
                data['antraege'] = antraege;
                widget.saveData(type, data);
                Navigator.pop(dCtx);
                setParentState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  /// EXISTING ANTRAG — 2 tabs: Details + Korrespondenz
  void _showGerichtAntragDialog(BuildContext ctx, Map<String, dynamic> data, int idx, String gerichtTyp, void Function(void Function()) setParentState) {
    final antrag = (data['antraege'] as List)[idx] as Map<String, dynamic>;
    final themeColor = gerichtTyp == 'betreuungsgericht' ? Colors.deepPurple : gerichtTyp == 'sozialgericht' ? Colors.teal : Colors.orange;

    final titelC = TextEditingController(text: antrag['titel'] ?? '');
    final aktenC = TextEditingController(text: antrag['aktenzeichen'] ?? '');
    final sachC = TextEditingController(text: antrag['sachbearbeiter'] ?? '');
    final sachTelC = TextEditingController(text: antrag['sachbearbeiter_tel'] ?? '');
    final sachEmailC = TextEditingController(text: antrag['sachbearbeiter_email'] ?? '');
    final datumC = TextEditingController(text: antrag['datum'] ?? '');
    final notizC = TextEditingController(text: antrag['notizen'] ?? '');
    String status = antrag['status'] ?? 'offen';
    bool isEditing = false;

    showDialog(
      context: ctx,
      builder: (dCtx) {
        return StatefulBuilder(
          builder: (dCtx2, setDState) {
            final korrespondenz = List<Map<String, dynamic>>.from(antrag['korrespondenz'] ?? []);

            return DefaultTabController(
              length: 3,
              child: AlertDialog(
                titlePadding: EdgeInsets.zero,
                contentPadding: EdgeInsets.zero,
                title: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                      decoration: BoxDecoration(color: themeColor.shade50, borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28))),
                      child: Row(children: [
                        Icon(Icons.description, size: 20, color: themeColor.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Text(antrag['titel'] ?? 'Antrag', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: themeColor.shade700))),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                          tooltip: 'Antrag löschen',
                          onPressed: () {
                            (data['antraege'] as List).removeAt(idx);
                            widget.saveData(type, data);
                            Navigator.pop(dCtx);
                            setParentState(() {});
                          },
                        ),
                        IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dCtx)),
                      ]),
                    ),
                    TabBar(
                      labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      unselectedLabelStyle: const TextStyle(fontSize: 12),
                      tabs: [
                        const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                        Tab(icon: Badge(
                          isLabelVisible: korrespondenz.isNotEmpty,
                          label: Text('${korrespondenz.length}', style: const TextStyle(fontSize: 9)),
                          child: const Icon(Icons.swap_vert, size: 16),
                        ), text: 'Korrespondenz'),
                        Tab(icon: Badge(
                          isLabelVisible: (antrag['dokumente'] as List?)?.isNotEmpty == true,
                          label: Text('${(antrag['dokumente'] as List?)?.length ?? 0}', style: const TextStyle(fontSize: 9)),
                          child: const Icon(Icons.folder, size: 16),
                        ), text: 'Dokumente'),
                      ],
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 540,
                  height: 450,
                  child: TabBarView(
                    children: [
                      // ── TAB 1: DETAILS ──
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (!isEditing) ...[
                              // Read-only view
                              _buildAntragFormFields(gerichtTyp, themeColor,
                                titelController: titelC, datumController: datumC, aktenzeichenController: aktenC,
                                sachbearbeiterController: sachC, sachbearbeiterTelController: sachTelC, sachbearbeiterEmailController: sachEmailC,
                                notizenController: notizC, status: status, onStatusChanged: (s) => status = s, setDState: setDState, dialogCtx: dCtx2, readOnly: true),
                              const SizedBox(height: 20),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.edit, size: 16),
                                  label: const Text('Bearbeiten'),
                                  style: OutlinedButton.styleFrom(foregroundColor: themeColor.shade700, side: BorderSide(color: themeColor.shade300)),
                                  onPressed: () => setDState(() => isEditing = true),
                                ),
                              ),
                            ] else ...[
                              // Edit mode
                              _buildAntragFormFields(gerichtTyp, themeColor,
                                titelController: titelC, datumController: datumC, aktenzeichenController: aktenC,
                                sachbearbeiterController: sachC, sachbearbeiterTelController: sachTelC, sachbearbeiterEmailController: sachEmailC,
                                notizenController: notizC, status: status, onStatusChanged: (s) => status = s, setDState: setDState, dialogCtx: dCtx2),
                              const SizedBox(height: 20),
                              Row(children: [
                                Expanded(
                                  child: OutlinedButton(
                                    onPressed: () => setDState(() => isEditing = false),
                                    style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade700),
                                    child: const Text('Abbrechen'),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: FilledButton.icon(
                                    icon: const Icon(Icons.save, size: 16),
                                    label: const Text('Speichern'),
                                    style: FilledButton.styleFrom(backgroundColor: themeColor.shade600),
                                    onPressed: () {
                                      final updated = _collectAntragData(antrag['id']?.toString(), titelController: titelC, aktenzeichenController: aktenC, sachbearbeiterController: sachC, sachbearbeiterTelController: sachTelC, sachbearbeiterEmailController: sachEmailC, datumController: datumC, notizenController: notizC, status: status);
                                      updated['korrespondenz'] = korrespondenz;
                                      (data['antraege'] as List)[idx] = updated;
                                      widget.saveData(type, data);
                                      setParentState(() {});
                                      setDState(() => isEditing = false);
                                      ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Antrag gespeichert'), backgroundColor: Colors.green));
                                    },
                                  ),
                                ),
                              ]),
                            ],
                          ],
                        ),
                      ),
                      // ── TAB 2: KORRESPONDENZ ──
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(children: [
                              Text('Korrespondenz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: themeColor.shade700)),
                              const Spacer(),
                              TextButton.icon(
                                icon: const Icon(Icons.add, size: 14),
                                label: const Text('Neu', style: TextStyle(fontSize: 11)),
                                style: TextButton.styleFrom(foregroundColor: themeColor.shade700),
                                onPressed: () {
                                  korrespondenz.insert(0, {
                                    'datum': DateFormat('dd.MM.yyyy').format(DateTime.now()),
                                    'richtung': 'eingang',
                                    'versandart': 'postalisch',
                                    'betreff': '',
                                    'notiz': '',
                                    '_isNew': true,
                                  });
                                  antrag['korrespondenz'] = korrespondenz;
                                  setDState(() {});
                                },
                              ),
                            ]),
                            const Divider(height: 8),
                            Expanded(
                              child: korrespondenz.isEmpty
                                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                      Icon(Icons.inbox, size: 32, color: Colors.grey.shade300),
                                      const SizedBox(height: 8),
                                      Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                    ]))
                                  : ListView.builder(
                                      itemCount: korrespondenz.length,
                                      itemBuilder: (_, ki) {
                                        final k = korrespondenz[ki];
                                        final isEingang = k['richtung'] == 'eingang';
                                        return _buildKorrespondenzTile(k, ki, korrespondenz, antrag, data, type, themeColor, isEingang, setDState, setParentState);
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                      // ── TAB 3: DOKUMENTE (server upload) ──
                      _GerichtDokumenteTab(
                        apiService: widget.apiService,
                        userId: widget.user.id,
                        antragId: antrag['id']?.toString() ?? '',
                        themeColor: themeColor,
                        antrag: antrag,
                        onSave: () {
                          widget.saveData(type, data);
                          setDState(() {});
                          setParentState(() {});
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }


  Widget _buildKorrespondenzTile(Map<String, dynamic> k, int ki, List<Map<String, dynamic>> korrespondenz, Map<String, dynamic> antrag, Map<String, dynamic> data, String type, MaterialColor themeColor, bool isEingang, void Function(void Function()) setDState, void Function(void Function()) setParentState) {
    const methods = {'postalisch': ('Postalisch', Icons.local_post_office), 'online': ('Online', Icons.language), 'email': ('E-Mail', Icons.email), 'persoenlich': ('Persönlich', Icons.person)};
    final richtungLabel = (k['richtung'] == 'ausgang') ? 'Ausgang' : 'Eingang';
    final versandart = k['versandart'] ?? 'postalisch';
    final mc = methods[versandart] ?? methods['postalisch']!;
    final isNew = k['_isNew'] == true;

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: isEingang ? Colors.blue.shade100 : Colors.green.shade100)),
      child: ExpansionTile(
        initiallyExpanded: isNew,
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        leading: Icon(isEingang ? Icons.call_received : Icons.call_made, size: 16, color: isEingang ? Colors.blue.shade700 : Colors.green.shade700),
        title: Text(
          (k['betreff'] as String?)?.isNotEmpty == true ? k['betreff'] : 'Eintrag ${ki + 1}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        subtitle: Row(children: [
          Text(k['datum'] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
          const SizedBox(width: 8),
          Icon(mc.$2, size: 12, color: Colors.grey.shade500),
          const SizedBox(width: 3),
          Text(mc.$1, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ]),
        children: isNew
            ? _buildKorrespondenzEditFields(k, ki, korrespondenz, antrag, data, type, themeColor, methods, setDState, setParentState)
            : [
                // ── READ-ONLY VIEW ──
                if ((k['datum'] as String?)?.isNotEmpty == true)
                  _korrespondenzInfoRow(Icons.event, 'Datum', k['datum']),
                _korrespondenzInfoRow(isEingang ? Icons.call_received : Icons.call_made, 'Richtung', richtungLabel),
                _korrespondenzInfoRow(mc.$2, 'Versandart', mc.$1),
                if ((k['betreff'] as String?)?.isNotEmpty == true)
                  _korrespondenzInfoRow(Icons.subject, 'Betreff', k['betreff']),
                if ((k['notiz'] as String?)?.isNotEmpty == true)
                  _korrespondenzInfoRow(Icons.notes, 'Notiz', k['notiz']),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.edit, size: 14),
                      label: const Text('Bearbeiten', style: TextStyle(fontSize: 11)),
                      style: OutlinedButton.styleFrom(foregroundColor: themeColor.shade700, side: BorderSide(color: themeColor.shade200), padding: const EdgeInsets.symmetric(vertical: 6)),
                      onPressed: () {
                        k['_editing'] = true;
                        setDState(() {});
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                    tooltip: 'Löschen',
                    onPressed: () {
                      korrespondenz.removeAt(ki);
                      antrag['korrespondenz'] = korrespondenz;
                      widget.saveData(type, data);
                      setDState(() {});
                      setParentState(() {});
                    },
                  ),
                ]),
                // ── EDIT VIEW (shown when _editing == true) ──
                if (k['_editing'] == true) ...[
                  const Divider(height: 16),
                  ..._buildKorrespondenzEditFields(k, ki, korrespondenz, antrag, data, type, themeColor, methods, setDState, setParentState),
                ],
              ],
      ),
    );
  }

  Widget _korrespondenzInfoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  List<Widget> _buildKorrespondenzEditFields(Map<String, dynamic> k, int ki, List<Map<String, dynamic>> korrespondenz, Map<String, dynamic> antrag, Map<String, dynamic> data, String type, MaterialColor themeColor, Map<String, (String, IconData)> methods, void Function(void Function()) setDState, void Function(void Function()) setParentState) {
    final betreffC = TextEditingController(text: k['betreff'] ?? '');
    final notizC = TextEditingController(text: k['notiz'] ?? '');
    final datumC = TextEditingController(text: k['datum'] ?? '');
    String richtung = k['richtung'] ?? 'eingang';
    String versandart = k['versandart'] ?? 'postalisch';

    return [
      // Richtung
      Row(children: [
        Expanded(child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_received, size: 12, color: richtung == 'eingang' ? Colors.white : Colors.blue), const SizedBox(width: 4), Text('Eingang', style: TextStyle(fontSize: 10, color: richtung == 'eingang' ? Colors.white : Colors.black87))]),
          selected: richtung == 'eingang', selectedColor: Colors.blue.shade700,
          onSelected: (_) { richtung = 'eingang'; k['richtung'] = richtung; setDState(() {}); },
        )),
        const SizedBox(width: 6),
        Expanded(child: ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_made, size: 12, color: richtung == 'ausgang' ? Colors.white : Colors.green), const SizedBox(width: 4), Text('Ausgang', style: TextStyle(fontSize: 10, color: richtung == 'ausgang' ? Colors.white : Colors.black87))]),
          selected: richtung == 'ausgang', selectedColor: Colors.green.shade700,
          onSelected: (_) { richtung = 'ausgang'; k['richtung'] = richtung; setDState(() {}); },
        )),
      ]),
      const SizedBox(height: 8),
      // Versandart
      Wrap(spacing: 4, runSpacing: 4, children: methods.entries.map((e) => ChoiceChip(
        label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(e.value.$2, size: 12, color: versandart == e.key ? Colors.white : Colors.grey.shade700), const SizedBox(width: 3), Text(e.value.$1, style: TextStyle(fontSize: 9, color: versandart == e.key ? Colors.white : Colors.black87))]),
        selected: versandart == e.key, selectedColor: themeColor.shade600,
        onSelected: (_) { versandart = e.key; k['versandart'] = versandart; setDState(() {}); },
      )).toList()),
      const SizedBox(height: 8),
      TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.event, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (p != null) { datumC.text = DateFormat('dd.MM.yyyy').format(p); k['datum'] = datumC.text; } }))),
      const SizedBox(height: 8),
      TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', prefixIcon: const Icon(Icons.subject, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: (v) => k['betreff'] = v),
      const SizedBox(height: 8),
      TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onChanged: (v) => k['notiz'] = v),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: FilledButton.icon(
          icon: const Icon(Icons.save, size: 14),
          label: const Text('Speichern', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: themeColor.shade600, padding: const EdgeInsets.symmetric(vertical: 6)),
          onPressed: () {
            k['datum'] = datumC.text;
            k['betreff'] = betreffC.text;
            k['notiz'] = notizC.text;
            k['richtung'] = richtung;
            k['versandart'] = versandart;
            k.remove('_isNew');
            k.remove('_editing');
            antrag['korrespondenz'] = korrespondenz;
            widget.saveData(type, data);
            setDState(() {});
            setParentState(() {});
          },
        )),
        const SizedBox(width: 8),
        IconButton(
          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
          tooltip: 'Löschen',
          onPressed: () {
            korrespondenz.removeAt(ki);
            antrag['korrespondenz'] = korrespondenz;
            widget.saveData(type, data);
            setDState(() {});
            setParentState(() {});
          },
        ),
      ]),
    ];
  }

}

/// Separate StatefulWidget for Gericht Antrag Dokumente tab (server upload/download)
class _GerichtDokumenteTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String antragId;
  final MaterialColor themeColor;
  final Map<String, dynamic> antrag;
  final VoidCallback onSave;

  const _GerichtDokumenteTab({required this.apiService, required this.userId, required this.antragId, required this.themeColor, required this.antrag, required this.onSave});

  @override
  State<_GerichtDokumenteTab> createState() => _GerichtDokumenteTabState();
}

class _GerichtDokumenteTabState extends State<_GerichtDokumenteTab> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = true;
  bool _uploading = false;

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => _loading = true);
    try {
      final result = await widget.apiService.listGerichtDokumente(widget.userId, widget.antragId);
      if (mounted && result['success'] == true) {
        _docs = List<Map<String, dynamic>>.from(result['dokumente'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _upload() async {
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      allowMultiple: true,
      dialogTitle: 'Dokumente hochladen (max 20)',
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.where((f) => f.path != null).take(20).map((f) => f.path!).toList();
    if (paths.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final uploadResult = await widget.apiService.uploadGerichtDokumente(widget.userId, widget.antragId, paths);
      if (mounted) {
        final count = (uploadResult['uploaded'] as List?)?.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count Dokument(e) hochgeladen'), backgroundColor: Colors.green));
        _loadDocs();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _viewDoc(Map<String, dynamic> doc) async {
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    final response = await widget.apiService.downloadGerichtDokument(docId);
    if (response == null || !mounted) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${doc['original_name']}';
      await File(filePath).writeAsBytes(response.bodyBytes);
      if (mounted) await FileViewerDialog.show(context, filePath, doc['original_name']);
    } catch (_) {}
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument l\u00F6schen?'),
      content: Text('"${doc['original_name']}" wirklich l\u00F6schen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('L\u00F6schen')),
      ],
    ));
    if (confirmed != true) return;
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    await widget.apiService.deleteGerichtDokument(widget.userId, docId);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gel\u00F6scht'), backgroundColor: Colors.green)); _loadDocs(); }
  }

  String _formatDate(String? d) {
    if (d == null || d.isEmpty) return '-';
    try { final dt = DateTime.parse(d); return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}'; } catch (_) { return d; }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return Padding(padding: const EdgeInsets.all(16), child: Column(children: [
      // Erforderliche Unterlagen checklist
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.checklist, size: 14, color: Colors.indigo.shade700), const SizedBox(width: 6),
            Text('Erforderliche Unterlagen', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          ]),
          ...[
            {'key': 'bh_jobcenter_bescheid', 'label': 'Jobcenter-Bescheid / Sozialamt-Bescheid', 'icon': Icons.account_balance_wallet},
            {'key': 'bh_lohnabrechnungen', 'label': '3 Lohnabrechnungen (falls erwerbst\u00E4tig)', 'icon': Icons.receipt},
            {'key': 'bh_kontoauszuege', 'label': 'Kontoausz\u00FCge der letzten 3 Monate', 'icon': Icons.account_balance},
            {'key': 'bh_mietvertrag', 'label': 'Mietvertrag / Mietbescheinigung', 'icon': Icons.home},
          ].map((task) {
            final checked = widget.antrag['${task['key']}'] == true;
            return CheckboxListTile(
              value: checked, dense: true, contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading, visualDensity: VisualDensity.compact,
              secondary: Icon(task['icon'] as IconData, size: 14, color: checked ? Colors.green : Colors.grey.shade400),
              title: Text(task['label'] as String, style: TextStyle(fontSize: 10, decoration: checked ? TextDecoration.lineThrough : null, color: checked ? Colors.grey : Colors.black87)),
              onChanged: (val) { setState(() { widget.antrag['${task['key']}'] = val; }); widget.onSave(); },
            );
          }),
        ]),
      ),
      const SizedBox(height: 8),
      Row(children: [
        Text('Dokumente (${_docs.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: widget.themeColor.shade700)),
        const Spacer(),
        ElevatedButton.icon(
          icon: _uploading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file, size: 14),
          label: Text(_uploading ? 'Wird hochgeladen...' : 'Hochladen', style: const TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: widget.themeColor.shade700, foregroundColor: Colors.white),
          onPressed: _uploading ? null : _upload,
        ),
      ]),
      const Divider(height: 12),
      Expanded(child: _docs.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.folder_open, size: 32, color: Colors.grey.shade300), const SizedBox(height: 8),
            Text('Keine Dokumente', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]))
        : ListView.builder(itemCount: _docs.length, itemBuilder: (_, i) {
            final doc = _docs[i];
            final name = doc['original_name'] ?? 'Unbekannt';
            final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
            IconData icon = Icons.insert_drive_file;
            Color color = Colors.grey;
            if (ext == 'pdf') { icon = Icons.picture_as_pdf; color = Colors.red; }
            else if (['jpg', 'jpeg', 'png'].contains(ext)) { icon = Icons.image; color = Colors.blue; }
            else if (['doc', 'docx'].contains(ext)) { icon = Icons.description; color = Colors.indigo; }
            return Card(elevation: 0, margin: const EdgeInsets.only(bottom: 6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: Colors.grey.shade200)),
              child: ListTile(
                leading: Icon(icon, color: color),
                title: Text(name, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                subtitle: Text(_formatDate(doc['created_at']), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                dense: true,
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(icon: Icon(Icons.visibility, size: 16, color: Colors.blue.shade600), tooltip: 'Anzeigen', onPressed: () => _viewDoc(doc)),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), tooltip: 'L\u00F6schen', onPressed: () => _deleteDoc(doc)),
                ]),
              ),
            );
          }),
      ),
    ]));
  }
}
