import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'polizei_vorfall_dialog.dart';

class BehordePolizeiContent extends StatefulWidget {
  final ApiService apiService;
  final String adminMitgliedernummer;
  final String clientMitgliedernummer;
  final int userId;
  final User? user;

  const BehordePolizeiContent({
    super.key,
    required this.apiService,
    required this.adminMitgliedernummer,
    required this.clientMitgliedernummer,
    required this.userId,
    this.user,
  });

  @override
  State<BehordePolizeiContent> createState() => _BehordePolizeiContentState();
}

class _BehordePolizeiContentState extends State<BehordePolizeiContent> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  List<Map<String, dynamic>> _dienststellen = [];
  List<Map<String, dynamic>> _vorfaelle = [];
  Map<String, dynamic>? _polizeiData;
  bool _isLoading = true;

  final _zustaendigController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadAll();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _zustaendigController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);
    await Future.wait([_loadDienststellen(), _loadUserPolizei()]);
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _loadDienststellen() async {
    try {
      _dienststellen = await widget.apiService.getPolizeiDienststellen();
    } catch (_) {}
  }

  Future<void> _loadUserPolizei() async {
    try {
      final result = await widget.apiService.getUserPolizei(widget.userId);
      if (result['success'] == true) {
        _polizeiData = result['polizei'] as Map<String, dynamic>?;
        _vorfaelle = List<Map<String, dynamic>>.from(result['vorfaelle'] ?? []);
        _zustaendigController.text = _polizeiData?['dienststelle_name'] ?? '';
      }
    } catch (_) {}
  }

  Future<void> _saveDienststelle() async {
    final name = _zustaendigController.text.trim();
    final selected = _dienststellen.where((d) => d['name'] == name).toList();
    final dienststelleId = selected.isNotEmpty ? selected.first['id'] as int? : null;

    final result = await widget.apiService.saveUserPolizeiDienststelle(widget.userId, dienststelleId, name);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result['success'] == true ? 'Gespeichert' : 'Fehler'),
        backgroundColor: result['success'] == true ? Colors.green : Colors.red,
      ));
      if (result['success'] == true) _loadUserPolizei().then((_) { if (mounted) setState(() {}); });
    }
  }

  Future<void> _addVorfall() async {
    // Basis-Felder
    final datumC = TextEditingController();
    final beschreibungC = TextEditingController();
    final aktenzeichenC = TextEditingController();
    final sachbearbeiterC = TextEditingController();
    final sachbearbeiterTelC = TextEditingController();
    String selectedTyp = 'owi_geschwindigkeit';

    // Strafanzeige-Felder (nur bei selectedTyp.startsWith('straf_'))
    final datumAnzeigeC = TextEditingController();
    final datumBescheinigungC = TextEditingController();
    final tatortBemerkungC = TextEditingController();
    final tatortPlzC = TextEditingController();
    final tatortOrtC = TextEditingController();
    final tatortStadtteilC = TextEditingController();
    final tatortStrasseC = TextEditingController();
    final tatortFreieC = TextEditingController();
    String? tatzeitWochentag;
    final tatzeitDatumC = TextEditingController();
    final tatzeitStundeC = TextEditingController();
    final tatzeitMinuteC = TextEditingController();
    final deliktC = TextEditingController();

    // Geschädigt — auto-fill aus Verifizierung Stufe 1
    final u = widget.user;
    final geschNameC = TextEditingController(text: u?.nachname ?? '');
    final geschGeburtsnameC = TextEditingController(text: u?.geburtsname ?? '');
    final geschVornameC = TextEditingController(text: u?.vorname ?? '');
    final geschGebDatumC = TextEditingController(text: _formatIsoToDe(u?.geburtsdatum));
    final geschGebOrtC = TextEditingController(text: u?.geburtsort ?? '');
    String? geschGeschlecht = u?.geschlecht;
    final geschStaatC = TextEditingController(text: u?.staatsangehoerigkeit ?? '');
    final geschWohnsitzC = TextEditingController(
      text: [u?.strasse, u?.hausnummer].where((s) => s != null && s.isNotEmpty).join(' ') +
            (u?.plz != null && (u?.plz ?? '').isNotEmpty ? ', ${u?.plz} ${u?.ort ?? ''}' : ''));

    // Folgen — 4 Optionen (zumindest eine aktiv markierbar)
    bool folgenVerletzungen = false;
    final folgenDiebstahlWertC = TextEditingController();
    final folgenBeschaedigungWertC = TextEditingController();
    final folgenSonstigeC = TextEditingController();
    String? sachfahndung;
    String? tatverdaechtige;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final isStraftat = selectedTyp.startsWith('straf_');

          Widget label(String t) => Padding(padding: const EdgeInsets.only(top: 6, bottom: 4),
              child: Text(t, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)));
          Widget sectionHeader(IconData ic, String t, Color c) => Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 6),
              child: Row(children: [
                Icon(ic, size: 16, color: c), const SizedBox(width: 6),
                Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: c)),
              ]));

          Future<void> pickDate(TextEditingController c) async {
            final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(),
                firstDate: DateTime(2000), lastDate: DateTime.now().add(const Duration(days: 30)),
                locale: const Locale('de'));
            if (picked != null) setDialogState(() => c.text = _fmtDe(picked));
          }

          return AlertDialog(
            title: Row(children: [
              Icon(Icons.add_circle, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(isStraftat ? 'Neue Strafanzeige' : 'Neuen Vorfall melden'),
            ]),
            content: SizedBox(
              width: isStraftat ? 720 : 500,
              child: SingleChildScrollView(child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label('Art des Vorfalls'),
                  DropdownButtonFormField<String>(
                    initialValue: selectedTyp, isExpanded: true,
                    decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                    items: _buildVorfallTypItems(),
                    onChanged: (v) {
                      if (v == null) return;
                      setDialogState(() {
                        selectedTyp = v;
                        // Delikt-Default je nach Auswahl
                        if (v == 'straf_koerperverletzung') {
                          deliktC.text = 'Körperverletzung einfach vorsätzlich, § 223 StGB';
                        } else if (v.startsWith('straf_') && deliktC.text.isEmpty) {
                          deliktC.text = _vorfallKategorien[v] ?? '';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      label('Datum'),
                      TextField(controller: datumC, readOnly: true,
                        decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true,
                          hintText: 'TT.MM.JJJJ',
                          suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18),
                            onPressed: () => pickDate(datumC))),
                      ),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      label('Aktenzeichen'),
                      TextField(controller: aktenzeichenC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Az.')),
                    ])),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      label('Sachbearbeiter/in'),
                      TextField(controller: sachbearbeiterC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Name')),
                    ])),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      label('Durchwahl'),
                      TextField(controller: sachbearbeiterTelC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Telefon')),
                    ])),
                  ]),
                  label('Beschreibung'),
                  TextField(controller: beschreibungC, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Was ist passiert?')),

                  // ────────── STRAFTAT-spezifische Felder ──────────
                  if (isStraftat) ...[
                    sectionHeader(Icons.event_note, 'Bescheinigung über die Erstattung einer Strafanzeige', Colors.indigo.shade700),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Datum Anzeigenaufnahme (Polizei)'),
                        TextField(controller: datumAnzeigeC, readOnly: true,
                          decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, hintText: 'TT.MM.JJJJ',
                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () => pickDate(datumAnzeigeC))),
                        ),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Datum Bescheinigung'),
                        TextField(controller: datumBescheinigungC, readOnly: true,
                          decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, hintText: 'TT.MM.JJJJ',
                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () => pickDate(datumBescheinigungC))),
                        ),
                      ])),
                    ]),

                    sectionHeader(Icons.location_on, 'Tatort', Colors.deepOrange.shade700),
                    label('Bemerkung'),
                    TextField(controller: tatortBemerkungC, maxLines: 2,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'z.B. Nähe Eingang Westseite')),
                    Row(children: [
                      Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('PLZ'),
                        TextField(controller: tatortPlzC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '89077')),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Ort'),
                        TextField(controller: tatortOrtC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Ulm')),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Stadtteil'),
                        TextField(controller: tatortStadtteilC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Weststadt')),
                      ])),
                    ]),
                    label('Straße / Hausnr.'),
                    TextField(controller: tatortStrasseC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'Römerstraße 122')),
                    label('Freie Ortsbezeichnung (optional)'),
                    TextField(controller: tatortFreieC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: 'z.B. Parkplatz hinter dem Gebäude')),

                    sectionHeader(Icons.access_time, 'Tatzeit', Colors.deepOrange.shade700),
                    Row(children: [
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Wochentag'),
                        DropdownButtonFormField<String>(
                          initialValue: tatzeitWochentag, isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: const ['Montag','Dienstag','Mittwoch','Donnerstag','Freitag','Samstag','Sonntag']
                              .map((w) => DropdownMenuItem(value: w, child: Text(w, style: const TextStyle(fontSize: 13)))).toList(),
                          onChanged: (v) => setDialogState(() => tatzeitWochentag = v),
                        ),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Datum'),
                        TextField(controller: tatzeitDatumC, readOnly: true,
                          decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, hintText: 'TT.MM.JJJJ',
                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () => pickDate(tatzeitDatumC))),
                        ),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Stunde'),
                        TextField(controller: tatzeitStundeC, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '14')),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Minute'),
                        TextField(controller: tatzeitMinuteC, keyboardType: TextInputType.number,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '30')),
                      ])),
                    ]),

                    sectionHeader(Icons.gavel, 'Delikt', Colors.red.shade700),
                    TextField(controller: deliktC,
                      decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true,
                        hintText: 'z.B. Körperverletzung einfach vorsätzlich, § 223 StGB')),

                    sectionHeader(Icons.person, 'Geschädigte/r (aus Verifizierung Stufe 1)', Colors.green.shade700),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Familienname'),
                        TextField(controller: geschNameC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Geburtsname'),
                        TextField(controller: geschGeburtsnameC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Vorname'),
                        TextField(controller: geschVornameC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      ])),
                    ]),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Geburtsdatum'),
                        TextField(controller: geschGebDatumC, readOnly: true,
                          decoration: InputDecoration(border: const OutlineInputBorder(), isDense: true, hintText: 'TT.MM.JJJJ',
                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18),
                              onPressed: () async {
                                final p = await showDatePicker(context: ctx, initialDate: DateTime(1990),
                                  firstDate: DateTime(1900), lastDate: DateTime.now(), locale: const Locale('de'));
                                if (p != null) setDialogState(() => geschGebDatumC.text = _fmtDe(p));
                              })),
                        ),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Geburtsort / Land'),
                        TextField(controller: geschGebOrtC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Geschlecht'),
                        DropdownButtonFormField<String>(
                          initialValue: geschGeschlecht, isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'm', child: Text('männlich')),
                            DropdownMenuItem(value: 'w', child: Text('weiblich')),
                            DropdownMenuItem(value: 'd', child: Text('divers')),
                          ],
                          onChanged: (v) => setDialogState(() => geschGeschlecht = v),
                        ),
                      ])),
                    ]),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Staatsangehörigkeit'),
                        TextField(controller: geschStaatC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      ])),
                      const SizedBox(width: 8),
                      Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Wohnsitz / Anschrift'),
                        TextField(controller: geschWohnsitzC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),
                      ])),
                    ]),

                    sectionHeader(Icons.fact_check, 'Folgendes wird geltend gemacht', Colors.blue.shade700),
                    CheckboxListTile(
                      dense: true, contentPadding: EdgeInsets.zero,
                      value: folgenVerletzungen, onChanged: (v) => setDialogState(() => folgenVerletzungen = v ?? false),
                      title: const Text('Verletzungen werden geltend gemacht', style: TextStyle(fontSize: 13)),
                    ),
                    Row(children: [
                      const Expanded(flex: 3, child: Text('Diebesgut im Wert von', style: TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: TextField(controller: folgenDiebstahlWertC, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '0.00', suffixText: 'EUR'))),
                      const Expanded(flex: 2, child: Padding(padding: EdgeInsets.only(left: 8), child: Text('wird geltend gemacht', style: TextStyle(fontSize: 12)))),
                    ]),
                    const SizedBox(height: 6),
                    Row(children: [
                      const Expanded(flex: 3, child: Text('Beschädigungen in Höhe von', style: TextStyle(fontSize: 13))),
                      Expanded(flex: 2, child: TextField(controller: folgenBeschaedigungWertC, keyboardType: TextInputType.number,
                        decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true, hintText: '0.00', suffixText: 'EUR'))),
                      const Expanded(flex: 2, child: Padding(padding: EdgeInsets.only(left: 8), child: Text('werden geltend gemacht', style: TextStyle(fontSize: 12)))),
                    ]),
                    label('Sonstige Folgen (Freitext)'),
                    TextField(controller: folgenSonstigeC, decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true)),

                    sectionHeader(Icons.search, 'Ermittlungen', Colors.purple.shade700),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Sachfahndung veranlasst'),
                        DropdownButtonFormField<String>(
                          initialValue: sachfahndung, isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'ja', child: Text('Ja')),
                            DropdownMenuItem(value: 'nein', child: Text('Nein')),
                          ],
                          onChanged: (v) => setDialogState(() => sachfahndung = v),
                        ),
                      ])),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        label('Tatverdächtige'),
                        DropdownButtonFormField<String>(
                          initialValue: tatverdaechtige, isExpanded: true,
                          decoration: const InputDecoration(border: OutlineInputBorder(), isDense: true),
                          items: const [
                            DropdownMenuItem(value: 'bekannt', child: Text('bekannt')),
                            DropdownMenuItem(value: 'nicht_bekannt', child: Text('nicht bekannt')),
                          ],
                          onChanged: (v) => setDialogState(() => tatverdaechtige = v),
                        ),
                      ])),
                    ]),
                    const SizedBox(height: 12),
                    Container(padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text(
                        'Nach Abschluss der Ermittlungen wird die Anzeige unter dem '
                        'Aktenzeichen ${aktenzeichenC.text.isEmpty ? "<Az>" : aktenzeichenC.text} '
                        'der Staatsanwaltschaft Ulm vorgelegt.',
                        style: TextStyle(fontSize: 11, color: Colors.blue.shade900, fontStyle: FontStyle.italic),
                      )),
                  ],
                ],
              )),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18), label: const Text('Melden'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(ctx, {
                  'typ': selectedTyp, 'datum': datumC.text.trim(),
                  'aktenzeichen': aktenzeichenC.text.trim(),
                  'sachbearbeiter': sachbearbeiterC.text.trim(),
                  'sachbearbeiter_telefon': sachbearbeiterTelC.text.trim(),
                  'beschreibung': beschreibungC.text.trim(),
                  if (isStraftat) ...{
                    'datum_anzeigeaufnahme': datumAnzeigeC.text.trim(),
                    'datum_bescheinigung': datumBescheinigungC.text.trim(),
                    'tatort_bemerkung': tatortBemerkungC.text.trim(),
                    'tatort_plz': tatortPlzC.text.trim(),
                    'tatort_ort': tatortOrtC.text.trim(),
                    'tatort_stadtteil': tatortStadtteilC.text.trim(),
                    'tatort_strasse': tatortStrasseC.text.trim(),
                    'tatort_freie_bezeichnung': tatortFreieC.text.trim(),
                    'tatzeit_wochentag': tatzeitWochentag ?? '',
                    'tatzeit_datum': tatzeitDatumC.text.trim(),
                    'tatzeit_stunde': tatzeitStundeC.text.trim(),
                    'tatzeit_minute': tatzeitMinuteC.text.trim(),
                    'delikt': deliktC.text.trim(),
                    'gesch_name': geschNameC.text.trim(),
                    'gesch_geburtsname': geschGeburtsnameC.text.trim(),
                    'gesch_vorname': geschVornameC.text.trim(),
                    'gesch_geburtsdatum': geschGebDatumC.text.trim(),
                    'gesch_geburtsort': geschGebOrtC.text.trim(),
                    'gesch_geschlecht': geschGeschlecht ?? '',
                    'gesch_staatsangehoerigkeit': geschStaatC.text.trim(),
                    'gesch_wohnsitz': geschWohnsitzC.text.trim(),
                    'folgen_verletzungen': folgenVerletzungen ? 1 : 0,
                    'folgen_diebstahl_wert': folgenDiebstahlWertC.text.trim(),
                    'folgen_beschaedigung_wert': folgenBeschaedigungWertC.text.trim(),
                    'folgen_sonstige': folgenSonstigeC.text.trim(),
                    'sachfahndung': sachfahndung ?? '',
                    'tatverdaechtige': tatverdaechtige ?? '',
                    'staatsanwaltschaft': 'Staatsanwaltschaft Ulm',
                  },
                }),
              ),
            ],
          );
        },
      ),
    );

    if (result != null) {
      final apiResult = await widget.apiService.addUserPolizeiVorfall(widget.userId, result);
      if (mounted && apiResult['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vorfall gemeldet'), backgroundColor: Colors.green),
        );
        _loadUserPolizei().then((_) { if (mounted) setState(() {}); });
      }
    }
  }

  static String _fmtDe(DateTime p) =>
      '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';

  static String _formatIsoToDe(String? iso) {
    if (iso == null || iso.isEmpty) return '';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
    return m != null ? '${m.group(3)}.${m.group(2)}.${m.group(1)}' : iso;
  }

  Future<void> _deleteVorfall(int vorfallId) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Vorfall löschen?'),
      content: const Text('Möchten Sie diesen Vorfall wirklich löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          child: const Text('Löschen')),
      ],
    ));
    if (confirmed != true) return;

    final result = await widget.apiService.deleteUserPolizeiVorfall(widget.userId, vorfallId);
    if (mounted && result['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vorfall gelöscht'), backgroundColor: Colors.green),
      );
      _loadUserPolizei().then((_) { if (mounted) setState(() {}); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return Column(children: [
      TabBar(
        controller: _tabCtrl,
        labelColor: Colors.blue.shade800,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: Colors.blue.shade700,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8,
              color: (_polizeiData?['dienststelle_name']?.toString().isNotEmpty ?? false) ? Colors.green : Colors.red),
            const SizedBox(width: 5),
            const Icon(Icons.local_police, size: 16),
            const SizedBox(width: 5),
            const Text('Zuständige Polizeidienststelle'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 5),
            const Icon(Icons.report, size: 16),
            const SizedBox(width: 5),
            Text('Vorfälle${_vorfaelle.isNotEmpty ? ' (${_vorfaelle.length})' : ''}'),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: _buildDienststelleCard()),
              const SizedBox(width: 16),
              Expanded(flex: 1, child: _buildNotfallCard()),
            ]),
          ]),
        ),
        SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: _buildVorfaelleCard(),
        ),
      ])),
    ]);
  }

  static const _vorfallKategorien = {
    // Ordnungswidrigkeiten
    'owi_geschwindigkeit': 'OWi: Geschwindigkeitsüberschreitung',
    'owi_rotlicht': 'OWi: Rotlichtverstoß',
    'owi_handy': 'OWi: Handynutzung am Steuer',
    'owi_parken': 'OWi: Parkverstoß / Halteverbot',
    'owi_alkohol': 'OWi: Alkohol am Steuer (0,5-1,09‰)',
    'owi_drogen_steuer': 'OWi: Drogeneinfluss am Steuer (§24a StVG)',
    'owi_abstand': 'OWi: Abstandsverstoß',
    'owi_ueberholen': 'OWi: Überholverstoß',
    'owi_gurt': 'OWi: Anschnallpflicht / Kindersicherung',
    'owi_vorfahrt': 'OWi: Vorfahrtverletzung',
    'owi_rettungsgasse': 'OWi: Rettungsgasse nicht gebildet',
    'owi_tuev': 'OWi: Fahrzeug ohne gültige HU (TÜV)',
    'owi_fahrrad': 'OWi: Fahrradverstoß',
    'owi_sonstige': 'OWi: Sonstige Ordnungswidrigkeit',
    // Bußgeld mit Fahrverbot
    'bussgeld_fahrverbot_1m': 'Bußgeld + 1 Monat Fahrverbot',
    'bussgeld_fahrverbot_2m': 'Bußgeld + 2 Monate Fahrverbot',
    'bussgeld_fahrverbot_3m': 'Bußgeld + 3 Monate Fahrverbot',
    // Straftaten - Person
    'straf_koerperverletzung': 'Straftat: Körperverletzung (§223 StGB)',
    'straf_gef_koerperverletzung': 'Straftat: Gefährliche Körperverletzung (§224)',
    'straf_bedrohung': 'Straftat: Bedrohung (§241 StGB)',
    'straf_noetigung': 'Straftat: Nötigung (§240 StGB)',
    'straf_beleidigung': 'Straftat: Beleidigung (§185 StGB)',
    'straf_stalking': 'Straftat: Nachstellung/Stalking (§238 StGB)',
    'straf_haeusliche_gewalt': 'Straftat: Häusliche Gewalt',
    // Straftaten - Eigentum
    'straf_diebstahl': 'Straftat: Diebstahl (§242 StGB)',
    'straf_einbruch': 'Straftat: Einbruchsdiebstahl (§244 StGB)',
    'straf_raub': 'Straftat: Raub (§249 StGB)',
    'straf_betrug': 'Straftat: Betrug (§263 StGB)',
    'straf_sachbeschaedigung': 'Straftat: Sachbeschädigung (§303 StGB)',
    'straf_unterschlagung': 'Straftat: Unterschlagung (§246 StGB)',
    'straf_erpressung': 'Straftat: Erpressung (§253 StGB)',
    'straf_urkundenfaelschung': 'Straftat: Urkundenfälschung (§267 StGB)',
    // Straftaten - Verkehr
    'straf_fahrerflucht': 'Straftat: Fahrerflucht (§142 StGB)',
    'straf_trunkenheit': 'Straftat: Trunkenheit im Verkehr (§316 StGB)',
    'straf_ohne_fahrerlaubnis': 'Straftat: Fahren ohne Fahrerlaubnis (§21 StVG)',
    'straf_gefaehrdung_verkehr': 'Straftat: Gefährdung Straßenverkehr (§315c)',
    'straf_rennen': 'Straftat: Verbotenes Kraftfahrzeugrennen (§315d)',
    // Straftaten - Drogen
    'straf_btm_besitz': 'Straftat: Besitz Betäubungsmittel (§29 BtMG)',
    'straf_btm_handel': 'Straftat: Handel Betäubungsmittel (§29 BtMG)',
    'straf_cannabis': 'Straftat: Cannabis über Freigrenze (§34 KCanG)',
    // Straftaten - Sonstige
    'straf_hausfriedensbruch': 'Straftat: Hausfriedensbruch (§123 StGB)',
    'straf_widerstand': 'Straftat: Widerstand gg. Vollstreckungsbeamte (§113)',
    'straf_schwarzfahren': 'Straftat: Erschleichen von Leistungen (§265a)',
    'straf_cybercrime': 'Straftat: Computerbetrug / Cyberkriminalität',
    'straf_brandstiftung': 'Straftat: Brandstiftung (§306 StGB)',
    'straf_sonstige': 'Straftat: Sonstige Straftat',
    // Polizeikontakt ohne Delikt
    'kontakt_zeuge': 'Kontakt: Zeugenbefragung / Vorladung',
    'kontakt_anzeige_erstattet': 'Kontakt: Strafanzeige erstattet (Opfer)',
    'kontakt_beschuldigter': 'Kontakt: Als Beschuldigter geladen',
    'kontakt_verkehrsunfall': 'Kontakt: Verkehrsunfall',
    'kontakt_kontrolle': 'Kontakt: Polizeikontrolle / Identitätsfeststellung',
    'kontakt_durchsuchung': 'Kontakt: Durchsuchung / Razzia',
    'kontakt_festnahme': 'Kontakt: Festnahme / Verhaftung',
    'kontakt_streitschlichtung': 'Kontakt: Streitschlichtung',
    'kontakt_sonstiges': 'Kontakt: Sonstiger Polizeikontakt',
  };

  List<DropdownMenuItem<String>> _buildVorfallTypItems() {
    return _vorfallKategorien.entries.map((e) {
      Color? color;
      if (e.key.startsWith('owi_') || e.key.startsWith('bussgeld_')) color = Colors.orange.shade700;
      if (e.key.startsWith('straf_')) color = Colors.red.shade700;
      if (e.key.startsWith('kontakt_')) color = Colors.blue.shade700;
      return DropdownMenuItem(
        value: e.key,
        child: Text(e.value, style: TextStyle(fontSize: 13, color: color)),
      );
    }).toList();
  }

  Widget _buildDienststelleCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.local_police, color: Colors.blue.shade700, size: 24),
            const SizedBox(width: 8),
            const Text('Zuständige Polizeidienststelle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ]),
          const Divider(height: 24),
          const Text('Dienststelle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Autocomplete<String>(
            initialValue: TextEditingValue(text: _zustaendigController.text),
            optionsBuilder: (v) {
              if (v.text.isEmpty) return _dienststellen.map((d) => d['name'] as String);
              return _dienststellen.map((d) => d['name'] as String)
                  .where((n) => n.toLowerCase().contains(v.text.toLowerCase()));
            },
            onSelected: (s) { _zustaendigController.text = s; setState(() {}); },
            fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
              if (controller.text.isEmpty && _zustaendigController.text.isNotEmpty) controller.text = _zustaendigController.text;
              return TextField(controller: controller, focusNode: focusNode, decoration: const InputDecoration(
                border: OutlineInputBorder(), hintText: 'z.B. Polizeiinspektion Neu-Ulm', isDense: true, prefixIcon: Icon(Icons.search, size: 18),
              ), onChanged: (v) => _zustaendigController.text = v);
            },
          ),
          ..._buildSelectedInfo(),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: ElevatedButton.icon(
            icon: const Icon(Icons.save, size: 18), label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
            onPressed: _saveDienststelle,
          )),
        ]),
      ),
    );
  }

  List<Widget> _buildSelectedInfo() {
    // Try from loaded polizei data first, then from dienststellen list
    Map<String, dynamic>? d;
    if (_polizeiData != null && _polizeiData!['dienststelle_name'] == _zustaendigController.text) {
      d = _polizeiData;
    } else {
      final selected = _dienststellen.where((ds) => ds['name'] == _zustaendigController.text).toList();
      if (selected.isNotEmpty) d = selected.first;
    }
    if (d == null) return [];

    return [
      const SizedBox(height: 12),
      Container(
        width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (d['adresse'] != null) _contactRow(Icons.location_on, '${d['adresse']}, ${d['plz']} ${d['ort']}'),
          if (d['telefon'] != null) _contactRow(Icons.phone, d['telefon']),
          if (d['fax'] != null) _contactRow(Icons.fax, d['fax']),
          if (d['email'] != null) _contactRow(Icons.email, d['email']),
          if (d['oeffnungszeiten'] != null) _contactRow(Icons.access_time, d['oeffnungszeiten']),
          if (d['website'] != null) InkWell(
            onTap: () => launchUrl(Uri.parse(d!['website']), mode: LaunchMode.externalApplication),
            child: _contactRow(Icons.open_in_new, 'Website öffnen'),
          ),
        ]),
      ),
    ];
  }

  Widget _buildNotfallCard() {
    return Card(color: Colors.red.shade50, child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.emergency, color: Colors.red.shade700, size: 24), const SizedBox(width: 8),
          Text('Notruf', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
        ]),
        const SizedBox(height: 16),
        _notrufButton('110', 'Polizei', Icons.local_police),
        const SizedBox(height: 8),
        _notrufButton('112', 'Feuerwehr / Rettung', Icons.local_fire_department),
        const SizedBox(height: 8),
        _notrufButton('0800 1110111', 'Telefonseelsorge', Icons.phone),
      ],
    )));
  }

  Widget _notrufButton(String nr, String label, IconData icon) {
    return SizedBox(width: double.infinity, child: OutlinedButton.icon(
      icon: Icon(icon, color: Colors.red.shade700, size: 18),
      label: Text('$nr - $label', style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.bold, fontSize: 13)),
      style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300), padding: const EdgeInsets.symmetric(vertical: 10)),
      onPressed: () => launchUrl(Uri.parse('tel:$nr')),
    ));
  }

  Widget _buildVorfaelleCard() {
    final typLabels = _vorfallKategorien;

    return Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.report, color: Colors.orange.shade700, size: 24), const SizedBox(width: 8),
          const Expanded(child: Text('Vorfälle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          ElevatedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Vorfall melden'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            onPressed: _addVorfall),
        ]),
        const Divider(height: 24),
        if (_vorfaelle.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(children: [
            Icon(Icons.check_circle, size: 40, color: Colors.green.shade300), const SizedBox(height: 8),
            Text('Keine Vorfälle eingetragen', style: TextStyle(color: Colors.grey.shade500)),
          ])))
        else
          ..._vorfaelle.map((v) {
            final typ = v['typ'] as String? ?? '';
            final typLabel = typLabels[typ] ?? typ;
            final datum = v['datum'] as String? ?? '';
            final formattedDatum = datum.contains('-') ? datum.split('-').reversed.join('.') : datum;
            MaterialColor badgeColor = Colors.grey;
            if (typ.startsWith('owi_') || typ.startsWith('bussgeld_')) badgeColor = Colors.orange;
            if (typ.startsWith('straf_')) badgeColor = Colors.red;
            if (typ.startsWith('kontakt_')) badgeColor = Colors.blue;
            final vorfallId = v['id'] is int ? v['id'] : int.tryParse(v['id'].toString()) ?? 0;
            return InkWell(
              onTap: () => PolizeiVorfallDialog.show(context, widget.apiService, vorfallId, widget.adminMitgliedernummer, () => _loadUserPolizei().then((_) { if (mounted) setState(() {}); })),
              borderRadius: BorderRadius.circular(8),
              child: Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Flexible(child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: badgeColor.shade100, borderRadius: BorderRadius.circular(4)),
                    child: Text(typLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor.shade800), overflow: TextOverflow.ellipsis))),
                  const SizedBox(width: 8),
                  if (formattedDatum.isNotEmpty) Text(formattedDatum, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  if (v['aktenzeichen'] != null && v['aktenzeichen'].toString().isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text('Az: ${v['aktenzeichen']}', style: TextStyle(fontSize: 12, color: Colors.blue.shade600, fontWeight: FontWeight.w500)),
                  ],
                  const Spacer(),
                  InkWell(onTap: () => _deleteVorfall(v['id'] is int ? v['id'] : int.parse(v['id'].toString())),
                    child: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400)),
                ]),
                if (v['sachbearbeiter_name'] != null && v['sachbearbeiter_name'].toString().isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.person, size: 14, color: Colors.grey.shade500), const SizedBox(width: 4),
                    Text('${v['sachbearbeiter_name']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    if (v['sachbearbeiter_telefon'] != null && v['sachbearbeiter_telefon'].toString().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.phone, size: 14, color: Colors.grey.shade500), const SizedBox(width: 4),
                      Text('${v['sachbearbeiter_telefon']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                    ],
                  ]),
                ],
                if (v['beschreibung'] != null && v['beschreibung'].toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Text(v['beschreibung'], style: const TextStyle(fontSize: 13)),
                ],
              ]),
            ));
          }),
      ],
    )));
  }

  Widget _contactRow(IconData icon, String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
    ]));
  }
}
