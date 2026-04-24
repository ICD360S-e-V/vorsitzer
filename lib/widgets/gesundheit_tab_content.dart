import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import '../utils/clipboard_helper.dart';
import '../utils/file_picker_helper.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart' as pdfrx;
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../services/termin_service.dart';
import '../models/user.dart';
import '../screens/webview_screen.dart';
import 'file_viewer_dialog.dart';

class GesundheitTabContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final TicketService ticketService;
  final TerminService terminService;
  final String adminMitgliedernummer;

  const GesundheitTabContent({
    super.key,
    required this.user,
    required this.apiService,
    required this.ticketService,
    required this.terminService,
    required this.adminMitgliedernummer,
  });

  @override
  State<GesundheitTabContent> createState() => _GesundheitTabContentState();
}

class _GesundheitTabContentState extends State<GesundheitTabContent> {
  // ============= PHYSIOTHERAPIE PRAXIS DATENBANK =============
  static const List<Map<String, String>> _physioPraxenDB = [
    {
      'name': 'Physio Gesellschaft für Krankengymnastik',
      'strasse': 'Krankenhausstr. 1',
      'plz': '89231',
      'ort': 'Neu-Ulm',
      'telefon': '0731 / 79 03 07-0',
      'fax': '0731 / 79 03 07-99',
      'email': 'neu-ulm@physio-gmbh.de',
    },
  ];

  // ============= BLUTANALYSE PARAMETER MIT REFERENZWERTEN (geschlechts-/altersabhängig) =============
  // Quelle: DGKL (Deutsche Gesellschaft für Klinische Chemie), Thomas L. "Labor und Diagnose" 8. Auflage
  // M = männlich, W = weiblich. Bei gleichen Werten: min_m == min_w etc.

  int _berechneAlter() {
    final geb = widget.user.geburtsdatum;
    if (geb == null || geb.isEmpty) return 40; // Default
    // Try dd.MM.yyyy or yyyy-MM-dd
    DateTime? d;
    if (geb.contains('.')) {
      final p = geb.split('.');
      if (p.length == 3) d = DateTime.tryParse('${p[2]}-${p[1]}-${p[0]}');
    } else {
      d = DateTime.tryParse(geb);
    }
    if (d == null) return 40;
    final now = DateTime.now();
    int alter = now.year - d.year;
    if (now.month < d.month || (now.month == d.month && now.day < d.day)) alter--;
    return alter;
  }

  bool get _isMaennlich {
    final g = widget.user.geschlecht?.toUpperCase() ?? 'M';
    return g != 'W';
  }

  List<Map<String, dynamic>> get _blutParameter {
    final m = _isMaennlich;
    return [
      // ── Blutbild (DGKL-Standard) ──
      {'key': 'erythrozyten', 'label': 'Erythrozyten', 'unit': 'Mio/µl', 'min': m ? 4.3 : 3.8, 'max': m ? 5.9 : 5.2, 'gruppe': 'Blutbild'},
      {'key': 'leukozyten', 'label': 'Leukozyten', 'unit': 'Tsd/µl', 'min': 4.0, 'max': 10.0, 'gruppe': 'Blutbild'},
      {'key': 'thrombozyten', 'label': 'Thrombozyten', 'unit': 'Tsd/µl', 'min': 150.0, 'max': 400.0, 'gruppe': 'Blutbild'},
      {'key': 'haemoglobin', 'label': 'Hämoglobin', 'unit': 'g/dl', 'min': m ? 13.5 : 12.0, 'max': m ? 17.5 : 16.0, 'gruppe': 'Blutbild'},
      {'key': 'haematokrit', 'label': 'Hämatokrit', 'unit': '%', 'min': m ? 40.0 : 35.0, 'max': m ? 52.0 : 47.0, 'gruppe': 'Blutbild'},
      {'key': 'mcv', 'label': 'MCV', 'unit': 'fl', 'min': 80.0, 'max': 100.0, 'gruppe': 'Blutbild'},
      {'key': 'mch', 'label': 'MCH', 'unit': 'pg', 'min': 27.0, 'max': 33.0, 'gruppe': 'Blutbild'},
      {'key': 'mchc', 'label': 'MCHC', 'unit': 'g/dl', 'min': 32.0, 'max': 36.0, 'gruppe': 'Blutbild'},
      // ── Leberwerte ──
      {'key': 'got', 'label': 'GOT (AST)', 'unit': 'U/l', 'min': 0.0, 'max': m ? 50.0 : 35.0, 'gruppe': 'Leberwerte'},
      {'key': 'gpt', 'label': 'GPT (ALT)', 'unit': 'U/l', 'min': 0.0, 'max': m ? 50.0 : 35.0, 'gruppe': 'Leberwerte'},
      {'key': 'g_gt', 'label': 'Gamma-GT', 'unit': 'U/l', 'min': 0.0, 'max': m ? 60.0 : 40.0, 'gruppe': 'Leberwerte'},
      {'key': 'alk_phosphatase', 'label': 'Alkalische Phosphatase', 'unit': 'U/l', 'min': 40.0, 'max': 130.0, 'gruppe': 'Leberwerte'},
      {'key': 'bilirubin_gesamt', 'label': 'Bilirubin gesamt', 'unit': 'mg/dl', 'min': 0.0, 'max': 1.2, 'gruppe': 'Leberwerte'},
      {'key': 'bilirubin_direkt', 'label': 'Bilirubin direkt', 'unit': 'mg/dl', 'min': 0.0, 'max': 0.3, 'gruppe': 'Leberwerte'},
      {'key': 'bilirubin_indirekt', 'label': 'Bilirubin indirekt', 'unit': 'mg/dl', 'min': 0.0, 'max': 0.8, 'gruppe': 'Leberwerte'},
      // ── Nierenwerte ──
      {'key': 'creatinin', 'label': 'Creatinin (Serum)', 'unit': 'mg/dl', 'min': m ? 0.7 : 0.5, 'max': m ? 1.2 : 0.9, 'gruppe': 'Nierenwerte'},
      {'key': 'ckd_epi', 'label': 'CKD-EPI Kreatinin (eGFR)', 'unit': 'ml/min', 'min': 90.0, 'max': 999.0, 'gruppe': 'Nierenwerte'},
      {'key': 'harnsaeure', 'label': 'Harnsäure (Serum)', 'unit': 'mg/dl', 'min': m ? 3.4 : 2.4, 'max': m ? 7.0 : 5.7, 'gruppe': 'Nierenwerte'},
      // ── Fettstoffwechsel ──
      {'key': 'cholesterin', 'label': 'Cholesterin gesamt', 'unit': 'mg/dl', 'min': 0.0, 'max': 200.0, 'gruppe': 'Fettstoffwechsel'},
      {'key': 'ldl_cholesterin', 'label': 'LDL-Cholesterin', 'unit': 'mg/dl', 'min': 0.0, 'max': 130.0, 'gruppe': 'Fettstoffwechsel'},
      // ── Blutzucker ──
      {'key': 'glucose_nuechtern', 'label': 'Glucose nüchtern', 'unit': 'mg/dl', 'min': 70.0, 'max': 100.0, 'gruppe': 'Blutzucker'},
      // ── Entzündung ──
      {'key': 'crp', 'label': 'C-reaktives Protein (CRP)', 'unit': 'mg/l', 'min': 0.0, 'max': 5.0, 'gruppe': 'Entzündung'},
      // ── Elektrolyte ──
      {'key': 'natrium', 'label': 'Natrium', 'unit': 'mmol/l', 'min': 136.0, 'max': 145.0, 'gruppe': 'Elektrolyte'},
      {'key': 'kalium', 'label': 'Kalium', 'unit': 'mmol/l', 'min': 3.5, 'max': 5.0, 'gruppe': 'Elektrolyte'},
      {'key': 'calcium', 'label': 'Calcium (Serum)', 'unit': 'mmol/l', 'min': 2.2, 'max': 2.65, 'gruppe': 'Elektrolyte'},
      // ── Eisenstoffwechsel ──
      {'key': 'ferritin', 'label': 'Ferritin', 'unit': 'ng/ml', 'min': m ? 30.0 : 15.0, 'max': m ? 400.0 : 150.0, 'gruppe': 'Eisenstoffwechsel'},
      // ── Vitamine ──
      {'key': 'vitamin_b12', 'label': 'Vitamin B12', 'unit': 'pg/ml', 'min': 200.0, 'max': 900.0, 'gruppe': 'Vitamine'},
      {'key': 'folsaeure', 'label': 'Folsäure', 'unit': 'ng/ml', 'min': 3.0, 'max': 17.0, 'gruppe': 'Vitamine'},
      {'key': 'vitamin_d3', 'label': 'Vitamin D3 (25-OH)', 'unit': 'ng/ml', 'min': 30.0, 'max': 100.0, 'gruppe': 'Vitamine'},
      // ── Hepatitis / Infektionen (qualitativ: negativ/positiv) ──
      {'key': 'hepatitis_a_igg', 'label': 'Hepatitis A IgG (Anti-HAV IgG)', 'unit': 'S/CO', 'min': 1.0, 'max': 999.0, 'gruppe': 'Infektionen'},
      {'key': 'hepatitis_a_igm', 'label': 'Hepatitis A IgM (Anti-HAV IgM)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
      {'key': 'hepatitis_b_c_igg', 'label': 'Hepatitis B c IgG (Anti-HBc)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
      {'key': 'hepatitis_b_s_ak', 'label': 'Hepatitis B s Antikörper (Anti-HBs)', 'unit': 'mIU/ml', 'min': 20.0, 'max': 999.0, 'gruppe': 'Infektionen'},
      {'key': 'hepatitis_b_s_ag', 'label': 'Hepatitis B s Antigen (HBsAg)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
      {'key': 'hepatitis_c_ig', 'label': 'Hepatitis C Virus Ig (Anti-HCV)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
      {'key': 'hiv_screening', 'label': 'HIV 1/2 AK Screening', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
    ];
  }

  // ============= GESUNDHEIT DATA (separate from Behörde) =============

  final Map<String, Map<String, dynamic>> _gesundheitData = {};
  final Map<String, bool> _gesundheitLoading = {};
  final Map<String, bool> _gesundheitSaving = {};
  // Multi-doctor: selected instance per base type, count per base type
  final Map<String, int> _multiArztSelected = {};
  final Map<String, int> _multiArztCount = {};

  Future<void> _loadGesundheitData(String type) async {
    if (_gesundheitLoading[type] == true) return;
    if (_gesundheitData.containsKey(type)) return;
    _gesundheitLoading[type] = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    try {
      final result = await widget.apiService.getGesundheitData(widget.user.id, type);
      if (mounted) {
        setState(() {
          _gesundheitData[type] = (result['data'] != null)
              ? Map<String, dynamic>.from(result['data'])
              : {};
          _gesundheitLoading[type] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gesundheitLoading[type] = false;
          _gesundheitData[type] = {};
        });
      }
    }
  }

  Future<void> _saveGesundheitData(String type, Map<String, dynamic> data) async {
    setState(() => _gesundheitSaving[type] = true);
    try {
      final result = await widget.apiService.saveGesundheitData(widget.user.id, type, data);
      if (mounted) {
        if (result['success'] == true) {
          setState(() => _gesundheitData[type] = data);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Daten gespeichert'), backgroundColor: Colors.green),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(result['message'] ?? 'Fehler'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _gesundheitSaving[type] = false);
    }
  }
  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 1100;
    return DefaultTabController(
      length: 18,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.teal.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.teal.shade700,
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              _gesundheitTabItem(Icons.medical_services, 'Hausarzt', isCompact),
              _gesundheitTabItem(Icons.air, 'Lungenarzt', isCompact),
              _gesundheitTabItem(Icons.visibility, 'Augenarzt', isCompact),
              _gesundheitTabItem(Icons.hearing, 'HNO-Arzt', isCompact),
              _gesundheitTabItem(Icons.psychology, 'Psychiater', isCompact),
              _gesundheitTabItem(Icons.favorite, 'Kardiologe', isCompact),
              _gesundheitTabItem(Icons.hub, 'Neurologe', isCompact),
              _gesundheitTabItem(Icons.accessibility_new, 'Orthopäde', isCompact),
              _gesundheitTabItem(Icons.face, 'Hautarzt', isCompact),
              _gesundheitTabItem(Icons.mood, 'Zahnarzt', isCompact),
              _gesundheitTabItem(Icons.pregnant_woman, 'Gynäkologie', isCompact),
              _gesundheitTabItem(Icons.water_drop, 'Urologie', isCompact),
              _gesundheitTabItem(Icons.biotech, 'Onkologie', isCompact),
              _gesundheitTabItem(Icons.science, 'Endokrinologie', isCompact),
              _gesundheitTabItem(Icons.monitor_heart, 'Diabetologie', isCompact),
              _gesundheitTabItem(Icons.local_hospital, 'Krankenhaus', isCompact),
              _gesundheitTabItem(Icons.more_horiz, 'Sonstige', isCompact),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildArztContent('gesundheit_hausarzt', 'Hausarzt', 'Allgemeinmedizin / Innere Medizin'),
                _buildArztContent('gesundheit_lungenarzt', 'Lungenarzt', 'Pneumologie / Pulmologie'),
                _buildArztContent('gesundheit_augenarzt', 'Augenarzt', 'Ophthalmologie'),
                _buildArztContent('gesundheit_hno', 'HNO-Arzt', 'Hals-Nasen-Ohren-Heilkunde'),
                _buildArztContent('gesundheit_psychiater', 'Psychiater / Psychologe', 'Psychiatrie / Psychotherapie'),
                _buildArztContent('gesundheit_kardiologe', 'Kardiologe', 'Kardiologie / Herzmedizin'),
                _buildArztContent('gesundheit_neurologe', 'Neurologe', 'Neurologie / Nervenheilkunde'),
                _buildArztContent('gesundheit_orthopaede', 'Orthopäde', 'Orthopädie / Unfallchirurgie'),
                _buildArztContent('gesundheit_hautarzt', 'Hautarzt', 'Dermatologie'),
                _buildArztContent('gesundheit_zahnarzt', 'Zahnarzt', 'Zahnmedizin'),
                _buildArztContent('gesundheit_gynaekologie', 'Gynäkologe', 'Gynäkologie / Frauenheilkunde'),
                _buildArztContent('gesundheit_urologie', 'Urologe', 'Urologie'),
                _buildArztContent('gesundheit_onkologie', 'Onkologe', 'Onkologie / Krebsmedizin'),
                _buildArztContent('gesundheit_endokrinologie', 'Endokrinologe', 'Endokrinologie / Hormonerkrankungen / Schilddrüse'),
                _buildArztContent('gesundheit_diabetologie', 'Diabetologe', 'Diabetologie / Diabetes mellitus / Stoffwechsel'),
                _buildArztContent('gesundheit_krankenhaus', 'Krankenhaus', 'Klinik / Stationare Behandlung'),
                _buildArztContent('gesundheit_sonstige', 'Sonstiger Arzt', 'Weitere Fachrichtung'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _gesundheitTabItem(IconData icon, String label, bool isCompact) {
    if (isCompact) {
      return Tab(child: Tooltip(message: label, child: Icon(icon, size: 18)));
    }
    return Tab(icon: Icon(icon, size: 18), text: label);
  }

  // ========== VERSORGUNGSAMT ==========

  // Show Versorgungsamt search dialog
  void _showVersorgungsamtSucheDialog(BuildContext context, Function(Map<String, dynamic>) onSelect) {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setSearchState) {
          Future<void> doSearch() async {
            setSearchState(() => loading = true);
            final res = await widget.apiService.searchVersorgungsaemter(search: searchC.text);
            if (dlgCtx.mounted) {
              setSearchState(() {
                loading = false;
                results = List<Map<String, dynamic>>.from(res['versorgungsaemter'] ?? []);
              });
            }
          }
          if (results.isEmpty && !loading && searchC.text.isEmpty) {
            doSearch();
          }
          return AlertDialog(
            title: const Text('Versorgungsamt auswählen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: 480, height: 400,
              child: Column(children: [
                TextField(
                  controller: searchC,
                  decoration: InputDecoration(
                    hintText: 'Suchen (Name, Ort, Bundesland)...',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch),
                  ),
                  onSubmitted: (_) => doSearch(),
                ),
                const SizedBox(height: 8),
                if (loading) const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator()),
                if (!loading) Expanded(
                  child: results.isEmpty
                      ? Center(child: Text('Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          itemCount: results.length,
                          itemBuilder: (_, i) {
                            final va = results[i];
                            final typLabel = va['typ'] == 'hauptsitz' ? 'Hauptsitz' : va['typ'] == 'aussenstelle' ? 'Außenstelle' : 'Regionalstelle';
                            return Card(
                              child: ListTile(
                                dense: true,
                                leading: Icon(va['typ'] == 'hauptsitz' ? Icons.account_balance : Icons.location_city, color: Colors.purple.shade600),
                                title: Text(va['kurzname']?.toString() ?? va['name']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('${va['strasse'] ?? ''}, ${va['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  Text('$typLabel – ${va['bundesland'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.purple.shade400)),
                                ]),
                                onTap: () { Navigator.pop(dlgCtx); onSelect(va); },
                              ),
                            );
                          },
                        ),
                ),
              ]),
            ),
            actions: [TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen'))],
          );
        },
      ),
    );
  }

  Widget _buildVersorgungsamtContent() {
    const type = 'gesundheit_versorgungsamt';
    if (!_gesundheitData.containsKey(type) && _gesundheitLoading[type] != true) {
      _loadGesundheitData(type);
    }
    if (_gesundheitLoading[type] == true) {
      return const Center(child: CircularProgressIndicator());
    }
    final data = Map<String, dynamic>.from(_gesundheitData[type] ?? {});
    final va = Map<String, dynamic>.from(data['versorgungsamt'] ?? {});

    // Merkzeichen definitions
    const merkzeichenDefs = <Map<String, String>>[
      {'code': 'G', 'label': 'Erheblich gehbehindert', 'desc': 'Öffentl. Verkehrsmittel Rabatt, Parkprivilegien, Steuervorteile'},
      {'code': 'aG', 'label': 'Außergewöhnliche Gehbehinderung', 'desc': 'Kostenlose ÖPNV mit Begleitung, kostenloser Parkplatz'},
      {'code': 'H', 'label': 'Hilflosigkeit', 'desc': 'Steuervorteile, Pflegeleistungen, kostenlose ÖPNV mit Begleitung'},
      {'code': 'B', 'label': 'Begleitperson erforderlich', 'desc': 'Kostenlose Begleitperson in öffentlichen Verkehrsmitteln'},
      {'code': 'Bl', 'label': 'Blindheit', 'desc': 'Mobilitätszuschüsse, Steuervorteile, kostenlose ÖPNV'},
      {'code': 'Gl', 'label': 'Gehörlosigkeit', 'desc': 'Rundfunkbeitragsbefreiung, Kommunikationsunterstützung'},
      {'code': 'TBl', 'label': 'Taubblindheit', 'desc': 'Kombinierte Mobilitäts- und Sinnesleistungen'},
      {'code': 'RF', 'label': 'Rundfunkbeitragsbefreiung', 'desc': 'Befreiung/Ermäßigung Rundfunkgebühren'},
      {'code': 'VB', 'label': 'Versorgungsberechtigt', 'desc': 'Kriegs-/Soldatenversorgung (GdB ≥ 50)'},
      {'code': 'EB', 'label': 'Entschädigungsberechtigt', 'desc': 'Entschädigung nach § 28 BEG'},
      {'code': '1.Kl', 'label': 'Erste Klasse Bahn', 'desc': '1. Klasse Bahnfahrt für schwerbeschädigte Kriegsveteranen'},
    ];

    String gdb = va['gdb']?.toString() ?? '';
    final aktenzeichenController = TextEditingController(text: va['aktenzeichen']?.toString() ?? '');
    final gueltigBisController = TextEditingController(text: va['gueltig_bis']?.toString() ?? '');
    final notizenController = TextEditingController(text: va['notizen']?.toString() ?? '');
    String sachbearbeiterAnrede = va['sachbearbeiter_anrede']?.toString() ?? '';
    final sachbearbeiterNameController = TextEditingController(text: va['sachbearbeiter_name']?.toString() ?? '');
    String ausweisStatus = va['ausweis']?.toString() ?? 'nein';
    String befristung = va['befristung']?.toString() ?? 'unbefristet';
    String ausweisfarbe = va['ausweisfarbe']?.toString() ?? 'gruen';
    // Selected Versorgungsamt from DB
    Map<String, dynamic> selectedBehoerde = va['behoerde'] is Map ? Map<String, dynamic>.from(va['behoerde'] as Map) : <String, dynamic>{};
    // Merkzeichen as Set
    final merkzeichenList = va['merkzeichen_list'] is List
        ? Set<String>.from((va['merkzeichen_list'] as List).map((e) => e.toString()))
        : <String>{};
    // Check if has Freifahrt (G, aG, H, Bl, or Gl)
    bool hasFreifahrt() => merkzeichenList.any((m) => ['G', 'aG', 'H', 'Bl', 'Gl'].contains(m));

    Future<void> saveData() async {
      final updatedData = Map<String, dynamic>.from(_gesundheitData[type] ?? data);
      updatedData['versorgungsamt'] = {
        'gdb': gdb,
        'aktenzeichen': aktenzeichenController.text.trim(),
        'merkzeichen_list': merkzeichenList.toList(),
        'ausweis': ausweisStatus,
        'ausweisfarbe': ausweisfarbe,
        'befristung': befristung,
        'gueltig_bis': gueltigBisController.text.trim(),
        'notizen': notizenController.text.trim(),
        'sachbearbeiter_anrede': sachbearbeiterAnrede,
        'sachbearbeiter_name': sachbearbeiterNameController.text.trim(),
        'behoerde': selectedBehoerde,
      };
      // Save silently — update cache without parent setState to avoid
      // recreating TextEditingControllers (which resets cursor position)
      _gesundheitData[type] = updatedData;
      try {
        await widget.apiService.saveGesundheitData(widget.user.id, type, updatedData);
      } catch (_) {}
    }

    return StatefulBuilder(
      builder: (ctx, setVaState) {
        final gdbInt = int.tryParse(gdb) ?? 0;
        final canHaveAusweis = gdbInt >= 50;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBehoerdeSectionHeader(Icons.accessible, 'Versorgungsamt', Colors.purple.shade700),
              const SizedBox(height: 4),
              Text('Schwerbehinderung & Ausweis', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 16),

              // ── Zuständiges Versorgungsamt ──
              _buildBehoerdeSectionHeader(Icons.business, 'Zuständiges Versorgungsamt', Colors.purple.shade600),
              const SizedBox(height: 8),
              if (selectedBehoerde.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.purple.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.purple.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.business, size: 16, color: Colors.purple.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Text(selectedBehoerde['name']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade800))),
                        InkWell(
                          onTap: () { setVaState(() { selectedBehoerde.clear(); }); saveData(); },
                          child: Icon(Icons.close, size: 16, color: Colors.grey.shade500),
                        ),
                      ]),
                      if (selectedBehoerde['typ'] != null) ...[
                        const SizedBox(height: 2),
                        Text(selectedBehoerde['typ'].toString(), style: TextStyle(fontSize: 10, color: Colors.purple.shade400, fontStyle: FontStyle.italic)),
                      ],
                      if (selectedBehoerde['strasse'] != null || selectedBehoerde['plz_ort'] != null) ...[
                        const SizedBox(height: 6),
                        if (selectedBehoerde['strasse'] != null)
                          Text(selectedBehoerde['strasse'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        if (selectedBehoerde['plz_ort'] != null)
                          Text(selectedBehoerde['plz_ort'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                      ],
                      if (selectedBehoerde['telefon'] != null) ...[
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(Icons.phone, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(selectedBehoerde['telefon'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ]),
                      ],
                      if (selectedBehoerde['zustaendig_fuer'] != null) ...[
                        const SizedBox(height: 4),
                        Text('Zuständig für: ${selectedBehoerde['zustaendig_fuer']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(selectedBehoerde.isEmpty ? Icons.search : Icons.swap_horiz, size: 16),
                  label: Text(selectedBehoerde.isEmpty ? 'Versorgungsamt auswählen' : 'Anderes Versorgungsamt wählen', style: const TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.purple.shade700,
                    side: BorderSide(color: Colors.purple.shade300),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onPressed: () {
                    _showVersorgungsamtSucheDialog(ctx, (behoerde) {
                      setVaState(() {
                        selectedBehoerde.clear();
                        selectedBehoerde.addAll(behoerde);
                      });
                      saveData();
                    });
                  },
                ),
              ),
              const SizedBox(height: 16),

              // ── Sachbearbeiter/in ──
              _buildBehoerdeSectionHeader(Icons.person_outline, 'Sachbearbeiter/in', Colors.purple.shade600),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['', 'Frau', 'Herr'].contains(sachbearbeiterAnrede) ? sachbearbeiterAnrede : '',
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          hint: Text('Anrede', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('Anrede wählen', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'Frau', child: Text('Frau', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'Herr', child: Text('Herr', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) {
                            setVaState(() => sachbearbeiterAnrede = v ?? '');
                            saveData();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: sachbearbeiterNameController,
                      decoration: InputDecoration(
                        labelText: 'Name',
                        hintText: 'z.B. Müller',
                        prefixIcon: Icon(Icons.badge, size: 18, color: Colors.purple.shade400),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => saveData(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── GdB Dropdown + Aktenzeichen ──
              _buildBehoerdeSectionHeader(Icons.assessment, 'Grad der Behinderung & Aktenzeichen', Colors.purple.shade600),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['', '20', '30', '40', '50', '60', '70', '80', '90', '100'].contains(gdb) ? gdb : '',
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          hint: Text('GdB wählen', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          items: [
                            const DropdownMenuItem(value: '', child: Text('Nicht festgelegt', style: TextStyle(fontSize: 12))),
                            ...['20', '30', '40', '50', '60', '70', '80', '90', '100'].map((v) => DropdownMenuItem(
                              value: v,
                              child: Text('GdB $v${v == '50' ? '  (Ausweis ab hier)' : v == '100' ? '  (Schwerstbehinderung)' : ''}',
                                style: TextStyle(fontSize: 12, fontWeight: int.parse(v) >= 50 ? FontWeight.w600 : FontWeight.normal)),
                            )),
                          ],
                          onChanged: (v) {
                            setVaState(() => gdb = v ?? '');
                            saveData();
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 3,
                    child: TextFormField(
                      controller: aktenzeichenController,
                      decoration: InputDecoration(
                        labelText: 'Aktenzeichen',
                        hintText: 'z.B. SB-12345-2026',
                        prefixIcon: Icon(Icons.folder, size: 18, color: Colors.purple.shade400),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => saveData(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── Merkzeichen Checkboxes ──
              _buildBehoerdeSectionHeader(Icons.label_important, 'Merkzeichen', Colors.purple.shade600),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade200), borderRadius: BorderRadius.circular(10)),
                child: Column(
                  children: merkzeichenDefs.asMap().entries.map((entry) {
                    final mz = entry.value;
                    final code = mz['code']!;
                    final isChecked = merkzeichenList.contains(code);
                    return Column(
                      children: [
                        if (entry.key > 0) Divider(height: 1, color: Colors.grey.shade200),
                        InkWell(
                          onTap: () {
                            setVaState(() {
                              if (isChecked) { merkzeichenList.remove(code); } else { merkzeichenList.add(code); }
                            });
                            saveData();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 24, height: 24,
                                  child: Checkbox(
                                    value: isChecked,
                                    activeColor: Colors.purple.shade600,
                                    onChanged: (v) {
                                      setVaState(() {
                                        if (v == true) { merkzeichenList.add(code); } else { merkzeichenList.remove(code); }
                                      });
                                      saveData();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isChecked ? Colors.purple.shade100 : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(code, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isChecked ? Colors.purple.shade800 : Colors.grey.shade600)),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(mz['label']!, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: isChecked ? Colors.black87 : Colors.grey.shade600)),
                                      Text(mz['desc']!, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
              if (merkzeichenList.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: merkzeichenList.map((code) => Chip(
                    label: Text(code, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
                    backgroundColor: Colors.purple.shade600,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    padding: EdgeInsets.zero,
                    deleteIcon: const Icon(Icons.close, size: 14, color: Colors.white70),
                    onDeleted: () { setVaState(() => merkzeichenList.remove(code)); saveData(); },
                  )).toList(),
                ),
              ],
              const SizedBox(height: 16),

              // ── Schwerbehindertenausweis ──
              _buildBehoerdeSectionHeader(Icons.credit_card, 'Schwerbehindertenausweis', Colors.purple.shade600),
              const SizedBox(height: 10),
              if (!canHaveAusweis && gdb.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
                  child: Row(children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Schwerbehindertenausweis ab GdB 50. Aktueller GdB: $gdb', style: TextStyle(fontSize: 11, color: Colors.orange.shade800))),
                  ]),
                ),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ausweisStatus,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          items: const [
                            DropdownMenuItem(value: 'nein', child: Text('Kein Ausweis', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'beantragt', child: Text('Beantragt', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'ja', child: Text('Ausweis vorhanden', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) { setVaState(() => ausweisStatus = v ?? 'nein'); saveData(); },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: befristung,
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          items: const [
                            DropdownMenuItem(value: 'unbefristet', child: Text('Unbefristet', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: 'befristet', child: Text('Befristet', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) { setVaState(() => befristung = v ?? 'unbefristet'); saveData(); },
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (befristung == 'befristet') ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: gueltigBisController,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Gültig bis',
                    prefixIcon: Icon(Icons.event, size: 18, color: Colors.purple.shade400),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.edit_calendar, size: 16),
                      onPressed: () async {
                        final picked = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 365)), firstDate: DateTime(2024), lastDate: DateTime(2040), locale: const Locale('de'));
                        if (picked != null) { gueltigBisController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}'; saveData(); }
                      },
                    ),
                  ),
                ),
              ],

              // ── Ausweis-Farbe ──
              if (ausweisStatus == 'ja') ...[
                const SizedBox(height: 12),
                Row(children: [
                  Text('Ausweisfarbe: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Grün', style: TextStyle(fontSize: 11)),
                    selected: ausweisfarbe == 'gruen',
                    selectedColor: Colors.green.shade200,
                    onSelected: (v) { setVaState(() => ausweisfarbe = 'gruen'); saveData(); },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: const Text('Grün + Orange', style: TextStyle(fontSize: 11)),
                    selected: ausweisfarbe == 'gruen_orange',
                    selectedColor: Colors.orange.shade200,
                    onSelected: (v) { setVaState(() => ausweisfarbe = 'gruen_orange'); saveData(); },
                  ),
                ]),
                if (hasFreifahrt() && ausweisfarbe != 'gruen_orange')
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Hinweis: Mit Merkzeichen ${merkzeichenList.where((m) => ['G', 'aG', 'H', 'Bl', 'Gl'].contains(m)).join(', ')} haben Sie Anspruch auf Grün+Orange (Freifahrtausweis)',
                      style: TextStyle(fontSize: 10, color: Colors.orange.shade700)),
                  ),
              ],
              const SizedBox(height: 16),

              // ── Ausweis-Vorschau (Vorderseite + Rückseite) ──
              if (ausweisStatus == 'ja' || gdbInt >= 50) ...[
                // Label
                Row(children: [
                  Icon(Icons.credit_card, size: 14, color: Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text('Ausweis-Vorschau (Muster)', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                ]),
                const SizedBox(height: 8),

                // ── VORDERSEITE (Front) ──
                Container(
                  width: double.infinity,
                  height: 190,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: ausweisfarbe == 'gruen_orange'
                        ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFFE65100)], stops: [0.55, 0.55])
                        : LinearGradient(colors: [Colors.green.shade700, Colors.green.shade500]),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  child: Stack(
                    children: [
                      Positioned(right: 12, top: 12, child: Icon(Icons.shield, size: 44, color: Colors.white.withValues(alpha: 0.12))),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Header
                            const Text('BUNDESREPUBLIK DEUTSCHLAND', style: TextStyle(fontSize: 8, color: Colors.white60, letterSpacing: 1.5, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 2),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(3)),
                              child: const Text('SCHWERBEHINDERTENAUSWEIS', style: TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1)),
                            ),
                            const SizedBox(height: 12),
                            // Photo + Name + GdB
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 55, height: 70,
                                  decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.white38)),
                                  child: const Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.person, size: 28, color: Colors.white54),
                                      Text('Lichtbild', style: TextStyle(fontSize: 7, color: Colors.white38)),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text('Name', style: TextStyle(fontSize: 8, color: Colors.white54)),
                                      Text(widget.user.name, style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 10),
                                      const Text('Geschäftszeichen', style: TextStyle(fontSize: 8, color: Colors.white54)),
                                      Text(
                                        aktenzeichenController.text.isNotEmpty ? aktenzeichenController.text : '—',
                                        style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w500),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const Spacer(),
                            // Bottom: Gültig bis
                            Row(children: [
                              const Text('Gültig bis: ', style: TextStyle(fontSize: 9, color: Colors.white54)),
                              Text(
                                befristung == 'befristet' && gueltigBisController.text.isNotEmpty
                                    ? gueltigBisController.text
                                    : 'Unbefristet',
                                style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.w600),
                              ),
                              const Spacer(),
                              if (ausweisfarbe == 'gruen_orange')
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(3)),
                                  child: const Text('FREIFAHRT', style: TextStyle(fontSize: 7, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                                ),
                            ]),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Center(child: Text('— Vorderseite —', style: TextStyle(fontSize: 9, color: Colors.grey.shade400))),
                const SizedBox(height: 10),

                // ── RÜCKSEITE (Back) ──
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: ausweisfarbe == 'gruen_orange'
                        ? const LinearGradient(colors: [Color(0xFF2E7D32), Color(0xFFE65100)], stops: [0.55, 0.55])
                        : LinearGradient(colors: [Colors.green.shade700, Colors.green.shade500]),
                    boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 6, offset: const Offset(0, 3))],
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // GdB
                      Row(children: [
                        const Text('Grad der Behinderung (GdB)', style: TextStyle(fontSize: 9, color: Colors.white54)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(6)),
                          child: Text('GdB $gdb', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                      ]),
                      const SizedBox(height: 12),
                      // Merkzeichen
                      const Text('Merkzeichen', style: TextStyle(fontSize: 9, color: Colors.white54)),
                      const SizedBox(height: 6),
                      if (merkzeichenList.isNotEmpty)
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: merkzeichenList.map((code) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(color: Colors.white30),
                            ),
                            child: Text(code, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.bold)),
                          )).toList(),
                        )
                      else
                        const Text('Keine Merkzeichen', style: TextStyle(fontSize: 11, color: Colors.white38, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 14),
                      // Divider line
                      Container(height: 1, color: Colors.white24),
                      const SizedBox(height: 10),
                      // Ausstellende Behörde
                      const Text('Ausstellende Behörde', style: TextStyle(fontSize: 9, color: Colors.white54)),
                      const SizedBox(height: 4),
                      if (selectedBehoerde.isNotEmpty) ...[
                        Text(selectedBehoerde['name']?.toString() ?? '—', style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
                        if (selectedBehoerde['strasse'] != null)
                          Text(selectedBehoerde['strasse'].toString(), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                        if (selectedBehoerde['plz_ort'] != null)
                          Text(selectedBehoerde['plz_ort'].toString(), style: const TextStyle(fontSize: 10, color: Colors.white70)),
                      ] else
                        const Text('Nicht angegeben', style: TextStyle(fontSize: 11, color: Colors.white38, fontStyle: FontStyle.italic)),
                      const SizedBox(height: 10),
                      // Aktenzeichen
                      Row(children: [
                        const Text('Aktenzeichen: ', style: TextStyle(fontSize: 9, color: Colors.white54)),
                        Expanded(
                          child: Text(
                            aktenzeichenController.text.isNotEmpty ? aktenzeichenController.text : '—',
                            style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                Center(child: Text('— Rückseite —', style: TextStyle(fontSize: 9, color: Colors.grey.shade400))),

                if (ausweisfarbe == 'gruen_orange') ...[
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.green.shade700, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 4),
                    Text('Grün', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    const SizedBox(width: 8),
                    const Text('+', style: TextStyle(fontSize: 10)),
                    const SizedBox(width: 8),
                    Container(width: 14, height: 14, decoration: BoxDecoration(color: Colors.orange.shade800, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 4),
                    Text('Orange = Freifahrtausweis (kostenlose ÖPNV)', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  ]),
                ],
                const SizedBox(height: 14),
              ],

              // ── Notizen ──
              TextFormField(
                controller: notizenController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: 'Notizen',
                  hintText: 'Zusätzliche Informationen...',
                  prefixIcon: Icon(Icons.notes, size: 18, color: Colors.purple.shade400),
                  alignLabelWithHint: true,
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (_) => saveData(),
              ),
              const SizedBox(height: 20),

              // ── Schriftverkehr / Verlauf ──
              _buildVersorgungsamtVerlauf(ctx, setVaState, data, type, saveData),
            ],
          ),
        );
      },
    );
  }

  Widget _buildVersorgungsamtVerlauf(BuildContext ctx, void Function(void Function()) setVaState, Map<String, dynamic> data, String type, Future<void> Function() saveData) {
    final verlauf = data['verlauf'] is List
        ? List<Map<String, dynamic>>.from((data['verlauf'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
        : <Map<String, dynamic>>[];

    void addEntry(Map<String, dynamic> entry) {
      verlauf.insert(0, entry);
      data['verlauf'] = verlauf;
      _gesundheitData[type] = data;
      saveData();
      setVaState(() {});
    }

    // Preload doc counts for badge
    for (final v in verlauf) {
      final eId = v['entry_id']?.toString() ?? '';
      if (eId.isNotEmpty && !_verlaufDocs.containsKey(eId)) {
        _loadVerlaufDocs(eId, type, setVaState);
      }
    }

    // Colors and icons per type
    const typeConfig = {
      'eingang': ('Eingang (Versorgungsamt → Sie)', Icons.call_received, Color(0xFF1565C0)),
      'ausgang': ('Ausgang (Sie → Versorgungsamt)', Icons.call_made, Color(0xFF2E7D32)),
    };
    const methodConfig = {
      'postalisch': ('Postalisch', Icons.local_post_office),
      'online': ('Online', Icons.language),
      'email': ('E-Mail', Icons.email),
      'fax': ('Fax', Icons.fax),
      'persoenlich': ('Persönlich', Icons.person),
    };
    const eingangMethods = ['postalisch', 'online', 'email', 'fax', 'persoenlich'];
    const ausgangMethods = ['postalisch', 'online', 'email', 'persoenlich'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header + Add button
        Row(children: [
          Icon(Icons.swap_vert, size: 18, color: Colors.purple.shade700),
          const SizedBox(width: 6),
          Text('Schriftverkehr', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
          const Spacer(),
          TextButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 12)),
            style: TextButton.styleFrom(foregroundColor: Colors.purple.shade700),
            onPressed: () {
              String richtung = 'eingang';
              String versandart = 'postalisch';
              final datumController = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
              final betreffController = TextEditingController();
              final notizController = TextEditingController();

              showDialog(
                context: ctx,
                builder: (dCtx) => StatefulBuilder(
                  builder: (dCtx2, setDState) => AlertDialog(
                    title: Row(children: [
                      Icon(Icons.post_add, size: 20, color: Colors.purple.shade700),
                      const SizedBox(width: 8),
                      const Text('Neuer Schriftverkehr', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    ]),
                    content: SizedBox(
                      width: 420,
                      child: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Richtung (Eingang/Ausgang)
                            Text('Richtung', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                            const SizedBox(height: 6),
                            Row(children: [
                              Expanded(
                                child: ChoiceChip(
                                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.call_received, size: 14, color: richtung == 'eingang' ? Colors.white : Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text('Eingang', style: TextStyle(fontSize: 11, color: richtung == 'eingang' ? Colors.white : Colors.black87)),
                                  ]),
                                  selected: richtung == 'eingang',
                                  selectedColor: Colors.blue.shade700,
                                  onSelected: (_) => setDState(() {
                                    richtung = 'eingang';
                                    if (!eingangMethods.contains(versandart)) versandart = 'postalisch';
                                  }),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: ChoiceChip(
                                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.call_made, size: 14, color: richtung == 'ausgang' ? Colors.white : Colors.green.shade700),
                                    const SizedBox(width: 4),
                                    Text('Ausgang', style: TextStyle(fontSize: 11, color: richtung == 'ausgang' ? Colors.white : Colors.black87)),
                                  ]),
                                  selected: richtung == 'ausgang',
                                  selectedColor: Colors.green.shade700,
                                  onSelected: (_) => setDState(() {
                                    richtung = 'ausgang';
                                    if (!ausgangMethods.contains(versandart)) versandart = 'postalisch';
                                  }),
                                ),
                              ),
                            ]),
                            const SizedBox(height: 14),
                            // Versandart
                            Text('Versandart', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: methodConfig.entries.where((e) => (richtung == 'ausgang' ? ausgangMethods : eingangMethods).contains(e.key)).map((e) => ChoiceChip(
                                label: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(e.value.$2, size: 14, color: versandart == e.key ? Colors.white : Colors.grey.shade700),
                                  const SizedBox(width: 4),
                                  Text(e.value.$1, style: TextStyle(fontSize: 10, color: versandart == e.key ? Colors.white : Colors.black87)),
                                ]),
                                selected: versandart == e.key,
                                selectedColor: Colors.purple.shade600,
                                onSelected: (_) => setDState(() => versandart = e.key),
                              )).toList(),
                            ),
                            const SizedBox(height: 14),
                            // Datum
                            TextFormField(
                              controller: datumController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Datum',
                                prefixIcon: Icon(Icons.event, size: 18, color: Colors.purple.shade400),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.edit_calendar, size: 16),
                                  onPressed: () async {
                                    final picked = await showDatePicker(context: dCtx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                                    if (picked != null) datumController.text = DateFormat('dd.MM.yyyy').format(picked);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Betreff
                            TextFormField(
                              controller: betreffController,
                              decoration: InputDecoration(
                                labelText: 'Betreff',
                                hintText: 'z.B. Feststellungsbescheid, Widerspruch, ...',
                                prefixIcon: Icon(Icons.subject, size: 18, color: Colors.purple.shade400),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Notiz
                            TextFormField(
                              controller: notizController,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Notiz / Inhalt',
                                hintText: 'Kurze Beschreibung...',
                                prefixIcon: Icon(Icons.notes, size: 18, color: Colors.purple.shade400),
                                alignLabelWithHint: true,
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Abbrechen')),
                      FilledButton.icon(
                        icon: const Icon(Icons.save, size: 16),
                        label: const Text('Speichern', style: TextStyle(fontSize: 12)),
                        style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade700),
                        onPressed: () {
                          if (betreffController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Betreff ist erforderlich'), backgroundColor: Colors.orange));
                            return;
                          }
                          addEntry({
                            'entry_id': 'va_${DateTime.now().millisecondsSinceEpoch}',
                            'datum': datumController.text.trim(),
                            'richtung': richtung,
                            'versandart': versandart,
                            'betreff': betreffController.text.trim(),
                            'notiz': notizController.text.trim(),
                            'erstellt_am': DateTime.now().toIso8601String(),
                          });
                          Navigator.pop(dCtx);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ]),
        const Divider(height: 1),
        const SizedBox(height: 8),

        // Timeline entries
        if (verlauf.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade200)),
            child: Column(children: [
              Icon(Icons.inbox, size: 32, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Noch kein Schriftverkehr erfasst', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 4),
              Text('Klicken Sie auf "Neuer Eintrag" um Korrespondenz hinzuzufügen', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
            ]),
          ),

        ...verlauf.asMap().entries.map((entry) {
          final idx = entry.key;
          final v = entry.value;
          final isEingang = v['richtung'] == 'eingang';
          final tc = isEingang ? typeConfig['eingang']! : typeConfig['ausgang']!;
          final mc = methodConfig[v['versandart']] ?? methodConfig['postalisch']!;

          // Count docs for badge
          final eId = v['entry_id']?.toString() ?? '';
          final docCount = _verlaufDocs[eId]?.length ?? 0;

          return InkWell(
            onTap: () => _showSchriftverkehrDetailDialog(ctx, setVaState, v, idx, verlauf, data, type, saveData, typeConfig, methodConfig),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isEingang ? Colors.blue.shade200 : Colors.green.shade200),
                color: isEingang ? Colors.blue.shade50 : Colors.green.shade50,
              ),
              child: IntrinsicHeight(
                child: Row(
                  children: [
                    Container(
                      width: 4,
                      decoration: BoxDecoration(
                        color: tc.$3,
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(10), bottomLeft: Radius.circular(10)),
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Icon(tc.$2, size: 16, color: tc.$3),
                              const SizedBox(width: 6),
                              Text(isEingang ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: tc.$3)),
                              const SizedBox(width: 8),
                              Icon(mc.$2, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 3),
                              Text(mc.$1, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                              const Spacer(),
                              if (docCount > 0) ...[
                                Icon(Icons.attach_file, size: 12, color: Colors.grey.shade500),
                                Text('$docCount', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                const SizedBox(width: 6),
                              ],
                              Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                              const SizedBox(width: 6),
                              Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                            ]),
                            const SizedBox(height: 4),
                            Text(v['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            if (v['notiz']?.toString().isNotEmpty == true)
                              Text(v['notiz'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  // Document cache per entry_id
  final Map<String, List<Map<String, dynamic>>> _verlaufDocs = {};
  final Map<String, bool> _verlaufDocsLoading = {};

  void _loadVerlaufDocs(String entryId, String gesundheitType, [void Function(void Function())? refreshState]) {
    if (entryId.isEmpty || _verlaufDocsLoading[entryId] == true) return;
    _verlaufDocsLoading[entryId] = true;
    widget.apiService.listGesundheitDocs(
      userId: widget.user.id,
      gesundheitType: gesundheitType,
      analyseId: entryId,
    ).then((res) {
      if (mounted) {
        final docs = List<Map<String, dynamic>>.from(res['documents'] ?? []);
        _verlaufDocs[entryId] = docs;
        _verlaufDocsLoading[entryId] = false;
        refreshState?.call(() {});
      }
    }).catchError((_) {
      if (mounted) {
        _verlaufDocs[entryId] = [];
        _verlaufDocsLoading[entryId] = false;
        refreshState?.call(() {});
      }
    });
  }

  String _formatFileSize(int bytes) {
    if (bytes > 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    if (bytes > 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  void _showSchriftverkehrDetailDialog(
    BuildContext ctx,
    void Function(void Function()) setVaState,
    Map<String, dynamic> entry,
    int entryIdx,
    List<Map<String, dynamic>> verlauf,
    Map<String, dynamic> data,
    String type,
    Future<void> Function() saveData,
    Map<String, (String, IconData, Color)> typeConfig,
    Map<String, (String, IconData)> methodConfig,
  ) {
    final entryId = entry['entry_id']?.toString() ?? '';
    final isEingang = entry['richtung'] == 'eingang';
    final tc = isEingang ? typeConfig['eingang']! : typeConfig['ausgang']!;
    final mc = methodConfig[entry['versandart']] ?? methodConfig['postalisch']!;

    showDialog(
      context: ctx,
      builder: (dCtx) {
        // Force reload docs for this dialog
        bool initialLoadDone = false;
        return StatefulBuilder(
          builder: (dCtx2, setDialogState) {
            if (!initialLoadDone) {
              initialLoadDone = true;
              // Force fresh load
              _verlaufDocsLoading[entryId] = false;
              _verlaufDocs.remove(entryId);
              _loadVerlaufDocs(entryId, type, setDialogState);
            }
            final docs = _verlaufDocs[entryId] ?? [];
            final isLoading = _verlaufDocsLoading[entryId] == true;

          return DefaultTabController(
            length: 2,
            child: AlertDialog(
              titlePadding: EdgeInsets.zero,
              contentPadding: EdgeInsets.zero,
              title: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
                    decoration: BoxDecoration(
                      color: tc.$3.withValues(alpha: 0.1),
                      borderRadius: const BorderRadius.only(topLeft: Radius.circular(28), topRight: Radius.circular(28)),
                    ),
                    child: Row(children: [
                      Icon(tc.$2, size: 20, color: tc.$3),
                      const SizedBox(width: 8),
                      Expanded(child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(entry['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Text(isEingang ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 10, color: tc.$3, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 8),
                            Icon(mc.$2, size: 12, color: Colors.grey.shade500),
                            const SizedBox(width: 3),
                            Text(mc.$1, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                            const SizedBox(width: 8),
                            Text(entry['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                          ]),
                        ],
                      )),
                      // Delete entry
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                        tooltip: 'Eintrag löschen',
                        onPressed: () {
                          showDialog(
                            context: dCtx2,
                            builder: (dc) => AlertDialog(
                              title: const Text('Eintrag löschen?', style: TextStyle(fontSize: 14)),
                              content: Text('„${entry['betreff']}" und alle Dokumente wirklich löschen?', style: const TextStyle(fontSize: 12)),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Abbrechen')),
                                FilledButton(
                                  style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                  onPressed: () {
                                    Navigator.pop(dc);
                                    Navigator.pop(dCtx);
                                    verlauf.removeAt(entryIdx);
                                    data['verlauf'] = verlauf;
                                    _gesundheitData[type] = data;
                                    saveData();
                                    setVaState(() {});
                                  },
                                  child: const Text('Löschen', style: TextStyle(fontSize: 12)),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(dCtx),
                      ),
                    ]),
                  ),
                  // Tabs
                  TabBar(
                    labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    unselectedLabelStyle: const TextStyle(fontSize: 12),
                    tabs: [
                      const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                      Tab(icon: Badge(
                        isLabelVisible: docs.isNotEmpty,
                        label: Text('${docs.length}', style: const TextStyle(fontSize: 9)),
                        child: const Icon(Icons.folder_open, size: 16),
                      ), text: 'Dokumente'),
                    ],
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                height: 400,
                child: TabBarView(
                  children: [
                    // ── TAB 1: DETAILS ──
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Richtung
                          Row(children: [
                            Icon(tc.$2, size: 18, color: tc.$3),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(color: tc.$3.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                              child: Text(isEingang ? 'Eingang (Versorgungsamt → Sie)' : 'Ausgang (Sie → Versorgungsamt)',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: tc.$3)),
                            ),
                          ]),
                          const SizedBox(height: 14),
                          // Versandart
                          _detailRow(Icons.send, 'Versandart', mc.$1),
                          const SizedBox(height: 10),
                          // Datum
                          _detailRow(Icons.event, 'Datum', entry['datum']?.toString() ?? '—'),
                          const SizedBox(height: 10),
                          // Betreff
                          _detailRow(Icons.subject, 'Betreff', entry['betreff']?.toString() ?? '—'),
                          const SizedBox(height: 14),
                          // Notiz
                          Text('Notiz / Inhalt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                          const SizedBox(height: 6),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                            child: Text(
                              entry['notiz']?.toString().isNotEmpty == true ? entry['notiz'].toString() : 'Keine Notiz',
                              style: TextStyle(fontSize: 12, color: entry['notiz']?.toString().isNotEmpty == true ? Colors.black87 : Colors.grey.shade400, fontStyle: entry['notiz']?.toString().isNotEmpty == true ? FontStyle.normal : FontStyle.italic),
                            ),
                          ),
                          const SizedBox(height: 14),
                          // ── Arbeitgeber benachrichtigt ──
                          _buildArbeitgeberBenachrichtigtSection(entry, verlauf, entryIdx, data, type, saveData, setVaState, setDialogState),
                          const SizedBox(height: 14),
                          // Erstellt am
                          if (entry['erstellt_am'] != null)
                            Text('Erstellt: ${entry['erstellt_am'].toString().substring(0, math.min(19, entry['erstellt_am'].toString().length))}',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                        ],
                      ),
                    ),

                    // ── TAB 2: DOKUMENTE ──
                    Column(
                      children: [
                        // Upload bar
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: Colors.grey.shade200))),
                          child: Row(children: [
                            Icon(Icons.cloud_upload, size: 16, color: Colors.purple.shade600),
                            const SizedBox(width: 8),
                            Text('${docs.length} Dokument${docs.length != 1 ? 'e' : ''}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                            const Spacer(),
                            FilledButton.icon(
                              icon: const Icon(Icons.upload_file, size: 16),
                              label: const Text('Hochladen', style: TextStyle(fontSize: 11)),
                              style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8)),
                              onPressed: () async {
                                final result = await FilePicker.platform.pickFiles(
                                  type: FileType.any,
                                  allowMultiple: true,
                                );
                                if (result == null || result.files.isEmpty) return;
                                if (!mounted) return;

                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                  content: Text('${result.files.length} Dokument${result.files.length > 1 ? 'e' : ''} werden hochgeladen...'),
                                  backgroundColor: Colors.blue, duration: const Duration(seconds: 3),
                                ));

                                int uploaded = 0;
                                for (final f in result.files) {
                                  if (f.path == null) continue;
                                  try {
                                    await widget.apiService.uploadGesundheitDoc(
                                      userId: widget.user.id,
                                      gesundheitType: type,
                                      analyseId: entryId,
                                      filePath: f.path!,
                                      fileName: f.name,
                                    );
                                    uploaded++;
                                  } catch (_) {}
                                }

                                if (!mounted) return;
                                // Reload
                                final listRes = await widget.apiService.listGesundheitDocs(userId: widget.user.id, gesundheitType: type, analyseId: entryId);
                                if (!mounted) return;
                                _verlaufDocs[entryId] = List<Map<String, dynamic>>.from(listRes['documents'] ?? []);
                                setDialogState(() {});
                                setVaState(() {});
                                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$uploaded Dokument${uploaded > 1 ? 'e' : ''} hochgeladen'), backgroundColor: Colors.green));
                              },
                            ),
                          ]),
                        ),

                        // Document list
                        Expanded(
                          child: isLoading
                              ? const Center(child: CircularProgressIndicator())
                              : docs.isEmpty
                                  ? Center(child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.folder_open, size: 40, color: Colors.grey.shade300),
                                        const SizedBox(height: 8),
                                        Text('Keine Dokumente', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                        const SizedBox(height: 4),
                                        Text('Klicken Sie "Hochladen" um Dokumente hinzuzufügen', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                                      ],
                                    ))
                                  : ListView.separated(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: docs.length,
                                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                                      itemBuilder: (_, i) {
                                        final doc = docs[i];
                                        final docId = doc['id'] is int ? doc['id'] as int : int.tryParse(doc['id'].toString()) ?? 0;
                                        final filename = doc['filename']?.toString() ?? 'Dokument';
                                        final mimeType = doc['mime_type']?.toString() ?? '';
                                        final fileSize = doc['file_size'] is int ? doc['file_size'] as int : int.tryParse(doc['file_size'].toString()) ?? 0;
                                        final isPdf = mimeType.contains('pdf');
                                        final isImage = mimeType.contains('image');
                                        final createdAt = doc['created_at']?.toString() ?? '';

                                        return Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(
                                            color: Colors.white,
                                            borderRadius: BorderRadius.circular(8),
                                            border: Border.all(color: Colors.grey.shade200),
                                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 4)],
                                          ),
                                          child: Row(children: [
                                            // File icon
                                            Container(
                                              width: 38, height: 38,
                                              decoration: BoxDecoration(
                                                color: isPdf ? Colors.red.shade50 : isImage ? Colors.blue.shade50 : Colors.grey.shade50,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Icon(
                                                isPdf ? Icons.picture_as_pdf : isImage ? Icons.image : Icons.insert_drive_file,
                                                size: 20,
                                                color: isPdf ? Colors.red.shade600 : isImage ? Colors.blue.shade600 : Colors.grey.shade600,
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(filename, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                                Row(children: [
                                                  Text(_formatFileSize(fileSize), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                                  if (createdAt.isNotEmpty) ...[
                                                    Text(' · ', style: TextStyle(color: Colors.grey.shade400)),
                                                    Text(createdAt.length >= 10 ? createdAt.substring(0, 10) : createdAt, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                                  ],
                                                ]),
                                              ],
                                            )),
                                            // Preview (eye)
                                            IconButton(
                                              icon: Icon(Icons.visibility, size: 18, color: Colors.purple.shade600),
                                              tooltip: 'Vorschau',
                                              onPressed: () async {
                                                try {
                                                  final bytes = await widget.apiService.downloadGesundheitDoc(docId);
                                                  if (!mounted || bytes == null) return;
                                                  final uint8Bytes = Uint8List.fromList(bytes);
                                                  if (!mounted) return;
                                                  await FileViewerDialog.showFromBytes(context, uint8Bytes, filename);
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                                                }
                                              },
                                            ),
                                            // Download
                                            IconButton(
                                              icon: Icon(Icons.download, size: 18, color: Colors.blue.shade600),
                                              tooltip: 'Herunterladen',
                                              onPressed: () async {
                                                try {
                                                  final bytes = await widget.apiService.downloadGesundheitDoc(docId);
                                                  if (!mounted || bytes == null) return;
                                                  final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
                                                  final file = File('${dir.path}/$filename');
                                                  await file.writeAsBytes(bytes);
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gespeichert: ${file.path}'), backgroundColor: Colors.green));
                                                } catch (e) {
                                                  if (!mounted) return;
                                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                                                }
                                              },
                                            ),
                                            // Delete
                                            IconButton(
                                              icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                                              tooltip: 'Löschen',
                                              onPressed: () {
                                                showDialog(
                                                  context: dCtx2,
                                                  builder: (dc) => AlertDialog(
                                                    title: const Text('Dokument löschen?', style: TextStyle(fontSize: 14)),
                                                    content: Text('„$filename" wirklich löschen?', style: const TextStyle(fontSize: 12)),
                                                    actions: [
                                                      TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Abbrechen')),
                                                      FilledButton(
                                                        style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                        onPressed: () async {
                                                          Navigator.pop(dc);
                                                          try {
                                                            await widget.apiService.deleteGesundheitDoc(docId);
                                                            final listRes = await widget.apiService.listGesundheitDocs(userId: widget.user.id, gesundheitType: type, analyseId: entryId);
                                                            if (!mounted) return;
                                                            _verlaufDocs[entryId] = List<Map<String, dynamic>>.from(listRes['documents'] ?? []);
                                                            setDialogState(() {});
                                                            setVaState(() {});
                                                          } catch (_) {}
                                                        },
                                                        child: const Text('Löschen', style: TextStyle(fontSize: 12)),
                                                      ),
                                                    ],
                                                  ),
                                                );
                                              },
                                            ),
                                          ]),
                                        );
                                      },
                                    ),
                        ),
                      ],
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

  Widget _buildArbeitgeberBenachrichtigtSection(
    Map<String, dynamic> entry,
    List<Map<String, dynamic>> verlauf,
    int entryIdx,
    Map<String, dynamic> data,
    String type,
    Future<void> Function() saveData,
    void Function(void Function()) setVaState,
    void Function(void Function()) setDialogState,
  ) {
    final bool benachrichtigt = entry['ag_benachrichtigt'] == true;
    final String agDatum = entry['ag_datum']?.toString() ?? '';
    final String agMethode = entry['ag_methode']?.toString() ?? '';
    final bool isComplete = benachrichtigt && agDatum.isNotEmpty && agMethode.isNotEmpty;
    final bool isEditing = entry['_ag_editing'] == true;

    final methoden = {
      'online': ('Online', Icons.language),
      'telefonisch': ('Telefonisch', Icons.phone),
      'email': ('Per E-Mail', Icons.email),
      'persoenlich': ('Persoenlich', Icons.person),
    };

    void doSave() {
      entry.remove('_ag_editing');
      verlauf[entryIdx] = entry;
      data['verlauf'] = verlauf;
      _gesundheitData[type] = data;
      saveData();
      setVaState(() {});
    }

    // Read-only mode: data is complete and not editing
    if (isComplete && !isEditing) {
      final mc = methoden[agMethode];
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                const SizedBox(width: 6),
                Text('Arbeitgeber benachrichtigt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                const Spacer(),
                InkWell(
                  onTap: () {
                    setDialogState(() => entry['_ag_editing'] = true);
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.edit, size: 16, color: Colors.blue.shade600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.event, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text('Am: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Text(_formatDate(agDatum), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
            const SizedBox(height: 4),
            Row(children: [
              Icon(mc?.$2 ?? Icons.send, size: 14, color: Colors.grey.shade500),
              const SizedBox(width: 6),
              Text('Art: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              Text(mc?.$1 ?? agMethode, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
            ]),
          ],
        ),
      );
    }

    // Edit mode
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: benachrichtigt ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: benachrichtigt ? Colors.green.shade200 : Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(benachrichtigt ? Icons.check_circle : Icons.warning_amber, size: 16, color: benachrichtigt ? Colors.green.shade700 : Colors.orange.shade700),
              const SizedBox(width: 6),
              Text('Arbeitgeber benachrichtigt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: benachrichtigt ? Colors.green.shade700 : Colors.orange.shade700)),
              const Spacer(),
              Switch(
                value: benachrichtigt,
                activeThumbColor: Colors.green.shade600,
                onChanged: (v) {
                  setDialogState(() {
                    entry['ag_benachrichtigt'] = v;
                    if (!v) {
                      entry.remove('ag_datum');
                      entry.remove('ag_methode');
                      entry.remove('_ag_editing');
                    }
                  });
                  doSave();
                },
              ),
            ],
          ),
          if (benachrichtigt) ...[
            const SizedBox(height: 8),
            // Datum
            Row(
              children: [
                Icon(Icons.event, size: 14, color: Colors.green.shade600),
                const SizedBox(width: 6),
                Text('Benachrichtigt am:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime.tryParse(agDatum) ?? DateTime.now(),
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2040),
                      locale: const Locale('de'),
                    );
                    if (picked != null) {
                      final formatted = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                      setDialogState(() => entry['ag_datum'] = formatted);
                      doSave();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade300),
                    ),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(
                        agDatum.isNotEmpty ? _formatDate(agDatum) : 'Datum wahlen',
                        style: TextStyle(fontSize: 12, color: agDatum.isNotEmpty ? Colors.black87 : Colors.grey.shade400),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.edit_calendar, size: 14, color: Colors.green.shade600),
                    ]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Methode
            Text('Art der Benachrichtigung:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: methoden.entries.map((m) {
                final sel = agMethode == m.key;
                return ChoiceChip(
                  label: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(m.value.$2, size: 13, color: sel ? Colors.white : Colors.grey.shade700),
                    const SizedBox(width: 4),
                    Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.grey.shade700)),
                  ]),
                  selected: sel,
                  selectedColor: Colors.green.shade600,
                  backgroundColor: Colors.white,
                  side: BorderSide(color: sel ? Colors.green.shade600 : Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  onSelected: (_) {
                    setDialogState(() => entry['ag_methode'] = m.key);
                    doSave();
                  },
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDate(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(children: [
      Icon(icon, size: 16, color: Colors.grey.shade500),
      const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
    ]);
  }

  Widget _buildArztContent(String baseType, String arztTitle, String fachrichtung) {
    // Multi-doctor: load instance_count from base data and auto-load sub-types
    if (!_multiArztCount.containsKey(baseType) && _gesundheitData.containsKey(baseType)) {
      final baseData = _gesundheitData[baseType] ?? {};
      final savedCount = baseData['instance_count'];
      if (savedCount != null && savedCount is int && savedCount > 1) {
        _multiArztCount[baseType] = savedCount;
        for (int i = 2; i <= savedCount; i++) {
          final subType = '${baseType}_$i';
          if (!_gesundheitData.containsKey(subType) && _gesundheitLoading[subType] != true) {
            _loadGesundheitData(subType);
          }
        }
      } else {
        _multiArztCount[baseType] = 1;
      }
    }
    final count = _multiArztCount[baseType] ?? 1;
    // Use getter so type is always current (not stale closure)
    String getActiveType() {
      final idx = _multiArztSelected[baseType] ?? 0;
      return idx == 0 ? baseType : '${baseType}_${idx + 1}';
    }
    final type = getActiveType();

    if (!_gesundheitData.containsKey(type) && _gesundheitLoading[type] != true) {
      _loadGesundheitData(type);
    }
    if (_gesundheitLoading[type] == true) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = _gesundheitData[type] ?? {};
    Map<String, dynamic> selectedArzt = data['arzt_id'] != null
        ? Map<String, dynamic>.from(data['selected_arzt'] ?? {})
        : {};
    String? arztId = data['arzt_id']?.toString();
    // Auto-refresh arzt data from DB if telefon or online_termin_url is missing
    if (arztId != null && selectedArzt.isNotEmpty && ((selectedArzt['telefon']?.toString() ?? '').isEmpty || (selectedArzt['online_termin_url']?.toString() ?? '').isEmpty)) {
      final refreshKey = '${type}_arzt_refreshed';
      if (data[refreshKey] != true) {
        data[refreshKey] = true;
        widget.apiService.searchAerzte(search: selectedArzt['arzt_name']?.toString() ?? selectedArzt['praxis_name']?.toString() ?? '').then((result) {
          final aerzte = result['aerzte'] as List? ?? [];
          for (final a in aerzte) {
            if (a['id'].toString() == arztId) {
              if (mounted) {
                setState(() {
                  selectedArzt = Map<String, dynamic>.from(a as Map);
                  data['selected_arzt'] = selectedArzt;
                  _gesundheitData[type] = data;
                });
                widget.apiService.saveGesundheitData(widget.user.id, type, data);
              }
              break;
            }
          }
        });
      }
    }
    final behandelnderArztController = TextEditingController(text: data['behandelnder_arzt'] ?? '');
    final letzterBesuchController = TextEditingController(text: data['letzter_besuch'] ?? '');
    final naechsterTerminController = TextEditingController(text: data['naechster_termin'] ?? '');
    final diagnoseController = TextEditingController(text: data['diagnose'] ?? '');
    final medikamenteController = TextEditingController(text: data['medikamente'] ?? '');
    final notizenController = TextEditingController(text: data['notizen'] ?? '');

    void saveAll() {
      final activeType = getActiveType();
      final activeData = _gesundheitData[activeType] ?? {};
      final rezCount = (activeData['rezepte'] as List?)?.length ?? 0;
      debugPrint('[SAVE-ALL] CALLED rezepte=$rezCount caller=${StackTrace.current.toString().split('\n').take(3).join(' | ')}');
      // Update in-place (don't replace reference - other widgets hold pointers to activeData)
      activeData['arzt_id'] = arztId;
      activeData['selected_arzt'] = selectedArzt;
      activeData['behandelnder_arzt'] = behandelnderArztController.text.trim();
      activeData['letzter_besuch'] = letzterBesuchController.text.trim();
      activeData['naechster_termin'] = naechsterTerminController.text.trim();
      activeData['diagnose'] = diagnoseController.text.trim();
      activeData['medikamente'] = medikamenteController.text.trim();
      activeData['notizen'] = notizenController.text.trim();
      _gesundheitData[activeType] = activeData;
      debugPrint('[SAVE-ALL] type=$activeType rezepte=${(activeData['rezepte'] as List?)?.length ?? 0} heilmittel=${(activeData['heilmittel'] as List?)?.length ?? 0} identical=${identical(activeData, data)}');
      widget.apiService.saveGesundheitData(widget.user.id, activeType, activeData).then((result) {
        if (mounted && result['success'] == true) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)),
          );
        }
      });
    }

    // Auto-save on focus lost: use onChanged in text fields instead of listeners
    // (listeners in build cause infinite rebuilds)

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return DefaultTabController(
          length: 11,
          child: Column(
            children: [
              // Multi-doctor tab bar (always visible, with + button to add more)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  border: Border(bottom: BorderSide(color: Colors.teal.shade200)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (int i = 0; i < count; i++) ...[
                      () {
                        final iType = i == 0 ? baseType : '${baseType}_${i + 1}';
                        final iData = _gesundheitData[iType] ?? {};
                        final iArzt = (iData['selected_arzt'] is Map) ? iData['selected_arzt'] as Map : {};
                        final iName = iArzt['praxis_name']?.toString() ?? iArzt['arzt_name']?.toString() ?? '$arztTitle ${i + 1}';
                        final isSel = (_multiArztSelected[baseType] ?? 0) == i;
                        return Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: InkWell(
                            onTap: () => setState(() => _multiArztSelected[baseType] = i),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: isSel ? Colors.teal.shade600 : Colors.white,
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                                border: Border.all(color: isSel ? Colors.teal.shade600 : Colors.teal.shade200),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_hospital,
                                    size: 14,
                                    color: isSel ? Colors.white : Colors.teal.shade700,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    iName,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                                      color: isSel ? Colors.white : Colors.teal.shade700,
                                    ),
                                  ),
                                  if (i > 0 && isSel) ...[
                                    const SizedBox(width: 8),
                                    InkWell(
                                      onTap: () async {
                                        final confirm = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: Text('$arztTitle entfernen?'),
                                            content: Text('Möchten Sie "$iName" wirklich entfernen? Alle Daten (Termine, Rezepte, etc.) werden gelöscht.'),
                                            actions: [
                                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                              TextButton(
                                                onPressed: () => Navigator.pop(ctx, true),
                                                style: TextButton.styleFrom(foregroundColor: Colors.red),
                                                child: const Text('Entfernen'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (confirm == true) {
                                          // Shift remaining sub-types down: move _{i+2} → _{i+1}, etc.
                                          // Then clear the last slot on the server so no stale data remains.
                                          for (int j = i + 1; j < count; j++) {
                                            final fromType = j == 0 ? baseType : '${baseType}_${j + 1}';
                                            final toType = j == 1 ? baseType : '${baseType}_$j';
                                            final moved = _gesundheitData[fromType];
                                            if (moved != null) {
                                              _gesundheitData[toType] = moved;
                                              widget.apiService.saveGesundheitData(widget.user.id, toType, moved);
                                            }
                                          }
                                          // Clear the (now-empty) last slot on the server
                                          final lastType = count == 1 ? baseType : '${baseType}_$count';
                                          _gesundheitData.remove(lastType);
                                          widget.apiService.saveGesundheitData(widget.user.id, lastType, {});

                                          final newCount = count - 1;
                                          final baseData = Map<String, dynamic>.from(_gesundheitData[baseType] ?? {});
                                          baseData['instance_count'] = newCount;
                                          _gesundheitData[baseType] = baseData;
                                          widget.apiService.saveGesundheitData(widget.user.id, baseType, baseData);
                                          setState(() {
                                            _multiArztCount[baseType] = newCount;
                                            _multiArztSelected[baseType] = (i - 1).clamp(0, newCount - 1);
                                          });
                                        }
                                      },
                                      child: Tooltip(
                                        message: 'Entfernen',
                                        child: Container(
                                          padding: const EdgeInsets.all(2),
                                          child: Icon(Icons.close, size: 16, color: Colors.white.withValues(alpha: 0.9)),
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      }(),
                    ],
                    // "+" button to add another doctor
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: InkWell(
                        onTap: () {
                          final newCount = count + 1;
                          final newType = '${baseType}_$newCount';
                          _showArztSucheDialog(context, fachrichtung, (arzt) {
                            final baseData = Map<String, dynamic>.from(_gesundheitData[baseType] ?? {});
                            baseData['instance_count'] = newCount;
                            _gesundheitData[baseType] = baseData;
                            widget.apiService.saveGesundheitData(widget.user.id, baseType, baseData);
                            final newData = <String, dynamic>{
                              'arzt_id': arzt['id']?.toString(),
                              'selected_arzt': Map<String, dynamic>.from(arzt as Map),
                            };
                            _gesundheitData[newType] = newData;
                            widget.apiService.saveGesundheitData(widget.user.id, newType, newData);
                            if (mounted) {
                              setState(() {
                                _multiArztCount[baseType] = newCount;
                                _multiArztSelected[baseType] = newCount - 1;
                                _gesundheitLoading[newType] = false;
                              });
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade100,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.teal.shade300, style: BorderStyle.solid),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 16, color: Colors.teal.shade700),
                              const SizedBox(width: 4),
                              Text(
                                'Weiterer $arztTitle',
                                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.teal.shade700),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
              TabBar(
                labelColor: Colors.teal.shade700,
                unselectedLabelColor: Colors.grey.shade500,
                indicatorColor: Colors.teal.shade700,
                isScrollable: true,
                tabs: const [
                  Tab(icon: Icon(Icons.local_hospital, size: 16), text: 'Arzt'),
                  Tab(icon: Icon(Icons.calendar_month, size: 16), text: 'Termine'),
                  Tab(icon: Icon(Icons.medication, size: 16), text: 'Medikamente'),
                  Tab(icon: Icon(Icons.note, size: 16), text: 'Notizen'),
                  Tab(icon: Icon(Icons.bloodtype, size: 16), text: 'Blutanalyse'),
                  Tab(icon: Icon(Icons.health_and_safety, size: 16), text: 'Vorsorge'),
                  Tab(icon: Icon(Icons.local_hospital, size: 16), text: 'Krankmeldungen'),
                  Tab(icon: Icon(Icons.swap_horiz, size: 16), text: 'Überweisung'),
                  Tab(icon: Icon(Icons.receipt_long, size: 16), text: 'Rezept'),
                  Tab(icon: Icon(Icons.healing, size: 16), text: 'Heilmittel'),
                  Tab(icon: Icon(Icons.description, size: 16), text: 'Berichte'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    // ===== TAB 1: ARZT (Doctor selection) =====
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (arztId == null || selectedArzt.isEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(24),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.grey.shade300),
                              ),
                              child: Column(
                                children: [
                                  Icon(Icons.person_search, size: 48, color: Colors.grey.shade400),
                                  const SizedBox(height: 8),
                                  Text('Kein $arztTitle zugewiesen', style: TextStyle(fontSize: 15, color: Colors.grey.shade600)),
                                  const SizedBox(height: 12),
                                  ElevatedButton.icon(
                                    onPressed: () => _showArztSucheDialog(context, fachrichtung, (arzt) {
                                      setLocalState(() {
                                        selectedArzt = Map<String, dynamic>.from(arzt);
                                        arztId = arzt['id']?.toString();
                                      });
                                      _saveGesundheitData(type, {
                                        'arzt_id': arzt['id']?.toString(),
                                        'selected_arzt': arzt,
                                        'behandelnder_arzt': '',
                                        'letzter_besuch': '',
                                        'naechster_termin': '',
                                        'diagnose': '',
                                        'medikamente': '',
                                        'notizen': '',
                                      });
                                    }),
                                    icon: const Icon(Icons.search, size: 18),
                                    label: Text('$arztTitle auswählen'),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // Doctor info card
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: Colors.teal.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.teal.shade200),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: Colors.teal.shade100,
                                        radius: 22,
                                        child: Icon(Icons.local_hospital, color: Colors.teal.shade700, size: 22),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(selectedArzt['praxis_name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                                            Text(selectedArzt['arzt_name'] ?? '', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                            if (selectedArzt['weitere_aerzte']?.isNotEmpty == true)
                                              Text(selectedArzt['weitere_aerzte'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.swap_horiz, color: Colors.teal),
                                        tooltip: '$arztTitle wechseln',
                                        onPressed: () => _showArztSucheDialog(context, fachrichtung, (arzt) {
                                          setLocalState(() {
                                            selectedArzt = Map<String, dynamic>.from(arzt);
                                            arztId = arzt['id']?.toString();
                                          });
                                          _saveGesundheitData(type, {
                                            'arzt_id': arzt['id']?.toString(),
                                            'selected_arzt': arzt,
                                            'behandelnder_arzt': behandelnderArztController.text.trim(),
                                            'letzter_besuch': letzterBesuchController.text.trim(),
                                            'naechster_termin': naechsterTerminController.text.trim(),
                                            'diagnose': diagnoseController.text.trim(),
                                            'medikamente': medikamenteController.text.trim(),
                                            'notizen': notizenController.text.trim(),
                                          });
                                        }),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.remove_circle_outline, color: Colors.red.shade400),
                                        tooltip: '$arztTitle entfernen',
                                        onPressed: () {
                                          setLocalState(() {
                                            selectedArzt = {};
                                            arztId = null;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Divider(color: Colors.teal.shade200, height: 1),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 24,
                                    runSpacing: 8,
                                    children: [
                                      if (selectedArzt['strasse']?.isNotEmpty == true || selectedArzt['plz_ort']?.isNotEmpty == true)
                                        _arztInfoChip(Icons.location_on, '${selectedArzt['strasse'] ?? ''}, ${selectedArzt['plz_ort'] ?? ''}'),
                                      if (selectedArzt['telefon']?.isNotEmpty == true)
                                        _arztInfoChip(Icons.phone, selectedArzt['telefon']),
                                      if (selectedArzt['fax']?.isNotEmpty == true)
                                        _arztInfoChip(Icons.fax, 'Fax: ${selectedArzt['fax']}'),
                                      if (selectedArzt['email']?.isNotEmpty == true)
                                        _arztInfoChip(Icons.email, selectedArzt['email']),
                                      if (selectedArzt['website']?.isNotEmpty == true)
                                        _arztInfoChip(Icons.language, selectedArzt['website']),
                                      if (selectedArzt['sprechzeiten']?.isNotEmpty == true)
                                        _arztInfoChip(Icons.schedule, selectedArzt['sprechzeiten']),
                                    ],
                                  ),
                                  if (selectedArzt['notizen']?.isNotEmpty == true) ...[
                                    const SizedBox(height: 8),
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade200)),
                                      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Icon(Icons.info_outline, size: 14, color: Colors.amber.shade700),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text(selectedArzt['notizen'], style: TextStyle(fontSize: 11, color: Colors.amber.shade900))),
                                      ]),
                                    ),
                                  ],
                                  // LANR / BSNR row
                                  if ((selectedArzt['lanr']?.isNotEmpty == true) || (selectedArzt['bsnr']?.isNotEmpty == true)) ...[
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        if (selectedArzt['lanr']?.isNotEmpty == true)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.indigo.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.indigo.shade200),
                                            ),
                                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                                              Icon(Icons.badge, size: 12, color: Colors.indigo.shade600),
                                              const SizedBox(width: 4),
                                              Text('LANR: ${selectedArzt['lanr']}', style: TextStyle(fontSize: 11, color: Colors.indigo.shade800, fontWeight: FontWeight.w600)),
                                            ]),
                                          ),
                                        if (selectedArzt['bsnr']?.isNotEmpty == true)
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                            margin: const EdgeInsets.only(right: 8),
                                            decoration: BoxDecoration(
                                              color: Colors.purple.shade50,
                                              borderRadius: BorderRadius.circular(6),
                                              border: Border.all(color: Colors.purple.shade200),
                                            ),
                                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                                              Icon(Icons.business, size: 12, color: Colors.purple.shade600),
                                              const SizedBox(width: 4),
                                              Text('BSNR: ${selectedArzt['bsnr']}', style: TextStyle(fontSize: 11, color: Colors.purple.shade800, fontWeight: FontWeight.w600)),
                                            ]),
                                          ),
                                        const Spacer(),
                                        TextButton.icon(
                                          icon: Icon(Icons.edit, size: 14, color: Colors.grey.shade600),
                                          label: Text('LANR/BSNR', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                          style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
                                          onPressed: () => _showArztNummernDialog(context, selectedArzt, (updated) {
                                            setLocalState(() {
                                              selectedArzt['lanr'] = updated['lanr'];
                                              selectedArzt['bsnr'] = updated['bsnr'];
                                              data['selected_arzt'] = selectedArzt;
                                            });
                                            saveAll();
                                          }),
                                        ),
                                      ],
                                    ),
                                  ] else ...[
                                    const SizedBox(height: 6),
                                    Align(
                                      alignment: Alignment.centerLeft,
                                      child: TextButton.icon(
                                        icon: Icon(Icons.add, size: 14, color: Colors.grey.shade500),
                                        label: Text('LANR / BSNR hinzufügen', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
                                        onPressed: () => _showArztNummernDialog(context, selectedArzt, (updated) {
                                          setLocalState(() {
                                            selectedArzt['lanr'] = updated['lanr'];
                                            selectedArzt['bsnr'] = updated['bsnr'];
                                            data['selected_arzt'] = selectedArzt;
                                          });
                                          saveAll();
                                        }),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            _buildBehoerdeSectionHeader(Icons.person, 'Behandelnder Arzt', Colors.teal.shade700),
                            const SizedBox(height: 8),
                            _buildBehoerdeTextField('Zuständiger Arzt für dieses Mitglied', behandelnderArztController,
                                hint: 'z.B. Dr. med. Michael Lankes', icon: Icons.person_pin),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              children: [
                                TextButton.icon(
                                  onPressed: saveAll,
                                  icon: Icon(Icons.save, size: 14, color: Colors.teal.shade600),
                                  label: Text('Speichern', style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    // ===== TAB 2: TERMINE (Appointments from DB) =====
                    _buildArztTermineTab(type, arztTitle, data: data, saveAll: saveAll, setLocalState: setLocalState),

                    // ===== TAB 3: MEDIKAMENTE (DB-based) =====
                    _buildArztMedikamenteTab(type, arztTitle),

                    // ===== TAB 4: NOTIZEN =====
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBehoerdeSectionHeader(Icons.note, 'Notizen', Colors.teal.shade700),
                          const SizedBox(height: 12),
                          _buildBehoerdeTextField('Zusätzliche Informationen', notizenController,
                              hint: 'Notizen zum Mitglied bei diesem Arzt...', icon: Icons.note, maxLines: 8),
                        ],
                      ),
                    ),

                    // ===== TAB 5: BLUTANALYSE =====
                    _buildBlutanalyseTab(type, arztTitle, data, saveAll, setLocalState),

                    // ===== TAB 6: VORSORGE (HPV/Pap) =====
                    _buildVorsorgeTab(type, arztTitle, data, saveAll, setLocalState),

                    // ===== TAB 7: KRANKMELDUNGEN =====
                    _buildKrankmeldungenTab(type, arztTitle, data, saveAll, setLocalState),

                    // ===== TAB 7: ÜBERWEISUNG =====
                    _buildUeberweisungTab(type, arztTitle, data, saveAll, setLocalState),

                    // ===== TAB 8: REZEPT =====
                    _buildRezeptTab(type, arztTitle, data, saveAll, setLocalState),

                    // ===== TAB 9: HEILMITTEL =====
                    _buildHeilmittelTab(type, arztTitle, data, saveAll, setLocalState),

                    // ===== TAB 10: BERICHTE =====
                    _buildBerichteTab(type, arztTitle, data, saveAll, setLocalState),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _arztInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.teal.shade600),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  // ========== HELPER: Nächster Werktag (Mo-Fr) ==========
  DateTime _nextWeekday(DateTime date) {
    // Samstag → Montag, Sonntag → Montag
    if (date.weekday == DateTime.saturday) return date.add(const Duration(days: 2));
    if (date.weekday == DateTime.sunday) return date.add(const Duration(days: 1));
    return date;
  }

  // ========== VORSORGE-BEZEICHNUNG ==========

  String _getVorsorgeBezeichnung(String type) {
    final map = {
      'gesundheit_hausarzt': 'Gesundheits-Check-up / Vorsorgeuntersuchung',
      'gesundheit_augenarzt': 'Augenärztliche Vorsorgeuntersuchung',
      'gesundheit_lungenarzt': 'Lungenfunktionsprüfung / Vorsorgeuntersuchung',
      'gesundheit_hno': 'HNO-Vorsorgeuntersuchung',
      'gesundheit_psychiater': 'Psychiatrische / Psychologische Untersuchung',
      'gesundheit_kardiologe': 'Kardiologische Vorsorgeuntersuchung',
      'gesundheit_neurologe': 'Neurologische Vorsorgeuntersuchung',
      'gesundheit_orthopaede': 'Orthopädische Untersuchung',
      'gesundheit_hautarzt': 'Hautkrebs-Screening / Dermatologische Vorsorge',
      'gesundheit_zahnarzt': 'Zahnärztliche Kontrolluntersuchung (halbjährlich)',
      'gesundheit_gynaekologie': 'Gynäkologische Vorsorgeuntersuchung',
      'gesundheit_urologie': 'Urologische Vorsorgeuntersuchung',
      'gesundheit_onkologie': 'Onkologische Nachsorge / Vorsorgeuntersuchung',
      'gesundheit_krankenhaus': 'Ambulante Untersuchung',
      'gesundheit_sonstige': 'Fachärztliche Untersuchung',
    };
    return map[type] ?? 'Vorsorgeuntersuchung';
  }

  // ========== VORSORGE-ERINNERUNG ==========

  Widget _buildVorsorgeErinnerung(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    String erinnerungIntervall = data['vorsorge_intervall']?.toString() ?? '';
    String erinnerungTicketDate = data['vorsorge_ticket_date']?.toString() ?? '';

    final termine = _arztTermine[type] ?? [];
    DateTime? letzterTermin;
    for (final t in termine) {
      final parsed = DateTime.tryParse(t['datum']?.toString() ?? '');
      if (parsed != null && (letzterTermin == null || parsed.isAfter(letzterTermin))) {
        letzterTermin = parsed;
      }
    }

    DateTime? naechsteFaellig;
    DateTime? erinnerungDatum;
    bool keinTerminVorhanden = false;
    if (erinnerungIntervall.isNotEmpty) {
      final monate = int.tryParse(erinnerungIntervall) ?? 0;
      if (monate > 0) {
        if (letzterTermin != null) {
          naechsteFaellig = _nextWeekday(DateTime(letzterTermin.year, letzterTermin.month + monate, letzterTermin.day));
          erinnerungDatum = _nextWeekday(DateTime(naechsteFaellig.year, naechsteFaellig.month - 1, naechsteFaellig.day));
        } else {
          keinTerminVorhanden = true;
          naechsteFaellig = DateTime.now();
          erinnerungDatum = DateTime.now();
        }
      }
    }

    final now = DateTime.now();
    final isUeberfaellig = keinTerminVorhanden || (naechsteFaellig != null && now.isAfter(naechsteFaellig));
    final isErinnerungFaellig = keinTerminVorhanden || (erinnerungDatum != null && now.isAfter(erinnerungDatum));

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isUeberfaellig ? Colors.red.shade50 : isErinnerungFaellig ? Colors.orange.shade50 : Colors.blue.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isUeberfaellig ? Colors.red.shade300 : isErinnerungFaellig ? Colors.orange.shade300 : Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.notifications_active, size: 18, color: isUeberfaellig ? Colors.red.shade700 : Colors.blue.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Vorsorge-Erinnerung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isUeberfaellig ? Colors.red.shade800 : Colors.blue.shade800))),
          ]),
          const SizedBox(height: 10),
          Text('Erinnerungsintervall', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: erinnerungIntervall.isEmpty ? null : erinnerungIntervall,
                isExpanded: true,
                hint: const Text('Keine Erinnerung', style: TextStyle(fontSize: 12)),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Keine Erinnerung', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: '3', child: Text('Alle 3 Monate', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: '6', child: Text('Alle 6 Monate', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: '10', child: Text('Alle 10 Monate', style: TextStyle(fontSize: 12))),
                  DropdownMenuItem(value: '12', child: Text('Alle 12 Monate (jährlich)', style: TextStyle(fontSize: 12))),
                ],
                onChanged: (val) async {
                  final newVal = val ?? '';
                  setLocalState(() {
                    data['vorsorge_intervall'] = newVal;
                    data['vorsorge_ticket_date'] = '';
                  });
                  saveAll();
                  // Auto-create ticket only if erinnerung date has passed or no termin
                  if (newVal.isNotEmpty) {
                    final monate = int.tryParse(newVal) ?? 0;
                    if (monate > 0) {
                      final basis = letzterTermin ?? DateTime.now();
                      final faellig = _nextWeekday(DateTime(basis.year, basis.month + monate, basis.day));
                      final erinnerung = _nextWeekday(DateTime(faellig.year, faellig.month - 1, faellig.day));
                      final shouldCreate = letzterTermin == null || DateTime.now().isAfter(erinnerung);
                      if (shouldCreate) {
                        final isOver = faellig.isBefore(DateTime.now()) || letzterTermin == null;
                        final letzteStr = letzterTermin != null ? '${letzterTermin.day.toString().padLeft(2, '0')}.${letzterTermin.month.toString().padLeft(2, '0')}.${letzterTermin.year}' : 'Kein Termin';
                        final erinnerungStr = '${erinnerung.year}-${erinnerung.month.toString().padLeft(2, '0')}-${erinnerung.day.toString().padLeft(2, '0')}';
                        try {
                          final result = await widget.ticketService.createTicketForMember(
                            adminMitgliedernummer: widget.adminMitgliedernummer,
                            memberMitgliedernummer: widget.user.mitgliedernummer,
                            subject: 'Vorsorge-Erinnerung: $arztTitle für ${widget.user.name}',
                            message: 'Sehr geehrtes Mitglied,\n\nIhre $arztTitle-Vorsorgeuntersuchung ist fällig.\n\nIntervall: Alle $newVal Monate\nLetzter Termin: $letzteStr\nFällig bis: ${faellig.day.toString().padLeft(2, '0')}.${faellig.month.toString().padLeft(2, '0')}.${faellig.year}\n\nBitte vereinbaren Sie zeitnah einen Termin.\n\nMit freundlichen Grüßen',
                            priority: isOver ? 'high' : 'medium',
                            scheduledDate: erinnerungStr,
                            systemAuto: true,
                          );
                          if (result.containsKey('ticket')) {
                            final today = DateTime.now();
                            final dateStr = '${today.day.toString().padLeft(2, '0')}.${today.month.toString().padLeft(2, '0')}.${today.year}';
                            setLocalState(() => data['vorsorge_ticket_date'] = dateStr);
                            saveAll();
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erinnerungs-Ticket automatisch erstellt'), backgroundColor: Colors.green));
                          }
                        } catch (_) {}
                      }
                    }
                  }
                },
              ),
            ),
          ),
          if (erinnerungIntervall.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (keinTerminVorhanden)
                    _vorsorgeInfoRow(Icons.error, 'Letzter Termin', 'Kein Termin vorhanden — sofort fällig!', Colors.red)
                  else if (letzterTermin != null)
                    _vorsorgeInfoRow(Icons.event, 'Letzter Termin', '${letzterTermin.day.toString().padLeft(2, '0')}.${letzterTermin.month.toString().padLeft(2, '0')}.${letzterTermin.year}', Colors.teal),
                  const SizedBox(height: 4),
                  if (naechsteFaellig != null && !keinTerminVorhanden) ...[
                    _vorsorgeInfoRow(isUeberfaellig ? Icons.error : Icons.schedule, 'Nächster Termin fällig', '${naechsteFaellig.day.toString().padLeft(2, '0')}.${naechsteFaellig.month.toString().padLeft(2, '0')}.${naechsteFaellig.year}', isUeberfaellig ? Colors.red : Colors.blue),
                    const SizedBox(height: 4),
                    _vorsorgeInfoRow(Icons.notifications, 'Erinnerung (1 Monat vorher)', '${erinnerungDatum!.day.toString().padLeft(2, '0')}.${erinnerungDatum.month.toString().padLeft(2, '0')}.${erinnerungDatum.year}', isErinnerungFaellig ? Colors.orange : Colors.grey),
                  ],
                  if (erinnerungTicketDate.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _vorsorgeInfoRow(Icons.confirmation_num, 'Ticket erstellt am', erinnerungTicketDate, Colors.green),
                  ],
                  if (isUeberfaellig) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                      child: Row(children: [
                        Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Expanded(child: Text(keinTerminVorhanden ? 'Noch kein Termin! Bitte Termin vereinbaren.' : 'Überfällig! Bitte Termin vereinbaren.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                      ]),
                    ),
                  ],
                ],
              ),
            ),
            if (isErinnerungFaellig && erinnerungTicketDate.isEmpty) ...[
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(Icons.confirmation_num, size: 16, color: Colors.orange.shade700),
                  label: Text('Erinnerungs-Ticket jetzt erstellen', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                  style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.orange.shade400), backgroundColor: Colors.orange.shade50),
                  onPressed: () async {
                    try {
                      final letzteStr = letzterTermin != null ? '${letzterTermin.day.toString().padLeft(2, '0')}.${letzterTermin.month.toString().padLeft(2, '0')}.${letzterTermin.year}' : 'Kein Termin';
                      final scheduledDate = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                      await widget.ticketService.createTicketForMember(
                        adminMitgliedernummer: widget.adminMitgliedernummer,
                        memberMitgliedernummer: widget.user.mitgliedernummer,
                        subject: 'Vorsorge-Erinnerung: $arztTitle für ${widget.user.name}',
                        message: 'Sehr geehrtes Mitglied,\n\nIhre $arztTitle-Vorsorgeuntersuchung ist fällig.\n\nIntervall: Alle $erinnerungIntervall Monate\nLetzter Termin: $letzteStr\n\nBitte vereinbaren Sie zeitnah einen Termin.\n\nMit freundlichen Grüßen',
                        priority: isUeberfaellig ? 'high' : 'medium',
                        scheduledDate: scheduledDate,
                        systemAuto: true,
                      );
                      final today = DateTime.now();
                      final dateStr = '${today.day.toString().padLeft(2, '0')}.${today.month.toString().padLeft(2, '0')}.${today.year}';
                      setLocalState(() => data['vorsorge_ticket_date'] = dateStr);
                      saveAll();
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Erinnerungs-Ticket erstellt'), backgroundColor: Colors.green));
                    } catch (e) {
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                    }
                  },
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _vorsorgeInfoRow(IconData icon, String label, String value, Color color) {
    return Row(children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 6),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color))),
    ]);
  }

  // ========== BLUTANALYSE TAB ==========

  Widget _buildBlutanalyseTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    final rawBlut = data['blutanalyse'];
    final blut = rawBlut is Map ? Map<String, dynamic>.from(rawBlut) : (rawBlut is List && rawBlut.isNotEmpty && rawBlut.first is Map ? Map<String, dynamic>.from(rawBlut.first as Map) : <String, dynamic>{});
    final rawHistory = blut['history'];
    final history = rawHistory is List ? List<Map<String, dynamic>>.from(rawHistory.whereType<Map>()) : <Map<String, dynamic>>[];
    String intervall = blut['kontrollintervall']?.toString() ?? '';
    String reminderTicketDate = blut['reminder_ticket_date']?.toString() ?? '';
    bool reminderSent = reminderTicketDate.isNotEmpty;

    final analyseTypen = <String, Map<String, String>>{
      'blutzucker':     {'label': 'Nüchtern-Blutzucker (Glukose)', 'gkv': 'Check-up 35'},
      'blutfette':      {'label': 'Blutfette (Gesamt-Cholesterin, LDL, HDL, Triglyceride)', 'gkv': 'Check-up 35'},
      'urin':           {'label': 'Urinuntersuchung (Eiweiß, Glukose, Blut, Leukozyten, Nitrit)', 'gkv': 'Check-up 35'},
      'hepatitis':      {'label': 'Hepatitis B + C Screening (einmalig ab 35)', 'gkv': 'Check-up 35 (einmalig)'},
      'stuhltest':      {'label': 'Stuhltest auf Blut / iFOBT (Darmkrebs ab 50)', 'gkv': 'Krebsvorsorge'},
      'koloskopie':     {'label': 'Koloskopie (Darmkrebs ab 55, alle 10 Jahre)', 'gkv': 'Krebsvorsorge'},
      'hautkrebs':      {'label': 'Hautkrebs-Screening (ab 35, alle 2 Jahre)', 'gkv': 'Krebsvorsorge'},
      'psa_vorsorge':   {'label': 'Prostata-Untersuchung (Männer ab 45, jährlich)', 'gkv': 'Krebsvorsorge'},
      'zervix':         {'label': 'Gebärmutterhals-Abstrich / PAP (Frauen ab 20, jährlich)', 'gkv': 'Krebsvorsorge'},
      'mammographie':   {'label': 'Mammographie-Screening (Frauen 50-69, alle 2 Jahre)', 'gkv': 'Krebsvorsorge'},
      'grosses_blutbild': {'label': 'Großes Blutbild', 'gkv': 'Nur bei Indikation'},
      'kleines_blutbild': {'label': 'Kleines Blutbild', 'gkv': 'Nur bei Indikation'},
      'leberwerte':     {'label': 'Leberwerte (GOT, GPT, GGT, AP)', 'gkv': 'Nur bei Indikation'},
      'nierenwerte':    {'label': 'Nierenwerte (Kreatinin, Harnstoff, GFR)', 'gkv': 'Nur bei Indikation'},
      'schilddruese':   {'label': 'Schilddrüse (TSH, fT3, fT4)', 'gkv': 'Nur bei Indikation'},
      'hba1c':          {'label': 'HbA1c (Langzeit-Blutzucker, bei Diabetes)', 'gkv': 'Nur bei Indikation'},
      'entzuendung':    {'label': 'Entzündungswerte (CRP, BSG)', 'gkv': 'Nur bei Indikation'},
      'gerinnung':      {'label': 'Gerinnungswerte (Quick/INR, PTT)', 'gkv': 'Nur bei Indikation'},
      'elektrolyte':    {'label': 'Elektrolyte (Na, K, Ca, Mg)', 'gkv': 'Nur bei Indikation'},
      'eisenwerte':     {'label': 'Eisenwerte (Ferritin, Transferrin)', 'gkv': 'Nur bei Indikation'},
      'harnsaeure':     {'label': 'Harnsäure', 'gkv': 'Nur bei Indikation'},
      'vitamin_d':      {'label': 'Vitamin D (25-OH-D3)', 'gkv': 'GKV bei Verdacht auf Mangel'},
      'vitamin_b12':    {'label': 'Vitamin B12 / Folsäure', 'gkv': 'GKV bei Verdacht auf Mangel'},
      'psa_blut':       {'label': 'PSA Bluttest (Prostata)', 'gkv': 'IGeL (Selbstzahler)'},
      'tumormarker':    {'label': 'Tumormarker (ohne Tumorverdacht)', 'gkv': 'IGeL (Selbstzahler)'},
    };

    Future<void> saveBlutHistory() async {
      final updatedData = Map<String, dynamic>.from(_gesundheitData[type] ?? data);
      final rawBlutData = updatedData['blutanalyse'];
      final blutData = rawBlutData is Map ? Map<String, dynamic>.from(rawBlutData) : <String, dynamic>{};
      blutData['history'] = history.map((e) => Map<String, dynamic>.from(e)).toList();
      blutData['kontrollintervall'] = intervall;
      blutData['reminder_ticket_date'] = reminderTicketDate;
      updatedData['blutanalyse'] = blutData;
      await _saveGesundheitData(type, updatedData);
    }

    // Calculate next due date from last analysis + interval
    DateTime? letzteAnalyse;
    DateTime? naechsteFaellig;
    bool keineAnalyseVorhanden = false;
    if (intervall.isNotEmpty) {
      final monate = int.tryParse(intervall) ?? 0;
      if (monate > 0) {
        if (history.isNotEmpty) {
          // Cea mai recentă analiză (nu prima din array!)
          for (final h in history) {
            final parts = (h['datum'] ?? '').toString().split('.');
            if (parts.length == 3) {
              final d = DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}');
              if (d != null && (letzteAnalyse == null || d.isAfter(letzteAnalyse))) {
                letzteAnalyse = d;
              }
            }
          }
          if (letzteAnalyse != null) {
            naechsteFaellig = _nextWeekday(DateTime(letzteAnalyse.year, letzteAnalyse.month + monate, letzteAnalyse.day));
          }
        } else {
          keineAnalyseVorhanden = true;
          naechsteFaellig = DateTime.now();
        }
      }
    }
    final now = DateTime.now();
    final isOverdue = keineAnalyseVorhanden || (naechsteFaellig != null && naechsteFaellig.isBefore(now));
    final isDueSoon = !keineAnalyseVorhanden && naechsteFaellig != null && !isOverdue && naechsteFaellig.difference(now).inDays <= 14;

    // ── Helper: format date for ticket ──
    String formatFaellig(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    String formatScheduled(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

    // ── Helper: create reminder ticket in background ──
    void autoCreateReminderTicket(DateTime faellig, {bool overdue = false}) {
      final faelligStr = formatFaellig(faellig);
      reminderSent = true;
      reminderTicketDate = faelligStr;
      final letzteStr = history.isNotEmpty ? (history.first['datum'] ?? '–') : '–';
      widget.ticketService.createTicketForMember(
        adminMitgliedernummer: widget.adminMitgliedernummer,
        memberMitgliedernummer: widget.user.mitgliedernummer,
        subject: 'Blutanalyse fällig – bitte Termin vereinbaren',
        message: 'Sehr geehrtes Mitglied,\n\n'
            'Ihre nächste Blutanalyse ${overdue ? 'war' : 'ist'} am $faelligStr fällig.\n'
            'Letzte Analyse: $letzteStr\n'
            'Kontrollintervall: alle $intervall Monate\n\n'
            'Bitte vereinbaren Sie zeitnah einen Termin bei Ihrem $arztTitle.\n\n'
            'Mit freundlichen Grüßen',
        priority: overdue ? 'high' : 'medium',
        scheduledDate: formatScheduled(faellig),
      ).then((_) => saveBlutHistory());
    }

    // ── AUTO-CREATE TICKET: when due date differs from last ticket date ──
    if (naechsteFaellig != null && intervall.isNotEmpty) {
      final currentFaelligStr = formatFaellig(naechsteFaellig);
      if (reminderTicketDate != currentFaelligStr) {
        autoCreateReminderTicket(naechsteFaellig, overdue: isOverdue);
      }
    }

    return StatefulBuilder(
      builder: (ctx, setBlutState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildBehoerdeSectionHeader(Icons.bloodtype, 'Blutanalysen', Colors.red.shade700),
              const SizedBox(height: 12),

              // ── KONTROLLINTERVALL ──
              Row(
                children: [
                  Icon(Icons.repeat, size: 16, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Text('Kontrollintervall:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: ['', '3', '6', '9', '12'].contains(intervall) ? intervall : '',
                          isExpanded: true,
                          isDense: true,
                          style: const TextStyle(fontSize: 13, color: Colors.black87),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('Nicht festgelegt', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: '3', child: Text('Alle 3 Monate', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: '6', child: Text('Alle 6 Monate', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: '9', child: Text('Alle 9 Monate', style: TextStyle(fontSize: 12))),
                            DropdownMenuItem(value: '12', child: Text('Jährlich', style: TextStyle(fontSize: 12))),
                          ],
                          onChanged: (v) {
                            final newIntervall = v ?? '';
                            setBlutState(() {
                              intervall = newIntervall;
                              reminderTicketDate = '';
                              reminderSent = false;
                            });
                            saveBlutHistory();
                            // Create ticket only if erinnerung date has passed or no analyse
                            if (newIntervall.isNotEmpty) {
                              final monate = int.tryParse(newIntervall) ?? 0;
                              if (monate > 0) {
                                final basis = letzteAnalyse ?? DateTime.now();
                                final neueFaellig = _nextWeekday(DateTime(basis.year, basis.month + monate, basis.day));
                                final erinnerung = _nextWeekday(DateTime(neueFaellig.year, neueFaellig.month - 1, neueFaellig.day));
                                final shouldCreate = letzteAnalyse == null || DateTime.now().isAfter(erinnerung);
                                if (shouldCreate) {
                                  setBlutState(() {});
                                  autoCreateReminderTicket(neueFaellig, overdue: neueFaellig.isBefore(DateTime.now()));
                                }
                              }
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              // ── BLUTANALYSE-ERINNERUNG (vizual ca Vorsorge-Erinnerung) ──
              if (intervall.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isOverdue ? Colors.red.shade50 : isDueSoon ? Colors.orange.shade50 : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: isOverdue ? Colors.red.shade300 : isDueSoon ? Colors.orange.shade300 : Colors.blue.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.notifications_active, size: 18, color: isOverdue ? Colors.red.shade700 : Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(child: Text('Blutanalyse-Erinnerung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isOverdue ? Colors.red.shade800 : Colors.blue.shade800))),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (keineAnalyseVorhanden)
                              _vorsorgeInfoRow(Icons.error, 'Letzte Analyse', 'Keine Analyse vorhanden — sofort fällig!', Colors.red)
                            else if (letzteAnalyse != null)
                              _vorsorgeInfoRow(Icons.event, 'Letzte Analyse', '${letzteAnalyse.day.toString().padLeft(2, '0')}.${letzteAnalyse.month.toString().padLeft(2, '0')}.${letzteAnalyse.year}', Colors.teal),
                            const SizedBox(height: 4),
                            if (naechsteFaellig != null && !keineAnalyseVorhanden) ...[
                              _vorsorgeInfoRow(isOverdue ? Icons.error : Icons.schedule, 'Nächste Analyse fällig', '${naechsteFaellig.day.toString().padLeft(2, '0')}.${naechsteFaellig.month.toString().padLeft(2, '0')}.${naechsteFaellig.year}', isOverdue ? Colors.red : Colors.blue),
                              const SizedBox(height: 4),
                              () {
                                final erinnerung = DateTime(naechsteFaellig!.year, naechsteFaellig.month - 1, naechsteFaellig.day);
                                return _vorsorgeInfoRow(Icons.notifications, 'Erinnerung (1 Monat vorher)', '${erinnerung.day.toString().padLeft(2, '0')}.${erinnerung.month.toString().padLeft(2, '0')}.${erinnerung.year}', now.isAfter(erinnerung) ? Colors.orange : Colors.grey);
                              }(),
                            ],
                            if (reminderSent) ...[
                              const SizedBox(height: 4),
                              _vorsorgeInfoRow(Icons.confirmation_num, 'Ticket erstellt am', reminderTicketDate, Colors.green),
                            ],
                            if (isOverdue) ...[
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                                child: Row(children: [
                                  Icon(Icons.warning, size: 16, color: Colors.red.shade700),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(keineAnalyseVorhanden ? 'Noch keine Analyse! Bitte Termin vereinbaren.' : 'Überfällig seit ${now.difference(naechsteFaellig!).inDays} Tagen!', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.red.shade700))),
                                ]),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if ((isOverdue || isDueSoon) && !reminderSent) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: Icon(Icons.confirmation_num, size: 16, color: Colors.orange.shade700),
                            label: Text('Erinnerungs-Ticket jetzt erstellen', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.orange.shade400), backgroundColor: Colors.orange.shade50),
                            onPressed: () async {
                              final letzteStr = letzteAnalyse != null ? '${letzteAnalyse.day.toString().padLeft(2, '0')}.${letzteAnalyse.month.toString().padLeft(2, '0')}.${letzteAnalyse.year}' : 'Keine Analyse';
                              final scheduledStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                              try {
                                final result = await widget.ticketService.createTicketForMember(
                                  adminMitgliedernummer: widget.adminMitgliedernummer,
                                  memberMitgliedernummer: widget.user.mitgliedernummer,
                                  subject: 'Blutanalyse fällig – bitte Termin vereinbaren ($arztTitle)',
                                  message: 'Sehr geehrtes Mitglied,\n\nIhre Blutanalyse bei $arztTitle ist fällig.\n\nKontrollintervall: alle $intervall Monate\nLetzte Analyse: $letzteStr\n\nBitte vereinbaren Sie zeitnah einen Termin.\n\nMit freundlichen Grüßen',
                                  priority: isOverdue ? 'high' : 'medium',
                                  scheduledDate: scheduledStr,
                                  systemAuto: true,
                                );
                                if (result.containsKey('ticket')) {
                                  final today = DateTime.now();
                                  final dateStr = '${today.day.toString().padLeft(2, '0')}.${today.month.toString().padLeft(2, '0')}.${today.year}';
                                  setBlutState(() { reminderSent = true; reminderTicketDate = dateStr; });
                                  saveBlutHistory();
                                  if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Erinnerungs-Ticket erstellt'), backgroundColor: Colors.green));
                                }
                              } catch (e) {
                                if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                              }
                            },
                          ),
                        ),
                      ],
                      if (reminderSent) ...[
                        const SizedBox(height: 6),
                        Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.check_circle, size: 16, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Text('Gesendet', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // ── NEUE ANALYSE HINZUFÜGEN ──
              ElevatedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: ctx,
                    initialDate: DateTime.now(),
                    firstDate: DateTime.now().subtract(const Duration(days: 3650)),
                    lastDate: DateTime.now(),
                    locale: const Locale('de', 'DE'),
                  );
                  if (picked != null) {
                    final datumStr = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                    setBlutState(() {
                      history.insert(0, {
                        'datum': datumStr,
                        'analysen': <String>[],
                        'labor': '',
                        'werte': <String, dynamic>{},
                        'qualitativ_werte': <String, String>{},
                        'dokument_name': '',
                        'dokument_path': '',
                      });
                    });
                    await saveBlutHistory();
                    if (ctx.mounted) {
                      _showBlutanalyseDetailDialog(
                        type: type,
                        data: _gesundheitData[type] ?? data,
                        history: history,
                        entryIndex: 0,
                        analyseTypen: analyseTypen,
                        setBlutState: setBlutState,
                      );
                    }
                  }
                },
                icon: const Icon(Icons.add_circle, size: 18),
                label: const Text('Neue Analyse hinzufügen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red.shade600,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
              const SizedBox(height: 16),

              // ── HISTORY ──
              if (history.isEmpty)
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Center(
                    child: Text(
                      'Noch keine Blutanalysen vorhanden.\nKlicken Sie oben um eine neue Analyse hinzuzufügen.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                    ),
                  ),
                ),
              if (history.isNotEmpty) ...[
                ...history.asMap().entries.map((entry) {
                  final h = entry.value;
                  final hasWerte = h['werte'] is Map && (h['werte'] as Map).isNotEmpty;
                  final hasDokument = (h['dokument_name'] ?? '').toString().isNotEmpty;
                  int abnormalCount = 0;
                  if (hasWerte) {
                    final werte = h['werte'] is Map ? Map<String, dynamic>.from(h['werte'] as Map) : <String, dynamic>{};
                    for (final param in _blutParameter) {
                      final val = double.tryParse(werte[param['key']]?.toString() ?? '');
                      if (val != null && param['qualitativ'] != true) {
                        final minV = (param['min'] as num).toDouble();
                        final maxV = (param['max'] as num).toDouble();
                        if (val < minV || val > maxV) {
                          abnormalCount++;
                        }
                      }
                    }
                  }
                  return InkWell(
                    onTap: () => _showBlutanalyseDetailDialog(
                      type: type,
                      data: _gesundheitData[type] ?? data,
                      history: history,
                      entryIndex: entry.key,
                      analyseTypen: analyseTypen,
                      setBlutState: setBlutState,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: hasWerte
                            ? (abnormalCount > 0 ? Colors.orange.shade50 : Colors.green.shade50)
                            : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: hasWerte
                            ? (abnormalCount > 0 ? Colors.orange.shade300 : Colors.green.shade300)
                            : Colors.grey.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasWerte ? (abnormalCount > 0 ? Icons.warning_amber : Icons.check_circle) : Icons.pending_actions,
                            size: 16,
                            color: hasWerte ? (abnormalCount > 0 ? Colors.orange.shade700 : Colors.green.shade600) : Colors.grey.shade500,
                          ),
                          const SizedBox(width: 8),
                          Text(h['datum'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          const SizedBox(width: 8),
                          if (hasDokument) ...[
                            Icon(Icons.attach_file, size: 13, color: Colors.blue.shade400),
                            const SizedBox(width: 4),
                          ],
                          if (hasWerte) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: abnormalCount > 0 ? Colors.orange.shade100 : Colors.green.shade100,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                abnormalCount > 0 ? '$abnormalCount auffällig' : 'Alle normal',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: abnormalCount > 0 ? Colors.orange.shade800 : Colors.green.shade800),
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          Expanded(
                            child: Text(
                              (h['analysen'] as List<dynamic>?)?.map((k) => analyseTypen[k.toString()]?['label'] ?? k).join(', ') ?? '',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                          const SizedBox(width: 4),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                            onPressed: () async {
                              setBlutState(() => history.removeAt(entry.key));
                              await saveBlutHistory();
                            },
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        );
      },
    );
  }

  // ========== BLUTANALYSE DETAIL DIALOG (Werte + Dokument + Bericht) ==========

  void _showBlutanalyseDetailDialog({
    required String type,
    required Map<String, dynamic> data,
    required List<Map<String, dynamic>> history,
    required int entryIndex,
    required Map<String, Map<String, String>> analyseTypen,
    required StateSetter setBlutState,
  }) {
    final h = Map<String, dynamic>.from(history[entryIndex]);
    final rawWerte = h['werte'];
    final werte = rawWerte is Map ? Map<String, dynamic>.from(rawWerte) : <String, dynamic>{};
    final controllers = <String, TextEditingController>{};
    final rawQualitativ = h['qualitativ_werte'];
    final qualitativWerte = rawQualitativ is Map ? Map<String, String>.from(rawQualitativ.map((k, v) => MapEntry(k.toString(), v.toString()))) : <String, String>{};
    String dokumentName = h['dokument_name']?.toString() ?? '';
    String dokumentPath = h['dokument_path']?.toString() ?? '';
    int currentTab = 0; // 0=Werte, 1=Dokument, 2=Bericht, 3=Termin
    bool isSaving = false;
    String saveStatus = ''; // '', 'saving', 'saved', 'error'
    // Termin data
    final terminDatumController = TextEditingController(text: h['termin_datum']?.toString() ?? '');
    final terminUhrzeitController = TextEditingController(text: h['termin_uhrzeit']?.toString() ?? '');
    final terminNotizController = TextEditingController(text: h['termin_notiz']?.toString() ?? '');
    bool terminTicketErstellt = h['termin_ticket_erstellt'] == true;
    List<Map<String, dynamic>> uploadedDocs = [];
    bool docsLoading = true;

    // Create controllers for all parameters
    for (final p in _blutParameter) {
      controllers[p['key'] as String] = TextEditingController(text: werte[p['key']]?.toString() ?? '');
    }

    // Save function — collects all values and persists to server
    Future<void> doSave(StateSetter setD) async {
      if (isSaving) return;
      isSaving = true;
      setD(() => saveStatus = 'saving');

      // Collect numeric values
      final newWerte = <String, dynamic>{};
      for (final p in _blutParameter) {
        final key = p['key'] as String;
        final text = controllers[key]?.text.trim() ?? '';
        if (text.isNotEmpty && p['qualitativ'] != true) {
          newWerte[key] = text;
        }
      }

      // Update history entry
      history[entryIndex] = {
        'datum': h['datum'],
        'analysen': h['analysen'],
        'labor': h['labor'],
        'werte': newWerte,
        'qualitativ_werte': Map<String, String>.from(qualitativWerte),
        'dokument_name': dokumentName,
        'dokument_path': dokumentPath,
        'termin_datum': terminDatumController.text.trim(),
        'termin_uhrzeit': terminUhrzeitController.text.trim(),
        'termin_notiz': terminNotizController.text.trim(),
        'termin_ticket_erstellt': terminTicketErstellt,
      };

      // Build complete data structure
      final saveData = Map<String, dynamic>.from(_gesundheitData[type] ?? data);
      final rawBlutSave = saveData['blutanalyse'];
      final blut = rawBlutSave is Map ? Map<String, dynamic>.from(rawBlutSave) : <String, dynamic>{};
      blut['history'] = history.map((e) => Map<String, dynamic>.from(e)).toList();
      saveData['blutanalyse'] = blut;

      try {
        final result = await widget.apiService.saveGesundheitData(widget.user.id, type, saveData);
        if (result['success'] == true) {
          _gesundheitData[type] = saveData;
          if (mounted) setState(() {});
          setD(() => saveStatus = 'saved');
        } else {
          setD(() => saveStatus = 'error');
        }
      } catch (_) {
        setD(() => saveStatus = 'error');
      }
      isSaving = false;
    }

    // Generate analyse_id from datum for document grouping
    final analyseId = (h['datum'] ?? '').toString().replaceAll('.', '_');

    // Load existing documents async
    void loadDocs(StateSetter setD) async {
      try {
        final result = await widget.apiService.listGesundheitDokumente(
          widget.user.id, type, analyseId,
        );
        if (result['success'] == true) {
          setD(() {
            uploadedDocs = List<Map<String, dynamic>>.from(result['documents'] ?? []);
            docsLoading = false;
          });
        } else {
          setD(() => docsLoading = false);
        }
      } catch (_) {
        setD(() => docsLoading = false);
      }
    }

    showDialog(
      context: context,
      builder: (dialogCtx) {
        bool docsInitialized = false;
        return StatefulBuilder(
          builder: (ctx, setD) {
            // Load docs on first build
            if (!docsInitialized) {
              docsInitialized = true;
              loadDocs(setD);
            }
            // Build report data
            final filledParams = <Map<String, dynamic>>[];
            final abnormalParams = <Map<String, dynamic>>[];
            for (final p in _blutParameter) {
              final key = p['key'] as String;
              if (p['qualitativ'] == true) {
                final qVal = qualitativWerte[key] ?? '';
                if (qVal.isNotEmpty) {
                  final isNeg = qVal == 'negativ' || qVal == 'nicht reaktiv';
                  filledParams.add({...p, 'value': qVal, 'status': isNeg ? 'normal' : 'auffällig'});
                  if (!isNeg) abnormalParams.add({...p, 'value': qVal, 'status': 'auffällig'});
                }
              } else {
                final val = double.tryParse(controllers[key]?.text ?? '');
                if (val != null) {
                  final minV = (p['min'] as num).toDouble();
                  final maxV = (p['max'] as num).toDouble();
                  String status = 'normal';
                  if (val < minV) {
                    status = 'niedrig';
                  } else if (val > maxV) {
                    status = 'hoch';
                  }
                  filledParams.add({...p, 'value': val, 'status': status});
                  if (status != 'normal') abnormalParams.add({...p, 'value': val, 'status': status});
                }
              }
            }

            return Dialog(
              insetPadding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700, maxHeight: 750),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.red.shade700,
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.bloodtype, color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Blutanalyse vom ${h['datum'] ?? ''}',
                                  style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (dokumentName.isNotEmpty)
                                Tooltip(
                                  message: dokumentName,
                                  child: Icon(Icons.attach_file, color: Colors.white.withValues(alpha: 0.8), size: 16),
                                ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                onPressed: () => Navigator.pop(ctx),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''}  ·  '
                            '${_isMaennlich ? 'Männlich' : 'Weiblich'}  ·  '
                            '${_berechneAlter()} Jahre  ·  '
                            'Referenzwerte: ${_isMaennlich ? '♂' : '♀'} (DGKL)',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                          ),
                        ],
                      ),
                    ),

                    // Tab bar
                    Container(
                      color: Colors.grey.shade100,
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => setD(() => currentTab = 0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: currentTab == 0 ? Colors.red.shade700 : Colors.transparent, width: 2)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.edit_note, size: 16, color: currentTab == 0 ? Colors.red.shade700 : Colors.grey),
                                    const SizedBox(width: 6),
                                    Text('Werte eingeben', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: currentTab == 0 ? Colors.red.shade700 : Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setD(() => currentTab = 1),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: currentTab == 1 ? Colors.red.shade700 : Colors.transparent, width: 2)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.upload_file, size: 16, color: currentTab == 1 ? Colors.red.shade700 : Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Dokument${uploadedDocs.isNotEmpty ? ' (${uploadedDocs.length})' : ''}',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: currentTab == 1 ? Colors.red.shade700 : Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setD(() => currentTab = 2),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: currentTab == 2 ? Colors.red.shade700 : Colors.transparent, width: 2)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.assessment, size: 16, color: currentTab == 2 ? Colors.red.shade700 : Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Bericht${filledParams.isNotEmpty ? ' (${filledParams.length})' : ''}',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: currentTab == 2 ? Colors.red.shade700 : Colors.grey.shade600),
                                    ),
                                    if (abnormalParams.isNotEmpty) ...[
                                      const SizedBox(width: 4),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                        decoration: BoxDecoration(color: Colors.orange.shade600, borderRadius: BorderRadius.circular(8)),
                                        child: Text('${abnormalParams.length}', style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              onTap: () => setD(() => currentTab = 3),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                decoration: BoxDecoration(
                                  border: Border(bottom: BorderSide(color: currentTab == 3 ? Colors.red.shade700 : Colors.transparent, width: 2)),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.calendar_month, size: 16, color: currentTab == 3 ? Colors.red.shade700 : Colors.grey),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Termin${terminDatumController.text.isNotEmpty ? ' ✓' : ''}',
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: currentTab == 3 ? Colors.red.shade700 : Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Expanded(
                      child: currentTab == 0
                          ? _buildWerteEingabeTab(controllers, qualitativWerte, dokumentName, dokumentPath, setD, (name, path) {
                              setD(() { dokumentName = name; dokumentPath = path; });
                              doSave(setD);
                            }, () => doSave(setD))
                          : currentTab == 1
                              ? _buildDokumentTab(type, analyseId, uploadedDocs, docsLoading, setD, () => loadDocs(setD), (name) {
                              dokumentName = name;
                              doSave(setD);
                            })
                              : currentTab == 2
                                  ? _buildBerichtTab(filledParams, abnormalParams)
                                  : _buildTerminTab(terminDatumController, terminUhrzeitController, terminNotizController, terminTicketErstellt, setD, () => doSave(setD), (val) => terminTicketErstellt = val, type, h),
                    ),

                    // Footer
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade200))),
                      child: Row(
                        children: [
                          // Auto-save status indicator
                          if (saveStatus == 'saving')
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.orange.shade600)),
                              const SizedBox(width: 6),
                              Text('Speichern...', style: TextStyle(fontSize: 11, color: Colors.orange.shade600)),
                            ])
                          else if (saveStatus == 'saved')
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.cloud_done, size: 16, color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Text('Gespeichert', style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                            ])
                          else if (saveStatus == 'error')
                            Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.error_outline, size: 16, color: Colors.red.shade600),
                              const SizedBox(width: 4),
                              Text('Fehler!', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                            ]),
                          const Spacer(),
                          TextButton(
                            onPressed: () async {
                              await doSave(setD);
                              if (ctx.mounted) {
                                setBlutState(() {});
                                Navigator.pop(ctx);
                              }
                            },
                            child: const Text('Schließen'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton.icon(
                            onPressed: isSaving ? null : () => doSave(setD),
                            icon: isSaving
                                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save, size: 16),
                            label: const Text('Speichern'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade600, foregroundColor: Colors.white),
                          ),
                          const SizedBox(width: 8),
                          // PDF Export button
                          if (filledParams.isNotEmpty)
                            ElevatedButton.icon(
                              onPressed: () => _exportBlutanalysePdf(h['datum'] ?? '', filledParams, abnormalParams),
                              icon: const Icon(Icons.picture_as_pdf, size: 16),
                              label: const Text('PDF'),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Tab 1: Werte eingeben ──
  Widget _buildWerteEingabeTab(
    Map<String, TextEditingController> controllers,
    Map<String, String> qualitativWerte,
    String dokumentName,
    String dokumentPath,
    StateSetter setD,
    Function(String, String) onDokumentChanged,
    VoidCallback onAutoSave,
  ) {
    String? lastGruppe;
    final rows = <Widget>[];

    // Dokument upload section
    rows.add(Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.upload_file, size: 20, color: Colors.blue.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: dokumentName.isNotEmpty
                ? Text(dokumentName, style: TextStyle(fontSize: 12, color: Colors.blue.shade800, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis)
                : Text('Analysedokument hochladen (PDF, Bild)', style: TextStyle(fontSize: 12, color: Colors.blue.shade600)),
          ),
          const SizedBox(width: 8),
          if (dokumentName.isNotEmpty)
            IconButton(
              icon: Icon(Icons.close, size: 16, color: Colors.red.shade400),
              onPressed: () => onDokumentChanged('', ''),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              tooltip: 'Dokument entfernen',
            ),
          const SizedBox(width: 4),
          ElevatedButton.icon(
            onPressed: () async {
              try {
                final result = await showDialog<Map<String, String>>(
                  context: context,
                  builder: (pickCtx) {
                    final nameC = TextEditingController();
                    return AlertDialog(
                      title: const Text('Dokument hinzufügen', style: TextStyle(fontSize: 15)),
                      content: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextField(
                            controller: nameC,
                            decoration: InputDecoration(
                              labelText: 'Dokumentname',
                              hintText: 'z.B. Blutbild_2026-03-22.pdf',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text('Das Dokument wird als Referenz gespeichert.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(pickCtx), child: const Text('Abbrechen')),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(pickCtx, {'name': nameC.text.trim(), 'path': 'manual_entry'}),
                          child: const Text('Hinzufügen'),
                        ),
                      ],
                    );
                  },
                );
                if (result != null && result['name']!.isNotEmpty) {
                  onDokumentChanged(result['name']!, result['path']!);
                }
              } catch (_) {}
            },
            icon: const Icon(Icons.add, size: 14),
            label: Text(dokumentName.isNotEmpty ? 'Ändern' : 'Hochladen', style: const TextStyle(fontSize: 11)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              minimumSize: Size.zero,
            ),
          ),
        ],
      ),
    ));

    // Parameter groups
    for (final p in _blutParameter) {
      final gruppe = p['gruppe'] as String;
      final key = p['key'] as String;
      if (gruppe != lastGruppe) {
        if (lastGruppe != null) rows.add(const SizedBox(height: 8));
        rows.add(Container(
          margin: const EdgeInsets.only(bottom: 6, top: 4),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(gruppe, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.red.shade800)),
        ));
        lastGruppe = gruppe;
      }

      if (p['qualitativ'] == true) {
        // Qualitative parameter (positiv/negativ etc.)
        final currentVal = qualitativWerte[key] ?? '';
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(p['label'] as String, style: const TextStyle(fontSize: 12)),
              ),
              Expanded(
                flex: 2,
                child: Row(
                  children: [
                    for (final opt in ['negativ', 'positiv', 'grenzwertig']) ...[
                      Expanded(
                        child: InkWell(
                          onTap: () {
                            setD(() {
                              qualitativWerte[key] = qualitativWerte[key] == opt ? '' : opt;
                            });
                            onAutoSave();
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            margin: const EdgeInsets.only(right: 2),
                            decoration: BoxDecoration(
                              color: currentVal == opt
                                  ? (opt == 'negativ' ? Colors.green.shade100 : opt == 'positiv' ? Colors.red.shade100 : Colors.orange.shade100)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: currentVal == opt
                                  ? (opt == 'negativ' ? Colors.green.shade400 : opt == 'positiv' ? Colors.red.shade400 : Colors.orange.shade400)
                                  : Colors.grey.shade300),
                            ),
                            child: Text(
                              opt == 'negativ' ? 'neg' : opt == 'positiv' ? 'pos' : 'grenz',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 9, fontWeight: currentVal == opt ? FontWeight.bold : FontWeight.normal),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ));
      } else {
        // Numeric parameter
        final minV = (p['min'] as num).toDouble();
        final maxV = (p['max'] as num).toDouble();
        final val = double.tryParse(controllers[key]?.text ?? '');
        Color? borderColor;
        Color? bgColor;
        if (val != null) {
          if (val < minV || val > maxV) {
            borderColor = Colors.orange.shade400;
            bgColor = Colors.orange.shade50;
          } else {
            borderColor = Colors.green.shade400;
            bgColor = Colors.green.shade50;
          }
        }
        rows.add(Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(p['label'] as String, style: const TextStyle(fontSize: 12)),
              ),
              SizedBox(
                width: 80,
                child: TextField(
                  controller: controllers[key],
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: borderColor ?? Colors.grey.shade300)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide(color: borderColor ?? Colors.grey.shade300)),
                    filled: bgColor != null,
                    fillColor: bgColor,
                  ),
                  style: TextStyle(fontSize: 12, fontWeight: val != null && (val < minV || val > maxV) ? FontWeight.bold : null),
                  onChanged: (_) {
                    setD(() {});
                    onAutoSave();
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 55,
                child: Text(p['unit'] as String, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ),
              SizedBox(
                width: 70,
                child: Text(
                  '${minV > 0 ? minV.toString() : '0'} – ${maxV < 999 ? maxV.toString() : '∞'}',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
        ));
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: rows,
      ),
    );
  }

  // ── Tab 1: Dokument (Upload/Download encrypted) ──
  Widget _buildDokumentTab(
    String type,
    String analyseId,
    List<Map<String, dynamic>> docs,
    bool loading,
    StateSetter setD,
    VoidCallback reloadDocs,
    void Function(String fileName) onDocUploaded,
  ) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Upload button
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.cloud_upload_outlined, size: 36, color: Colors.blue.shade400),
                const SizedBox(height: 8),
                Text('Analyseergebnis hochladen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                const SizedBox(height: 4),
                Text('PDF oder Bild vom Arzt/Labor (AES-256 verschlüsselt)', style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      final filePath = await _pickGesundheitFile();
                      if (filePath != null && filePath.isNotEmpty) {
                        setD(() {});
                        final fileName = filePath.split('/').last;
                        final uploadResult = await widget.apiService.uploadGesundheitDokument(
                          userId: widget.user.id,
                          gesundheitType: type,
                          analyseId: analyseId,
                          filePath: filePath,
                          fileName: fileName,
                        );
                        if (uploadResult['success'] == true) {
                          reloadDocs();
                          onDocUploaded(fileName);
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Dokument "$fileName" hochgeladen (verschlüsselt)'), backgroundColor: Colors.green),
                            );
                          }
                        } else {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(uploadResult['message'] ?? 'Upload fehlgeschlagen'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Datei hochladen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade600,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Document list
          if (docs.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Icon(Icons.folder_open, size: 40, color: Colors.grey.shade300),
                    const SizedBox(height: 8),
                    Text('Keine Dokumente vorhanden', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  ],
                ),
              ),
            )
          else ...[
            Text('Hochgeladene Dokumente (${docs.length})', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 8),
            ...docs.map((doc) {
              final isPdf = doc['mime_type']?.toString().contains('pdf') == true;
              final sizeKb = ((int.tryParse(doc['file_size']?.toString() ?? '0') ?? 0) / 1024).toStringAsFixed(0);
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPdf ? Icons.picture_as_pdf : Icons.image,
                      size: 24,
                      color: isPdf ? Colors.red.shade400 : Colors.blue.shade400,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(doc['filename']?.toString() ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                          Text('$sizeKb KB  ·  ${doc['created_at'] ?? ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock, size: 12, color: Colors.green.shade600),
                        const SizedBox(width: 2),
                        Text('AES-256', style: TextStyle(fontSize: 9, color: Colors.green.shade600)),
                      ],
                    ),
                    const SizedBox(width: 8),
                    // Preview
                    IconButton(
                      icon: Icon(Icons.visibility, size: 18, color: Colors.teal.shade600),
                      tooltip: 'Vorschau',
                      onPressed: () async {
                        try {
                          final response = await widget.apiService.downloadGesundheitDokument(int.parse(doc['id'].toString()));
                          if (response.statusCode == 200 && mounted) {
                            final mime = doc['mime_type']?.toString() ?? '';
                            final filename = doc['filename']?.toString() ?? '';
                            if (mime.contains('pdf')) {
                              // Save temp and open with pdfrx
                              final dir = await getTemporaryDirectory();
                              final tmpFile = File('${dir.path}/$filename');
                              await tmpFile.writeAsBytes(response.bodyBytes);
                              if (mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    insetPadding: const EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: 800,
                                      height: 600,
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                                            child: Row(
                                              children: [
                                                Icon(Icons.picture_as_pdf, color: Colors.red.shade400),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(filename, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                                              ],
                                            ),
                                          ),
                                          Expanded(child: pdfrx.PdfViewer.file(tmpFile.path)),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                            } else {
                              // Image preview
                              if (mounted) {
                                showDialog(
                                  context: context,
                                  builder: (_) => Dialog(
                                    insetPadding: const EdgeInsets.all(20),
                                    child: SizedBox(
                                      width: 800,
                                      height: 600,
                                      child: Column(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
                                            child: Row(
                                              children: [
                                                Icon(Icons.image, color: Colors.blue.shade400),
                                                const SizedBox(width: 8),
                                                Expanded(child: Text(filename, style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                                              ],
                                            ),
                                          ),
                                          Expanded(
                                            child: InteractiveViewer(
                                              maxScale: 5.0,
                                              child: Image.memory(response.bodyBytes, fit: BoxFit.contain),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Vorschau-Fehler: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    // Download
                    IconButton(
                      icon: Icon(Icons.download, size: 18, color: Colors.blue.shade600),
                      tooltip: 'Herunterladen',
                      onPressed: () async {
                        try {
                          final response = await widget.apiService.downloadGesundheitDokument(int.parse(doc['id'].toString()));
                          if (response.statusCode == 200) {
                            final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
                            final file = File('${dir.path}/${doc['filename']}');
                            await file.writeAsBytes(response.bodyBytes);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Gespeichert: ${file.path}'), backgroundColor: Colors.green),
                              );
                            }
                          } else {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Download fehlgeschlagen'), backgroundColor: Colors.red),
                              );
                            }
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                            );
                          }
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                    // Delete
                    IconButton(
                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                      tooltip: 'Löschen',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (cCtx) => AlertDialog(
                            title: const Text('Dokument löschen?', style: TextStyle(fontSize: 15)),
                            content: Text('${doc['filename']} wird unwiderruflich gelöscht.', style: const TextStyle(fontSize: 13)),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(cCtx, false), child: const Text('Abbrechen')),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(cCtx, true),
                                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('Löschen', style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true) {
                          await widget.apiService.deleteGesundheitDokument(int.parse(doc['id'].toString()));
                          reloadDocs();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Dokument gelöscht'), backgroundColor: Colors.green),
                            );
                          }
                        }
                      },
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // File picker helper using file_picker package
  Future<String?> _pickGesundheitFile() async {
    try {
      final result = await FilePickerHelper.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'tiff', 'bmp'],
        allowMultiple: false,
      );
      if (result != null && result.files.isNotEmpty) {
        return result.files.first.path;
      }
    } catch (_) {}
    return null;
  }

  // ── Tab 3: Termin (Besprechungstermin) ──
  Widget _buildTerminTab(
    TextEditingController datumCtrl,
    TextEditingController uhrzeitCtrl,
    TextEditingController notizCtrl,
    bool ticketErstellt,
    StateSetter setD,
    VoidCallback onSave,
    void Function(bool) setTicketErstellt,
    String type,
    Map<String, dynamic> h,
  ) {
    Future<void> autoCreateTermin() async {
      if (datumCtrl.text.isEmpty || uhrzeitCtrl.text.isEmpty || ticketErstellt) return;

      final datumText = datumCtrl.text.trim();
      final uhrzeitText = uhrzeitCtrl.text.trim();
      final notizText = notizCtrl.text.trim();

      // Parse date + time into DateTime
      final datumParts = datumText.split('.');
      final zeitParts = uhrzeitText.split(':');
      if (datumParts.length != 3 || zeitParts.length != 2) return;

      final terminDate = DateTime(
        int.parse(datumParts[2]),
        int.parse(datumParts[1]),
        int.parse(datumParts[0]),
        int.parse(zeitParts[0]),
        int.parse(zeitParts[1]),
      );

      try {
        widget.terminService.setToken(widget.apiService.token ?? '');
        final result = await widget.terminService.createTermin(
          title: 'Besprechung Blutanalyse vom ${h['datum'] ?? ''}',
          category: 'sonstiges',
          description: 'Besprechung der Blutanalyse-Ergebnisse vom ${h['datum'] ?? ''} '
              'für ${widget.user.name}.'
              '${notizText.isNotEmpty ? '\n\nAnmerkung: $notizText' : ''}',
          terminDate: terminDate,
          durationMinutes: 30,
          location: 'Büro',
          participantIds: [widget.user.id],
        );

        if (mounted) {
          if (result['success'] == true) {
            setD(() => setTicketErstellt(true));
            onSave();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Termin am $datumText um $uhrzeitText Uhr in Terminverwaltung erstellt'), backgroundColor: Colors.green),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(result['message'] ?? 'Termin-Fehler'), backgroundColor: Colors.red),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.calendar_month, size: 24, color: Colors.purple.shade600),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Besprechungstermin', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.purple.shade800)),
                      const SizedBox(height: 2),
                      Text('Termin zur Besprechung der Analyseergebnisse', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Wählen Sie Datum und Uhrzeit — ein Termin wird automatisch erstellt.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),

          // Datum
          Text('Datum', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: datumCtrl,
            readOnly: true,
            decoration: InputDecoration(
              hintText: 'Datum wählen...',
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: datumCtrl.text.isNotEmpty ? IconButton(
                icon: Icon(Icons.clear, size: 16, color: Colors.grey.shade400),
                onPressed: () {
                  setD(() => datumCtrl.clear());
                  onSave();
                },
              ) : null,
            ),
            style: const TextStyle(fontSize: 14),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: context,
                initialDate: now.add(const Duration(days: 1)),
                firstDate: now,
                lastDate: now.add(const Duration(days: 365)),
                locale: const Locale('de', 'DE'),
              );
              if (picked != null) {
                setD(() {
                  datumCtrl.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                });
                onSave();
                await autoCreateTermin();
              }
            },
          ),
          const SizedBox(height: 16),

          // Uhrzeit
          Text('Uhrzeit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: uhrzeitCtrl,
            readOnly: true,
            decoration: InputDecoration(
              hintText: 'Uhrzeit wählen...',
              prefixIcon: const Icon(Icons.access_time, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: uhrzeitCtrl.text.isNotEmpty ? IconButton(
                icon: Icon(Icons.clear, size: 16, color: Colors.grey.shade400),
                onPressed: () {
                  setD(() => uhrzeitCtrl.clear());
                  onSave();
                },
              ) : null,
            ),
            style: const TextStyle(fontSize: 14),
            onTap: () async {
              final picked = await showTimePicker(
                context: context,
                initialTime: const TimeOfDay(hour: 10, minute: 0),
                builder: (ctx, child) {
                  return MediaQuery(
                    data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                    child: child!,
                  );
                },
              );
              if (picked != null) {
                setD(() {
                  uhrzeitCtrl.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                });
                onSave();
                await autoCreateTermin();
              }
            },
          ),
          const SizedBox(height: 16),

          // Notiz
          Text('Notiz / Grund', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: notizCtrl,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'z.B. Besprechung auffälliger Werte, Therapieplan...',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
            onChanged: (_) => onSave(),
          ),
          const SizedBox(height: 24),

          // Status
          if (ticketErstellt)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Termin erstellt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.green.shade800)),
                        const SizedBox(height: 2),
                        Text(
                          'Termin am ${datumCtrl.text} um ${uhrzeitCtrl.text} Uhr wurde in der Terminverwaltung erstellt.',
                          style: TextStyle(fontSize: 11, color: Colors.green.shade600),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          if (!ticketErstellt && datumCtrl.text.isNotEmpty && uhrzeitCtrl.text.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text('Bitte Uhrzeit wählen — Termin wird automatisch erstellt.', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                ],
              ),
            ),

          if (!ticketErstellt && uhrzeitCtrl.text.isNotEmpty && datumCtrl.text.isEmpty)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text('Bitte Datum wählen — Termin wird automatisch erstellt.', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                ],
              ),
            ),

          // Summary
          if (datumCtrl.text.isNotEmpty || uhrzeitCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Terminübersicht', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (datumCtrl.text.isNotEmpty) ...[
                        Icon(Icons.calendar_today, size: 14, color: Colors.purple.shade600),
                        const SizedBox(width: 6),
                        Text(datumCtrl.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                      if (uhrzeitCtrl.text.isNotEmpty) ...[
                        const SizedBox(width: 12),
                        Icon(Icons.access_time, size: 14, color: Colors.purple.shade600),
                        const SizedBox(width: 6),
                        Text('${uhrzeitCtrl.text} Uhr', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ],
                  ),
                  if (notizCtrl.text.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.notes, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 6),
                        Expanded(child: Text(notizCtrl.text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Tab 2: Bericht (Report) ──
  Widget _buildBerichtTab(List<Map<String, dynamic>> filledParams, List<Map<String, dynamic>> abnormalParams) {
    if (filledParams.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Keine Werte eingegeben', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Geben Sie Blutwerte im Tab "Werte eingeben" ein.', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Summary card
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: abnormalParams.isEmpty ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: abnormalParams.isEmpty ? Colors.green.shade300 : Colors.orange.shade300),
            ),
            child: Row(
              children: [
                Icon(
                  abnormalParams.isEmpty ? Icons.check_circle : Icons.warning_amber_rounded,
                  size: 28,
                  color: abnormalParams.isEmpty ? Colors.green.shade700 : Colors.orange.shade700,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        abnormalParams.isEmpty ? 'Alle Werte im Normalbereich' : '${abnormalParams.length} auffällige${abnormalParams.length == 1 ? 'r' : ''} Wert${abnormalParams.length == 1 ? '' : 'e'}',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: abnormalParams.isEmpty ? Colors.green.shade800 : Colors.orange.shade800),
                      ),
                      Text(
                        '${filledParams.length} Werte insgesamt erfasst',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Abnormal values first (attention section)
          if (abnormalParams.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(6)),
              child: Row(
                children: [
                  Icon(Icons.priority_high, size: 14, color: Colors.orange.shade800),
                  const SizedBox(width: 4),
                  Text('Auffällige Werte – Achtung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.orange.shade800)),
                ],
              ),
            ),
            ...abnormalParams.map((p) => _buildBerichtRow(p, highlight: true)),
            const SizedBox(height: 12),
          ],

          // All values grouped
          ...() {
            String? lastGruppe;
            final widgets = <Widget>[];
            for (final p in filledParams) {
              final gruppe = p['gruppe'] as String;
              if (gruppe != lastGruppe) {
                if (lastGruppe != null) widgets.add(const SizedBox(height: 6));
                widgets.add(Container(
                  margin: const EdgeInsets.only(bottom: 4, top: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                  child: Text(gruppe, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade700)),
                ));
                lastGruppe = gruppe;
              }
              widgets.add(_buildBerichtRow(p, highlight: false));
            }
            return widgets;
          }(),
        ],
      ),
    );
  }

  Widget _buildBerichtRow(Map<String, dynamic> p, {required bool highlight}) {
    final status = p['status'] as String;
    final isQualitativ = p['qualitativ'] == true;
    Color statusColor;
    IconData statusIcon;
    String statusText;

    if (status == 'normal' || status == 'negativ') {
      statusColor = Colors.green.shade600;
      statusIcon = Icons.check_circle;
      statusText = isQualitativ ? (p['value'] as String) : 'Normal';
    } else if (status == 'niedrig') {
      statusColor = Colors.blue.shade700;
      statusIcon = Icons.arrow_downward;
      statusText = 'Niedrig';
    } else if (status == 'hoch') {
      statusColor = Colors.red.shade600;
      statusIcon = Icons.arrow_upward;
      statusText = 'Hoch';
    } else {
      statusColor = Colors.orange.shade700;
      statusIcon = Icons.warning_amber;
      statusText = isQualitativ ? (p['value'] as String) : 'Auffällig';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: highlight ? statusColor.withValues(alpha: 0.08) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: highlight ? Border.all(color: statusColor.withValues(alpha: 0.3)) : null,
      ),
      child: Row(
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: Text(p['label'] as String, style: TextStyle(fontSize: 12, fontWeight: highlight ? FontWeight.w600 : FontWeight.normal)),
          ),
          if (!isQualitativ) ...[
            SizedBox(
              width: 60,
              child: Text(
                '${p['value']}',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 50,
              child: Text(p['unit'] as String, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 65,
              child: Text(
                '(${(p['min'] as num) > 0 ? p['min'] : '0'} – ${(p['max'] as num) < 999 ? p['max'] : '∞'})',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade400),
                textAlign: TextAlign.right,
              ),
            ),
          ] else
            SizedBox(
              width: 80,
              child: Text(statusText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColor), textAlign: TextAlign.right),
            ),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
            child: Text(statusText, style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: statusColor)),
          ),
        ],
      ),
    );
  }

  // ── PDF Export für Blutanalyse Bericht ──
  Future<void> _exportBlutanalysePdf(String datum, List<Map<String, dynamic>> filledParams, List<Map<String, dynamic>> abnormalParams) async {
    try {
      final pdf = pw.Document();
      final userName = '${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''}'.trim();

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          header: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('Blutanalyse Bericht', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('Patient: $userName  |  Datum: $datum  |  ${widget.user.mitgliedernummer}',
                  style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700)),
              pw.Divider(),
              pw.SizedBox(height: 8),
            ],
          ),
          build: (ctx) {
            final widgets = <pw.Widget>[];

            // Summary
            widgets.add(pw.Container(
              padding: const pw.EdgeInsets.all(10),
              decoration: pw.BoxDecoration(
                color: abnormalParams.isEmpty ? PdfColors.green50 : PdfColors.orange50,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Text(
                abnormalParams.isEmpty
                    ? 'Alle ${filledParams.length} Werte im Normalbereich'
                    : '${abnormalParams.length} von ${filledParams.length} Werten auffaellig',
                style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
              ),
            ));
            widgets.add(pw.SizedBox(height: 12));

            // Table
            String? lastGruppe;
            for (final p in filledParams) {
              final gruppe = p['gruppe'] as String;
              if (gruppe != lastGruppe) {
                if (lastGruppe != null) widgets.add(pw.SizedBox(height: 6));
                widgets.add(pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  color: PdfColors.grey200,
                  child: pw.Text(gruppe, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                ));
                lastGruppe = gruppe;
              }

              final status = p['status'] as String;
              final isQ = p['qualitativ'] == true;
              PdfColor rowColor = PdfColors.white;
              if (status == 'hoch') {
                rowColor = PdfColors.red50;
              } else if (status == 'niedrig') {
                rowColor = PdfColors.blue50;
              } else if (status == 'auffällig') {
                rowColor = PdfColors.orange50;
              }

              final arrow = status == 'hoch' ? ' ↑' : status == 'niedrig' ? ' ↓' : '';

              widgets.add(pw.Container(
                padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: rowColor,
                child: pw.Row(
                  children: [
                    pw.Expanded(flex: 4, child: pw.Text(p['label'] as String, style: const pw.TextStyle(fontSize: 10))),
                    pw.SizedBox(
                      width: 60,
                      child: pw.Text(
                        isQ ? (p['value'] as String) : '${p['value']}$arrow',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        textAlign: pw.TextAlign.right,
                      ),
                    ),
                    pw.SizedBox(width: 6),
                    pw.SizedBox(width: 40, child: pw.Text(isQ ? '' : (p['unit'] as String), style: const pw.TextStyle(fontSize: 9))),
                    pw.SizedBox(width: 6),
                    if (!isQ)
                      pw.SizedBox(
                        width: 60,
                        child: pw.Text(
                          '${(p['min'] as num) > 0 ? p['min'] : '0'} - ${(p['max'] as num) < 999 ? p['max'] : ''}',
                          style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
                          textAlign: pw.TextAlign.right,
                        ),
                      ),
                  ],
                ),
              ));
            }

            return widgets;
          },
        ),
      );

      await Printing.layoutPdf(onLayout: (format) => pdf.save(), name: 'Blutanalyse_$datum.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // ========== KRANKMELDUNGEN TAB ==========

  // ═══════════════════════════════════════════════════════════════
  // VORSORGE TAB — Zervixkarzinom-Screening (HPV/Pap)
  // ═══════════════════════════════════════════════════════════════
  Widget _buildVorsorgeTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    final geb = widget.user.geburtsdatum;
    int? alter;
    if (geb != null) {
      final gebDatum = DateTime.tryParse(geb.toString());
      if (gebDatum != null) alter = DateTime.now().difference(gebDatum).inDays ~/ 365;
    }
    final geschlecht = widget.user.geschlecht?.toString().toLowerCase() ?? '';
    final isFrau = geschlecht == 'weiblich' || geschlecht == 'w' || geschlecht == 'frau';

    // Screening data
    final vorsorge = data['vorsorge_hpv'] is Map ? Map<String, dynamic>.from(data['vorsorge_hpv'] as Map) : <String, dynamic>{};
    final letztesDatum = vorsorge['letztes_datum']?.toString() ?? '';
    final letztesErgebnis = vorsorge['letztes_ergebnis']?.toString() ?? '';
    final naechstesDatum = vorsorge['naechstes_datum']?.toString() ?? '';

    // Calculate interval based on age
    final int intervallMonate = (alter != null && alter >= 35) ? 36 : 12;
    final String intervallText = intervallMonate == 36 ? 'alle 3 Jahre (Ko-Testung: Pap + HPV)' : 'jährlich (Pap-Abstrich)';
    final String screeningTyp = (alter != null && alter >= 35) ? 'Ko-Testung (Pap-Abstrich + HPV-Test)' : 'Pap-Abstrich (zytologische Untersuchung)';

    // Calculate next due date
    DateTime? naechstFaellig;
    if (letztesDatum.isNotEmpty) {
      final letzte = DateTime.tryParse(letztesDatum);
      if (letzte != null) {
        naechstFaellig = DateTime(letzte.year, letzte.month + intervallMonate, letzte.day);
      }
    }
    final heute = DateTime.now();
    final isOverdue = naechstFaellig != null && heute.isAfter(naechstFaellig);
    final restTage = naechstFaellig != null ? naechstFaellig.difference(heute).inDays : null;
    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.health_and_safety, size: 22, color: Colors.pink.shade700), const SizedBox(width: 8),
          Expanded(child: Text('Zervixkarzinom-Screening', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.pink.shade700))),
        ]),
        const SizedBox(height: 4),
        Text('Gebärmutterhalskrebs-Früherkennung (HPV/Pap)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        const SizedBox(height: 12),

        if (!isFrau)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10)),
            child: Column(children: [
              Icon(Icons.info, size: 32, color: Colors.grey.shade400), const SizedBox(height: 8),
              Text('Nur für weibliche Mitglieder relevant', style: TextStyle(color: Colors.grey.shade600)),
            ]),
          )
        else ...[
          // Status Banner
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: letztesDatum.isEmpty ? Colors.grey.shade50 : isOverdue ? Colors.red.shade50 : (restTage != null && restTage <= 90) ? Colors.orange.shade50 : Colors.green.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: letztesDatum.isEmpty ? Colors.grey.shade300 : isOverdue ? Colors.red.shade300 : (restTage != null && restTage <= 90) ? Colors.orange.shade300 : Colors.green.shade300, width: 2),
            ),
            child: Row(children: [
              Icon(letztesDatum.isEmpty ? Icons.help_outline : isOverdue ? Icons.warning : Icons.check_circle, size: 28,
                color: letztesDatum.isEmpty ? Colors.grey.shade500 : isOverdue ? Colors.red.shade700 : Colors.green.shade700),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(letztesDatum.isEmpty ? 'Kein Screening eingetragen' : isOverdue ? 'Screening überfällig!' : 'Screening aktuell',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: letztesDatum.isEmpty ? Colors.grey.shade700 : isOverdue ? Colors.red.shade800 : Colors.green.shade800)),
                if (naechstFaellig != null) Text('Nächstes Screening: ${fmt(naechstFaellig)}${restTage != null ? ' ($restTage Tage)' : ''}',
                  style: TextStyle(fontSize: 12, color: isOverdue ? Colors.red.shade700 : Colors.green.shade700)),
              ])),
            ]),
          ),
          const SizedBox(height: 16),

          // Info
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.pink.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Screening-Empfehlung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.pink.shade800)),
              const SizedBox(height: 6),
              if (alter != null) ...[
                Row(children: [
                  Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.pink.shade100, borderRadius: BorderRadius.circular(6)),
                    child: Text('Alter: $alter Jahre', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.pink.shade800))),
                  const SizedBox(width: 8),
                  Expanded(child: Text(intervallText, style: TextStyle(fontSize: 11, color: Colors.pink.shade700))),
                ]),
                const SizedBox(height: 4),
                Text('Typ: $screeningTyp', style: TextStyle(fontSize: 11, color: Colors.pink.shade600)),
              ] else
                Text('Geburtsdatum nicht hinterlegt — Intervall kann nicht berechnet werden', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
            ]),
          ),
          const SizedBox(height: 16),

          // Letztes Screening
          Text('Letztes Screening', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          InkWell(
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: DateTime.tryParse(letztesDatum) ?? DateTime.now(), firstDate: DateTime(2015), lastDate: DateTime.now(), locale: const Locale('de'));
              if (p != null) { setLocalState(() { vorsorge['letztes_datum'] = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}'; data['vorsorge_hpv'] = vorsorge; }); saveAll(); }
            },
            child: Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.calendar_today, size: 18, color: Colors.pink.shade600), const SizedBox(width: 8),
                Text(letztesDatum.isEmpty ? 'Datum eintragen...' : letztesDatum, style: TextStyle(fontSize: 14, color: letztesDatum.isEmpty ? Colors.grey.shade400 : Colors.black87, fontStyle: letztesDatum.isEmpty ? FontStyle.italic : FontStyle.normal)),
                const Spacer(),
                Icon(Icons.edit_calendar, size: 16, color: Colors.pink.shade400),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: letztesErgebnis.isEmpty ? null : letztesErgebnis,
            decoration: InputDecoration(labelText: 'Ergebnis', prefixIcon: Icon(Icons.science, size: 18, color: Colors.pink.shade400), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: const [
              DropdownMenuItem(value: 'unauffaellig', child: Text('Unauffällig (Pap I/II)', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'kontrollbeduerftig', child: Text('Kontrollbedürftig (Pap III/IIID)', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'auffaellig', child: Text('Auffällig (Pap IV/V)', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'hpv_positiv', child: Text('HPV-positiv', style: TextStyle(fontSize: 13))),
              DropdownMenuItem(value: 'hpv_negativ', child: Text('HPV-negativ', style: TextStyle(fontSize: 13))),
            ],
            onChanged: (v) { setLocalState(() { vorsorge['letztes_ergebnis'] = v; data['vorsorge_hpv'] = vorsorge; }); saveAll(); },
          ),
          const SizedBox(height: 16),

          // Rechtsgrundlage
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Rechtsgrundlage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              _vorsorgeInfoRow('20–34 Jahre', 'Jährlich Pap-Abstrich (zytologische Untersuchung)'),
              _vorsorgeInfoRow('Ab 35 Jahre', 'Alle 3 Jahre Ko-Testung (Pap + HPV-Test)'),
              _vorsorgeInfoRow('Einladung', 'Krankenkasse lädt alle 5 Jahre ein (20, 25, 30, 35...)'),
              _vorsorgeInfoRow('Grundlage', 'G-BA Richtlinie Organisiertes Krebsfrüherkennungsprogramm'),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _vorsorgeInfoRow(String label, String text) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.pink.shade700))),
      const SizedBox(width: 8),
      Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
    ]));
  }

  Widget _buildKrankmeldungenTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    final List<dynamic> krankmeldungen = data['krankmeldungen'] is List ? data['krankmeldungen'] as List : [];

    void showKrankmeldungDialog({Map<String, dynamic>? existing, int? editIndex}) {
      final feststellungC = TextEditingController(text: existing?['feststellungsdatum']?.toString() ?? '');
      final auBeginnC = TextEditingController(text: existing?['au_beginn']?.toString() ?? '');
      final auEndeC = TextEditingController(text: existing?['au_ende']?.toString() ?? '');
      final diagnoseC = TextEditingController(text: existing?['diagnose']?.toString() ?? '');
      final icdCodeC = TextEditingController(text: existing?['icd_code']?.toString() ?? '');
      String art = existing?['art']?.toString() ?? 'erst';
      bool arbeitsunfall = existing?['arbeitsunfall'] == true;


      Future<void> pickDate(BuildContext dlgCtx, TextEditingController ctrl) async {
        final picked = await showDatePicker(
          context: dlgCtx,
          initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2040),
          locale: const Locale('de'),
        );
        if (picked != null) {
          ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
        }
      }

      showDialog(
        context: context,
        builder: (dlgCtx) => StatefulBuilder(
          builder: (dlgCtx, setDlgState) => AlertDialog(
            title: Row(children: [
              Icon(Icons.local_hospital, size: 18, color: Colors.pink.shade700),
              const SizedBox(width: 8),
              Text(editIndex != null ? 'Krankmeldung bearbeiten' : 'Neue Krankmeldung', style: const TextStyle(fontSize: 15)),
            ]),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: art,
                      decoration: InputDecoration(labelText: 'Art der Bescheinigung', prefixIcon: const Icon(Icons.description, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      items: const [
                        DropdownMenuItem(value: 'erst', child: Text('Erstbescheinigung', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'folge', child: Text('Folgebescheinigung', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) => setDlgState(() => art = v ?? 'erst'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: feststellungC,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Feststellungsdatum (Ausstellungsdatum)',
                        prefixIcon: const Icon(Icons.event_note, size: 18),
                        suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDate(dlgCtx, feststellungC).then((_) => setDlgState(() {}))),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: auBeginnC,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'AU-Beginn (arbeitsunf\u00E4hig seit)',
                        prefixIcon: const Icon(Icons.play_arrow, size: 18),
                        suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDate(dlgCtx, auBeginnC).then((_) => setDlgState(() {}))),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: auEndeC,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Voraussichtl. AU-Ende',
                        prefixIcon: const Icon(Icons.stop, size: 18),
                        suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDate(dlgCtx, auEndeC).then((_) => setDlgState(() {}))),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: diagnoseC,
                      decoration: InputDecoration(
                        labelText: 'Diagnose (optional)',
                        prefixIcon: const Icon(Icons.medical_information, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: icdCodeC,
                      decoration: InputDecoration(
                        labelText: 'ICD-Code (optional, z.B. J06.9)',
                        prefixIcon: const Icon(Icons.code, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      title: const Text('Arbeitsunfall', style: TextStyle(fontSize: 13)),
                      subtitle: const Text('Unfall w\u00E4hrend der Arbeit oder auf dem Arbeitsweg', style: TextStyle(fontSize: 11)),
                      value: arbeitsunfall,
                      activeTrackColor: Colors.red.shade200,
                      activeThumbColor: Colors.red.shade700,
                      onChanged: (v) => setDlgState(() => arbeitsunfall = v),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
              FilledButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Speichern'),
                onPressed: () async {
                  if (auBeginnC.text.isEmpty) return;
                  final entry = <String, dynamic>{
                    'art': art,
                    'erstbescheinigung': art == 'erst',
                    'feststellungsdatum': feststellungC.text.isNotEmpty ? feststellungC.text : null,
                    'au_beginn': auBeginnC.text,
                    'au_ende': auEndeC.text.isNotEmpty ? auEndeC.text : null,
                    'diagnose': diagnoseC.text.isNotEmpty ? diagnoseC.text : null,
                    'icd_code': icdCodeC.text.isNotEmpty ? icdCodeC.text : null,
                    'arbeitsunfall': arbeitsunfall,
                    'arzt': arztTitle,
                  };
                  // Preserve existing versand data on edit
                  if (editIndex != null && existing != null) {
                    for (final key in ['versand_jobcenter', 'versand_jobcenter_datum', 'versand_jobcenter_art', 'versand_krankenkasse', 'versand_krankenkasse_datum', 'versand_krankenkasse_art']) {
                      if (existing.containsKey(key)) entry[key] = existing[key];
                    }
                  }
                  final isNew = editIndex == null;
                  final list = List<dynamic>.from(krankmeldungen);
                  int savedIndex;
                  if (editIndex != null && editIndex < list.length) {
                    list[editIndex] = entry;
                    savedIndex = editIndex;
                  } else {
                    list.add(entry);
                    savedIndex = list.length - 1;
                  }
                  data['krankmeldungen'] = list;

                  // Save values before pop destroys controllers
                  final savedAuEnde = auEndeC.text;
                  final savedDiagnose = diagnoseC.text;

                  Navigator.pop(dlgCtx);
                  saveAll();
                  setLocalState(() {});

                  // Show Versand dialog after creating a new Krankmeldung
                  if (isNew && mounted) {
                    await Future.delayed(const Duration(milliseconds: 300));
                    if (mounted) {
                      _showVersandDialog(data, list, savedIndex, saveAll, setLocalState);
                    }
                  }

                  // Auto-create ticket 1 day before AU-Ende to ask member about renewal
                  if (savedAuEnde.isNotEmpty) {
                    final auEnde = DateTime.tryParse(savedAuEnde);
                    if (auEnde != null) {
                      final reminderDate = auEnde.subtract(const Duration(days: 1));
                      final diagnoseText = savedDiagnose.isNotEmpty ? ' ($savedDiagnose)' : '';
                      final formattedEnde = DateFormat('dd.MM.yyyy').format(auEnde);
                      try {
                        final result = await widget.ticketService.createTicketForMember(
                          adminMitgliedernummer: widget.adminMitgliedernummer,
                          memberMitgliedernummer: widget.user.mitgliedernummer,
                          subject: 'AU-Erneuerung \u2013 Krankmeldung l\u00E4uft ab am $formattedEnde',
                          message: 'Sehr geehrtes Mitglied,\n\n'
                              'Ihre Krankmeldung$diagnoseText l\u00E4uft am $formattedEnde ab.\n\n'
                              'M\u00F6chten Sie Ihre AU erneuern?\n\n'
                              '\u2022 Ja\n'
                              '\u2022 Nein\n\n'
                              'Mit freundlichen Gr\u00FC\u00DFen,\nIhr Vorsitz',
                          priority: 'high',
                          scheduledDate: DateFormat('yyyy-MM-dd').format(reminderDate),
                          systemAuto: true,
                        );
                        if (result.containsKey('ticket') && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Erinnerungsticket f\u00FCr $formattedEnde erstellt'), backgroundColor: Colors.green),
                          );
                        } else if (result.containsKey('error') && mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Ticket-Hinweis: ${result['error']}'), backgroundColor: Colors.orange),
                          );
                        }
                      } catch (e) {
                        debugPrint('Krankmeldung ticket error: $e');
                      }
                    }
                  }
                },
              ),
            ],
          ),
        ),
      );
    }

    return StatefulBuilder(
      builder: (context, setTabState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // eAU info banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.yellow.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.yellow.shade600),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.yellow.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Seit 01.01.2023 gilt die eAU (elektronische Arbeitsunf\u00E4higkeitsbescheinigung). Der Arbeitgeber ruft die AU direkt bei der Krankenkasse ab.',
                        style: TextStyle(fontSize: 11, color: Colors.yellow.shade900, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Header + Add button
              Row(
                children: [
                  Icon(Icons.healing, size: 16, color: Colors.pink.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Krankmeldungen (${krankmeldungen.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.pink.shade700))),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Hinzuf\u00FCgen', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.pink.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () => showKrankmeldungDialog(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (krankmeldungen.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        Icon(Icons.healing, size: 40, color: Colors.grey.shade400),
                        const SizedBox(height: 8),
                        Text('Keine Krankmeldungen vorhanden', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                        const SizedBox(height: 4),
                        Text('Klicke "Hinzuf\u00FCgen" um eine Krankmeldung zu erfassen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                      ],
                    ),
                  ),
                )
              else
                ...krankmeldungen.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final km = entry.value is Map<String, dynamic> ? entry.value as Map<String, dynamic> : <String, dynamic>{};
                  final isErst = km['erstbescheinigung'] == true || km['art'] == 'erst';
                  final isUnfall = km['arbeitsunfall'] == true;
                  final auBeginn = DateTime.tryParse(km['au_beginn']?.toString() ?? '');
                  final auEnde = DateTime.tryParse(km['au_ende']?.toString() ?? '');
                  final dauerTage = (auBeginn != null && auEnde != null) ? auEnde.difference(auBeginn).inDays + 1 : null;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isErst ? Colors.blue.shade200 : Colors.orange.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header: badges + actions
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isErst ? Colors.blue.shade100 : Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                isErst ? 'Erstbescheinigung' : 'Folgebescheinigung',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isErst ? Colors.blue.shade800 : Colors.orange.shade800),
                              ),
                            ),
                            if (isUnfall) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(6)),
                                child: Text('Arbeitsunfall', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                              ),
                            ],
                            if (dauerTage != null) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(6)),
                                child: Text('$dauerTage Tage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                              ),
                            ],
                            const Spacer(),
                            Tooltip(
                              message: 'Versand an Jobcenter/Krankenkasse',
                              child: InkWell(
                                onTap: () => _showVersandDialog(data, List<dynamic>.from(krankmeldungen), idx, saveAll, setLocalState),
                                child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.send, size: 16, color: Colors.deepPurple.shade600)),
                              ),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () => showKrankmeldungDialog(existing: km, editIndex: idx),
                              child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.edit, size: 16, color: Colors.blue.shade600)),
                            ),
                            const SizedBox(width: 4),
                            InkWell(
                              onTap: () {
                                final list = List<dynamic>.from(krankmeldungen);
                                list.removeAt(idx);
                                data['krankmeldungen'] = list;
                                saveAll();
                                setLocalState(() {});
                                setTabState(() {});
                              },
                              child: Padding(padding: const EdgeInsets.all(4), child: Icon(Icons.delete, size: 16, color: Colors.red.shade400)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        _buildDetailRow(Icons.event_note, 'Feststellungsdatum', km['feststellungsdatum']?.toString() ?? '-'),
                        _buildDetailRow(Icons.play_arrow, 'AU-Beginn', km['au_beginn']?.toString() ?? '-'),
                        _buildDetailRow(Icons.stop, 'AU-Ende', km['au_ende']?.toString() ?? '-'),
                        if (km['diagnose'] != null && km['diagnose'].toString().isNotEmpty)
                          _buildDetailRow(Icons.medical_information, 'Diagnose', km['diagnose'].toString()),
                        if (km['icd_code'] != null && km['icd_code'].toString().isNotEmpty)
                          _buildDetailRow(Icons.code, 'ICD-Code', km['icd_code'].toString()),
                        // Versand Status
                        if (km['versand_jobcenter'] == true || km['versand_krankenkasse'] == true) ...[
                          const SizedBox(height: 6),
                          Divider(color: Colors.grey.shade200, height: 1),
                          const SizedBox(height: 6),
                        ],
                        if (km['versand_jobcenter'] == true)
                          _buildVersandRow(Icons.business, 'Jobcenter', km['versand_jobcenter_datum']?.toString(), km['versand_jobcenter_art']?.toString(), Colors.indigo, person1: km['versand_jc_person1']?.toString(), person2: km['versand_jc_person2']?.toString()),
                        if (km['versand_krankenkasse'] == true)
                          _buildVersandRow(Icons.health_and_safety, 'Krankenkasse', km['versand_krankenkasse_datum']?.toString(), km['versand_krankenkasse_art']?.toString(), Colors.teal, person1: km['versand_kk_person1']?.toString(), person2: km['versand_kk_person2']?.toString()),
                        if (km['versand_jobcenter'] != true && km['versand_krankenkasse'] != true)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(children: [
                              Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade600),
                              const SizedBox(width: 4),
                              Text('Noch nicht versendet', style: TextStyle(fontSize: 10, color: Colors.orange.shade600, fontStyle: FontStyle.italic)),
                            ]),
                          ),
                      ],
                    ),
                  );
                }),
              const SizedBox(height: 12),
              // Regeln info
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 8, left: 4, right: 4),
                dense: true,
                leading: Icon(Icons.gavel, size: 16, color: Colors.teal.shade600),
                title: Text('Pflichten bei Krankheit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal.shade700)),
                children: [
                  _buildDetailRow(Icons.notification_important, 'Meldepflicht', 'Sofort am 1. Krankheitstag (\u00A75 EFZG)'),
                  _buildDetailRow(Icons.assignment, 'AU-Bescheinigung', 'Sp\u00E4testens am 4. Kalendertag'),
                  _buildDetailRow(Icons.sync, 'Folgebescheinigung', 'Am n\u00E4chsten Werktag nach Ablauf'),
                  _buildDetailRow(Icons.warning, 'Versto\u00DF', 'Abmahnung oder K\u00FCndigung m\u00F6glich'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))),
        ],
      ),
    );
  }

  void _showVersandDialog(Map<String, dynamic> data, List<dynamic> list, int index, VoidCallback saveAll, StateSetter setLocalState) {
    final km = list[index] is Map<String, dynamic> ? list[index] as Map<String, dynamic> : <String, dynamic>{};
    bool vJc = km['versand_jobcenter'] == true;
    String vJcDatum = km['versand_jobcenter_datum']?.toString() ?? '';
    String vJcArt = km['versand_jobcenter_art']?.toString() ?? '';
    String vJcPerson1 = km['versand_jc_person1']?.toString() ?? '';
    String vJcPerson2 = km['versand_jc_person2']?.toString() ?? '';
    bool vKk = km['versand_krankenkasse'] == true;
    String vKkDatum = km['versand_krankenkasse_datum']?.toString() ?? '';
    String vKkArt = km['versand_krankenkasse_art']?.toString() ?? '';
    String vKkPerson1 = km['versand_kk_person1']?.toString() ?? '';
    String vKkPerson2 = km['versand_kk_person2']?.toString() ?? '';

    final vJcDatumC = TextEditingController(text: vJcDatum);
    final vKkDatumC = TextEditingController(text: vKkDatum);

    // Load admin users (vorsitzer + schatzmeister) for Auftragsnehmer
    List<Map<String, String>> adminPersonen = [];
    bool adminLoaded = false;

    Future<void> pickDateTime(BuildContext ctx, TextEditingController ctrl, StateSetter setState, void Function(String) onSet) async {
      final date = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(ctrl.text.split(' ').first) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
      if (date != null && ctx.mounted) {
        final time = await showTimePicker(context: ctx, initialTime: TimeOfDay.now());
        if (time != null) {
          final val = '${DateFormat('yyyy-MM-dd').format(date)} ${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
          ctrl.text = val;
          setState(() => onSet(val));
        }
      }
    }

    const versandArten = [
      DropdownMenuItem(value: 'online', child: Text('Online', style: TextStyle(fontSize: 13))),
      DropdownMenuItem(value: 'postalisch', child: Text('Postalisch', style: TextStyle(fontSize: 13))),
      DropdownMenuItem(value: 'persoenlich', child: Text('Pers\u00F6nlich', style: TextStyle(fontSize: 13))),
      DropdownMenuItem(value: 'persoenlich_postalisch', child: Text('Pers\u00F6nlich + Postalisch', style: TextStyle(fontSize: 13))),
    ];

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          // Load admin users once
          if (!adminLoaded) {
            adminLoaded = true;
            widget.apiService.getUsers().then((result) {
              if (result['success'] == true && result['users'] is List) {
                final users = result['users'] as List;
                final filtered = users.where((u) => u['role'] == 'vorsitzer' || u['role'] == 'schatzmeister').toList();
                setDlgState(() {
                  adminPersonen = filtered.map((u) => <String, String>{
                    'id': u['mitgliedernummer']?.toString() ?? '',
                    'name': u['name']?.toString() ?? '',
                    'role': u['role']?.toString() ?? '',
                  }).toList();
                });
              }
            }).catchError((_) {});
          }

          bool needsPerson(String art) => art == 'postalisch' || art == 'persoenlich' || art == 'persoenlich_postalisch';

          Widget buildPersonDropdown(String label, String value, bool isRequired, void Function(String) onChanged) {
            return DropdownButtonFormField<String>(
              initialValue: value.isNotEmpty ? value : null,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: '$label${isRequired ? ' *' : ''}',
                prefixIcon: const Icon(Icons.person, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              hint: Text(isRequired ? 'Pflichtfeld' : 'Optional', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              items: [
                if (!isRequired)
                  const DropdownMenuItem(value: '', child: Text('\u2014 Keine \u2014', style: TextStyle(fontSize: 12, color: Colors.grey))),
                ...adminPersonen.map((p) => DropdownMenuItem(
                  value: p['name'],
                  child: Text('${p['name']} (${p['role'] == 'vorsitzer' ? 'Vorsitzer' : 'Schatzmeister'})', style: const TextStyle(fontSize: 12)),
                )),
              ],
              onChanged: (v) => setDlgState(() => onChanged(v ?? '')),
            );
          }

          return AlertDialog(
          title: Row(children: [
            Icon(Icons.send, size: 18, color: Colors.deepPurple.shade700),
            const SizedBox(width: 8),
            const Text('Krankmeldung Versand', style: TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Details header
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(km['erstbescheinigung'] == true || km['art'] == 'erst' ? 'Erstbescheinigung' : 'Folgebescheinigung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                        if (km['au_beginn'] != null) Text('AU: ${km['au_beginn']} \u2013 ${km['au_ende'] ?? '?'}', style: const TextStyle(fontSize: 11)),
                        if (km['diagnose'] != null && km['diagnose'].toString().isNotEmpty) Text('Diagnose: ${km['diagnose']}', style: const TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // ===== JOBCENTER =====
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: vJc ? Colors.indigo.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: vJc ? Colors.indigo.shade300 : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: Text('An Jobcenter gesendet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.indigo.shade700)),
                          secondary: Icon(Icons.business, size: 20, color: Colors.indigo.shade400),
                          value: vJc,
                          activeTrackColor: Colors.indigo.shade200,
                          activeThumbColor: Colors.indigo.shade700,
                          onChanged: (v) => setDlgState(() => vJc = v),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (vJc) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: vJcDatumC,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Datum & Uhrzeit',
                              prefixIcon: const Icon(Icons.schedule, size: 18),
                              suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDateTime(dlgCtx, vJcDatumC, setDlgState, (v) => vJcDatum = v)),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: vJcArt.isNotEmpty ? vJcArt : null,
                            decoration: InputDecoration(labelText: 'Versandart', prefixIcon: const Icon(Icons.send, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                            items: versandArten,
                            onChanged: (v) => setDlgState(() => vJcArt = v ?? ''),
                          ),
                          // Auftragsnehmer (only for postalisch/persoenlich)
                          if (needsPerson(vJcArt) && adminPersonen.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.indigo.shade50.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Auftragsnehmer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                                  const SizedBox(height: 6),
                                  buildPersonDropdown('1. Person', vJcPerson1, true, (v) => vJcPerson1 = v),
                                  const SizedBox(height: 6),
                                  buildPersonDropdown('2. Person', vJcPerson2, false, (v) => vJcPerson2 = v),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // ===== KRANKENKASSE =====
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: vKk ? Colors.teal.shade50 : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: vKk ? Colors.teal.shade300 : Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SwitchListTile(
                          title: Text('An Krankenkasse gesendet', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.teal.shade700)),
                          secondary: Icon(Icons.health_and_safety, size: 20, color: Colors.teal.shade400),
                          value: vKk,
                          activeTrackColor: Colors.teal.shade200,
                          activeThumbColor: Colors.teal.shade700,
                          onChanged: (v) => setDlgState(() => vKk = v),
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                        ),
                        if (vKk) ...[
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: vKkDatumC,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Datum & Uhrzeit',
                              prefixIcon: const Icon(Icons.schedule, size: 18),
                              suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDateTime(dlgCtx, vKkDatumC, setDlgState, (v) => vKkDatum = v)),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          DropdownButtonFormField<String>(
                            initialValue: vKkArt.isNotEmpty ? vKkArt : null,
                            decoration: InputDecoration(labelText: 'Versandart', prefixIcon: const Icon(Icons.send, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                            items: versandArten,
                            onChanged: (v) => setDlgState(() => vKkArt = v ?? ''),
                          ),
                          // Auftragsnehmer (only for postalisch/persoenlich)
                          if (needsPerson(vKkArt) && adminPersonen.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.teal.shade50.withValues(alpha: 0.5), borderRadius: BorderRadius.circular(6)),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Auftragsnehmer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                                  const SizedBox(height: 6),
                                  buildPersonDropdown('1. Person', vKkPerson1, true, (v) => vKkPerson1 = v),
                                  const SizedBox(height: 6),
                                  buildPersonDropdown('2. Person', vKkPerson2, false, (v) => vKkPerson2 = v),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Sp\u00E4ter')),
            FilledButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade600),
              onPressed: () {
                final updated = Map<String, dynamic>.from(km);
                updated['versand_jobcenter'] = vJc;
                updated['versand_jobcenter_datum'] = vJc && vJcDatumC.text.isNotEmpty ? vJcDatumC.text : null;
                updated['versand_jobcenter_art'] = vJc && vJcArt.isNotEmpty ? vJcArt : null;
                updated['versand_jc_person1'] = vJc && vJcPerson1.isNotEmpty ? vJcPerson1 : null;
                updated['versand_jc_person2'] = vJc && vJcPerson2.isNotEmpty ? vJcPerson2 : null;
                updated['versand_krankenkasse'] = vKk;
                updated['versand_krankenkasse_datum'] = vKk && vKkDatumC.text.isNotEmpty ? vKkDatumC.text : null;
                updated['versand_krankenkasse_art'] = vKk && vKkArt.isNotEmpty ? vKkArt : null;
                updated['versand_kk_person1'] = vKk && vKkPerson1.isNotEmpty ? vKkPerson1 : null;
                updated['versand_kk_person2'] = vKk && vKkPerson2.isNotEmpty ? vKkPerson2 : null;
                list[index] = updated;
                data['krankmeldungen'] = list;
                Navigator.pop(dlgCtx);
                saveAll();
                setLocalState(() {});
              },
            ),
          ],
        );
        },
      ),
    );
  }

  Widget _buildVersandRow(IconData icon, String ziel, String? datum, String? art, MaterialColor color, {String? person1, String? person2}) {
    String artText = '';
    if (art != null) {
      switch (art) {
        case 'online': artText = 'Online'; break;
        case 'postalisch': artText = 'Postalisch'; break;
        case 'persoenlich': artText = 'Pers\u00F6nlich'; break;
        case 'persoenlich_postalisch': artText = 'Pers\u00F6nlich + Postalisch'; break;
        default: artText = art;
      }
    }
    final hasPersonen = (person1 != null && person1.isNotEmpty) || (person2 != null && person2.isNotEmpty);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle, size: 14, color: color.shade600),
              const SizedBox(width: 4),
              Icon(icon, size: 14, color: color.shade400),
              const SizedBox(width: 4),
              Text('$ziel: ', style: TextStyle(fontSize: 11, color: color.shade700, fontWeight: FontWeight.w600)),
              if (datum != null && datum.isNotEmpty)
                Text('$datum ', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500)),
              if (artText.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: color.shade200)),
                  child: Text(artText, style: TextStyle(fontSize: 9, color: color.shade700, fontWeight: FontWeight.bold)),
                ),
            ],
          ),
          if (hasPersonen)
            Padding(
              padding: const EdgeInsets.only(left: 22, top: 2),
              child: Row(
                children: [
                  Icon(Icons.person, size: 12, color: color.shade400),
                  const SizedBox(width: 3),
                  Text(
                    [
                      if (person1 != null && person1.isNotEmpty) person1,
                      if (person2 != null && person2.isNotEmpty) person2,
                    ].join(' & '),
                    style: TextStyle(fontSize: 10, color: color.shade600, fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // ========== ÜBERWEISUNG TAB ==========

  Widget _buildUeberweisungTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    final List<dynamic> ueberweisungen = data['ueberweisungen'] is List ? data['ueberweisungen'] as List : [];

    void showUeberweisungDialog({Map<String, dynamic>? existing, int? editIndex, Map<String, dynamic>? kkData}) {
      final arztData = data['selected_arzt'] is Map ? data['selected_arzt'] as Map : {};
      final user = widget.user;
      final userName = '${user.vorname ?? ''} ${user.nachname ?? ''}'.trim();

      final adresseDefault = [
        '${user.strasse ?? ''} ${user.hausnummer ?? ''}'.trim(),
        '${user.plz ?? ''} ${user.ort ?? ''}'.trim(),
      ].where((s) => s.isNotEmpty).join(', ');

      final datumC = TextEditingController(text: existing?['datum']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
      final patientC = TextEditingController(text: existing?['patient']?.toString() ?? userName);
      final gebDatumC = TextEditingController(text: existing?['geb_datum']?.toString() ?? (user.geburtsdatum ?? ''));
      final adresseC = TextEditingController(text: existing?['adresse']?.toString() ?? adresseDefault);
      const ueberweisungAnOptionen = [
        'Radiologie', 'Orthopädie', 'Kardiologie', 'Neurologie', 'Dermatologie',
        'Augenheilkunde', 'HNO', 'Urologie', 'Gynäkologie', 'Pädiatrie',
        'Psychiatrie / Psychotherapie', 'Gastroenterologie', 'Pneumologie',
        'Rheumatologie', 'Endokrinologie', 'Nephrologie', 'Hämatologie / Onkologie',
        'Chirurgie', 'Innere Medizin', 'Allgemeinmedizin', 'Sportmedizin',
        'Physiotherapie', 'Ergotherapie', 'Labor',
      ];
      String anSelected = existing?['an']?.toString() ?? '';
      final fachrichtungC = TextEditingController(text: existing?['fachrichtung']?.toString() ?? '');
      final krankenkasseC = TextEditingController(text: existing?['krankenkasse']?.toString() ?? kkData?['name']?.toString() ?? '');
      final versichertenNrC = TextEditingController(text: existing?['versicherten_nr']?.toString() ?? kkData?['versichertennummer']?.toString() ?? '');
      final kostentraegerC = TextEditingController(text: existing?['kostentraeger_kennung']?.toString() ?? kkData?['ehic_institutionskennzeichen']?.toString() ?? '');
      final bsnrC = TextEditingController(text: existing?['bsnr']?.toString() ?? arztData['bsnr']?.toString() ?? '');
      final lanrC = TextEditingController(text: existing?['lanr']?.toString() ?? arztData['lanr']?.toString() ?? '');
      final diagnoseC = TextEditingController(text: existing?['diagnose']?.toString() ?? '');
      final icdCodeC = TextEditingController(text: existing?['icd_code']?.toString() ?? '');
      final befundeC = TextEditingController(text: existing?['befunde']?.toString() ?? '');
      final auftragC = TextEditingController(text: existing?['auftrag']?.toString() ?? '');
      final ausfuehrungC = TextEditingController(text: existing?['ausfuehrung_text']?.toString() ?? '');
      // Backward compat: old entries had sub-types directly in 'art'
      const oldSubValues = {'mitbehandlung', 'weiterbehandlung', 'konsil', 'auftragsleistung', 'ausfuehrung', 'diagnostik'};
      final rawArt = existing?['art']?.toString() ?? 'kurativ';
      String art = oldSubValues.contains(rawArt) ? 'kurativ' : (rawArt.isNotEmpty ? rawArt : 'kurativ');
      String artSub = existing?['art_sub']?.toString() ??
          (oldSubValues.contains(rawArt)
              ? (rawArt == 'ausfuehrung'
                  ? 'auftragsleistung'
                  : rawArt == 'diagnostik'
                      ? 'mitbehandlung'
                      : rawArt)
              : 'mitbehandlung');

      // Versicherungsstatus: prefer saved, then from KK behörde, default '1000000'
      final validStatuses = {'', '1000000', '1010000', '1060000', '3000000', '3010000', '5000000', '5010000', '9000000'};
      String versicherungsstatus = existing?['versicherungsstatus']?.toString() ?? kkData?['versichertenstatus']?.toString() ?? '1000000';
      if (!validStatuses.contains(versicherungsstatus)) versicherungsstatus = '1000000';

      final userGeschlecht = user.geschlecht;
      String geschlecht = existing?['geschlecht']?.toString() ?? (userGeschlecht != null && ['M','W','D'].contains(userGeschlecht) ? userGeschlecht : 'M');
      String status = existing?['status']?.toString() ?? 'offen';

      Future<void> pickDate(BuildContext dlgCtx, TextEditingController ctrl) async {
        final picked = await showDatePicker(
          context: dlgCtx,
          initialDate: DateTime.tryParse(ctrl.text) ?? DateTime.now(),
          firstDate: DateTime(2000),
          lastDate: DateTime(2040),
          locale: const Locale('de'),
        );
        if (picked != null) ctrl.text = DateFormat('yyyy-MM-dd').format(picked);
      }

      Widget sectionHeader(String label) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        child: Row(children: [
          Expanded(child: Divider(color: Colors.indigo.shade200)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade600)),
          ),
          Expanded(child: Divider(color: Colors.indigo.shade200)),
        ]),
      );

      showDialog(
        context: context,
        builder: (dlgCtx) => StatefulBuilder(
          builder: (dlgCtx, setDlgState) => AlertDialog(
            title: Row(children: [
              Icon(Icons.swap_horiz, size: 18, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              Text(editIndex != null ? 'Überweisung bearbeiten' : 'Neue Überweisung (Muster 6)', style: const TextStyle(fontSize: 15)),
            ]),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── ABSCHNITT 1: Patient ──
                    sectionHeader('PATIENT'),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: patientC,
                          decoration: InputDecoration(
                            labelText: 'Name, Vorname',
                            prefixIcon: const Icon(Icons.person, size: 18),
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: gebDatumC,
                          decoration: InputDecoration(
                            labelText: 'geb. am',
                            prefixIcon: const Icon(Icons.cake, size: 18),
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: adresseC,
                      decoration: InputDecoration(
                        labelText: 'Straße, PLZ Ort',
                        prefixIcon: const Icon(Icons.location_on, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // ── ABSCHNITT 2: Versicherung ──
                    sectionHeader('VERSICHERUNGSDATEN'),
                    TextFormField(
                      controller: krankenkasseC,
                      decoration: InputDecoration(
                        labelText: 'Krankenkasse / Kostenträger',
                        prefixIcon: const Icon(Icons.business, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: versichertenNrC,
                          decoration: InputDecoration(
                            labelText: 'Versicherten-Nr.',
                            prefixIcon: const Icon(Icons.badge, size: 18),
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: kostentraegerC,
                          decoration: InputDecoration(
                            labelText: 'Kostenträger-IK',
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: versicherungsstatus,
                      decoration: InputDecoration(
                        labelText: 'Versicherungsstatus',
                        prefixIcon: const Icon(Icons.verified_user, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('Nicht ausgewählt', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: '1000000', child: Text('1000000 – Mitglied (GKV)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '1010000', child: Text('1010000 – Mitglied (BVG)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '1060000', child: Text('1060000 – Mitglied (Sozialhilfe)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '3000000', child: Text('3000000 – Familienversicherter', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '3010000', child: Text('3010000 – Familienversicherter (BVG)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '5000000', child: Text('5000000 – Rentner (KVdR)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '5010000', child: Text('5010000 – Rentner (BVG)', style: TextStyle(fontSize: 12))),
                        DropdownMenuItem(value: '9000000', child: Text('9000000 – Sonstiger Kostenträger', style: TextStyle(fontSize: 12))),
                      ],
                      onChanged: (v) => setDlgState(() => versicherungsstatus = v ?? '1000000'),
                    ),
                    const SizedBox(height: 10),
                    Row(children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          isExpanded: true,
                          initialValue: geschlecht,
                          decoration: InputDecoration(
                            labelText: 'Geschlecht',
                            prefixIcon: const Icon(Icons.person_outline, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          items: const [
                            DropdownMenuItem(value: 'M', child: Text('M – männlich', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'W', child: Text('W – weiblich', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'D', child: Text('D – divers', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) => setDlgState(() => geschlecht = v ?? 'M'),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    // ── ABSCHNITT 2: Überweisung ──
                    sectionHeader('ÜBERWEISUNG'),
                    TextFormField(
                      controller: datumC,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Ausstellungsdatum',
                        prefixIcon: const Icon(Icons.event_note, size: 18),
                        suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () => pickDate(dlgCtx, datumC).then((_) => setDlgState(() {}))),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    // Niveau 1: Art der Überweisung (Kurativ / Präventiv / §116b / Belegärztlich)
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: art,
                      decoration: InputDecoration(
                        labelText: 'Art der Überweisung',
                        prefixIcon: const Icon(Icons.category, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'kurativ', child: Text('Kurativ', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'praeventiv', child: Text('Präventiv', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: '116b', child: Text('Behandlung gem. § 116b SGB V', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'belegaerztlich', child: Text('Bei belegärztlicher Behandlung', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) => setDlgState(() => art = v ?? 'kurativ'),
                    ),
                    // Niveau 2: Überweisungsart — nur bei Kurativ
                    if (art == 'kurativ') ...[
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: artSub,
                        decoration: InputDecoration(
                          labelText: 'Überweisungsart',
                          prefixIcon: const Icon(Icons.subdirectory_arrow_right, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'mitbehandlung', child: Text('Zur Mitbehandlung', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'weiterbehandlung', child: Text('Zur Weiterbehandlung', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'konsil', child: Text('Konsiliaruntersuchung', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'auftragsleistung', child: Text('Zur Auftragsleistung', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setDlgState(() => artSub = v ?? 'mitbehandlung'),
                      ),
                      // Ausführung von — nur bei Auftragsleistung
                      if (artSub == 'auftragsleistung') ...[
                        const SizedBox(height: 10),
                        TextFormField(
                          controller: ausfuehrungC,
                          decoration: InputDecoration(
                            labelText: 'Ausführung von (Leistungen)',
                            hintText: 'z. B. Röntgen, Labor, EKG ...',
                            prefixIcon: const Icon(Icons.playlist_add_check, size: 18),
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: ueberweisungAnOptionen.contains(anSelected) ? anSelected : null,
                      decoration: InputDecoration(
                        labelText: 'Überwiesen an (Fachrichtung)',
                        prefixIcon: const Icon(Icons.local_hospital, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      hint: const Text('Fachrichtung auswählen', style: TextStyle(fontSize: 13)),
                      items: ueberweisungAnOptionen.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) => setDlgState(() {
                        anSelected = v ?? '';
                        if (fachrichtungC.text.isEmpty) fachrichtungC.text = v ?? '';
                      }),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: fachrichtungC,
                      decoration: InputDecoration(
                        labelText: 'Fachrichtung (z.B. Orthopädie)',
                        prefixIcon: const Icon(Icons.medical_services, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // ── ABSCHNITT 3: Medizin ──
                    sectionHeader('MEDIZINISCHE ANGABEN'),
                    Row(children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: diagnoseC,
                          decoration: InputDecoration(
                            labelText: 'Diagnose / Verdachtsdiagnose',
                            prefixIcon: const Icon(Icons.medical_information, size: 18),
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: icdCodeC,
                          decoration: InputDecoration(
                            labelText: 'ICD-Code',
                            prefixIcon: const Icon(Icons.code, size: 18),
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: befundeC,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Befunde / Bemerkungen',
                        prefixIcon: const Icon(Icons.notes, size: 18),
                        alignLabelWithHint: true,
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: auftragC,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Auftrag',
                        hintText: 'z. B. Bitte um Mitbehandlung wegen...',
                        prefixIcon: const Icon(Icons.assignment, size: 18),
                        alignLabelWithHint: true,
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // ── ABSCHNITT 4: Arzt ──
                    sectionHeader('ARZTDATEN (optional)'),
                    Row(children: [
                      Expanded(
                        child: TextFormField(
                          controller: bsnrC,
                          decoration: InputDecoration(
                            labelText: 'BSNR (Betriebsstätten-Nr.)',
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextFormField(
                          controller: lanrC,
                          decoration: InputDecoration(
                            labelText: 'LANR (Arzt-Nr.)',
                            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(
                        labelText: 'Status',
                        prefixIcon: const Icon(Icons.check_circle_outline, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'offen', child: Text('Offen', style: TextStyle(fontSize: 13))),
                        DropdownMenuItem(value: 'erledigt', child: Text('Erledigt', style: TextStyle(fontSize: 13))),
                      ],
                      onChanged: (v) => setDlgState(() => status = v ?? 'offen'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
              FilledButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Speichern'),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
                onPressed: () {
                  if (anSelected.isEmpty && diagnoseC.text.trim().isEmpty) return;
                  final entry = <String, dynamic>{
                    'datum': datumC.text,
                    'patient': patientC.text.trim(),
                    'geb_datum': gebDatumC.text.trim(),
                    'adresse': adresseC.text.trim(),
                    'art': art,
                    'art_sub': art == 'kurativ' ? artSub : '',
                    'an': anSelected,
                    'fachrichtung': fachrichtungC.text.trim(),
                    'krankenkasse': krankenkasseC.text.trim(),
                    'versicherten_nr': versichertenNrC.text.trim(),
                    'kostentraeger_kennung': kostentraegerC.text.trim(),
                    'versicherungsstatus': versicherungsstatus,
                    'geschlecht': geschlecht,
                    'diagnose': diagnoseC.text.trim(),
                    'icd_code': icdCodeC.text.trim(),
                    'befunde': befundeC.text.trim(),
                    'auftrag': auftragC.text.trim(),
                    'ausfuehrung_text': ausfuehrungC.text.trim(),
                    'bsnr': bsnrC.text.trim(),
                    'lanr': lanrC.text.trim(),
                    'status': status,
                    'ausgestellt_von': () {
                        final name = arztData['arzt_name']?.toString() ?? '';
                        final praxis = arztData['praxis_name']?.toString() ?? '';
                        final bsnr = bsnrC.text.trim();
                        final lanr = lanrC.text.trim();
                        if (name.isNotEmpty && praxis.isNotEmpty) return '$name – $praxis (BSNR: $bsnr, LANR: $lanr)';
                        if (name.isNotEmpty) return '$name (BSNR: $bsnr, LANR: $lanr)';
                        if (praxis.isNotEmpty) return '$praxis (BSNR: $bsnr, LANR: $lanr)';
                        return arztTitle;
                      }(),
                  };
                  final list = List<dynamic>.from(ueberweisungen);
                  if (editIndex != null && editIndex < list.length) {
                    list[editIndex] = entry;
                  } else {
                    list.add(entry);
                  }
                  data['ueberweisungen'] = list;
                  Navigator.pop(dlgCtx);
                  saveAll();
                  setLocalState(() {});
                },
              ),
            ],
          ),
        ),
      );
    }

    // ── BEKANNTE PRAXEN (fachrichtung → Kontaktdaten) ──
    const praxisSuggestions = <String, Map<String, String>>{
      'Radiologie': {
        'name': 'RADIOLOGIE ZENTRUM NEU-ULM',
        'adresse': 'Meininger Allee 5, 89231 Neu-Ulm',
        'telefon': '(0731) 17607-0',
        'telefon2': 'Privatsprechstunde: (0731) 17607-89',
        'fax': '(0731) 17607-77',
        'email': 'praxis@radiologie-nu.de',
      },
    };

    void showDetailDialog(Map<String, dynamic> uData, int uIdx, StateSetter setTabState, StateSetter setLocalState) {
      final termin = uData['termin'] is Map
          ? Map<String, dynamic>.from(uData['termin'] as Map)
          : <String, dynamic>{};
      final anVal = uData['an']?.toString() ?? '';
      final suggestion = praxisSuggestions[anVal] ?? <String, String>{};

      final terminDatumC = TextEditingController(text: termin['datum']?.toString() ?? '');
      final terminUhrzeitC = TextEditingController(text: termin['uhrzeit']?.toString() ?? '');
      final praxisNameC = TextEditingController(text: termin['praxis_name']?.toString() ?? suggestion['name'] ?? '');
      final praxisAdresseC = TextEditingController(text: termin['praxis_adresse']?.toString() ?? suggestion['adresse'] ?? '');
      final praxisTelefonC = TextEditingController(text: termin['praxis_telefon']?.toString() ?? suggestion['telefon'] ?? '');
      final praxisFaxC = TextEditingController(text: termin['praxis_fax']?.toString() ?? suggestion['fax'] ?? '');
      final praxisEmailC = TextEditingController(text: termin['praxis_email']?.toString() ?? suggestion['email'] ?? '');
      final terminNotizenC = TextEditingController(text: termin['notizen']?.toString() ?? '');
      String terminStatus = termin['status']?.toString() ?? 'geplant';
      bool editingTermin = (termin['datum']?.toString() ?? '').isEmpty;

      // Auto-fetch portal_url from DB if not set but praxis is selected
      if ((termin['portal_url']?.toString() ?? '').isEmpty && praxisNameC.text.isNotEmpty) {
        widget.apiService.searchAerzte(search: praxisNameC.text).then((result) {
          final aerzte = result['aerzte'] as List? ?? [];
          for (final a in aerzte) {
            final pUrl = a['portal_url']?.toString() ?? '';
            if (pUrl.isNotEmpty) {
              termin['portal_url'] = pUrl;
              termin['portal_label'] = a['portal_label']?.toString() ?? 'Portal';
              break;
            }
          }
        });
      }

      Widget detailRow(IconData icon, String label, String value) {
        if (value.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(icon, size: 14, color: Colors.indigo.shade400),
            const SizedBox(width: 6),
            Text('$label ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontWeight: FontWeight.w600)),
            Expanded(child: Text(value, style: const TextStyle(fontSize: 12))),
          ]),
        );
      }

      // Verlauf data
      final verlauf = uData['verlauf'] is List
          ? List<Map<String, dynamic>>.from((uData['verlauf'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
          : <Map<String, dynamic>>[];

      showDialog(
        context: context,
        builder: (dlgCtx) => DefaultTabController(
          length: 4,
          child: StatefulBuilder(
            builder: (dlgCtx, setDlgState) {
              final artBase2 = {
                'kurativ': 'Kurativ', 'praeventiv': 'Präventiv', '116b': 'Gem. § 116b SGB V',
                'belegaerztlich': 'Belegärztlich', 'mitbehandlung': 'Mitbehandlung',
                'weiterbehandlung': 'Weiterbehandlung', 'konsil': 'Konsiliaruntersuchung',
                'auftragsleistung': 'Auftragsleistung', 'ausfuehrung': 'Auftragsleistung',
                'diagnostik': 'Mitbehandlung',
              };
              final aBase = artBase2[uData['art']] ?? uData['art']?.toString() ?? '';
              final aSub = uData['art_sub']?.toString() ?? '';
              final aSubLabel = aSub.isNotEmpty ? (artBase2[aSub] ?? aSub) : '';
              final aLabel = aSubLabel.isNotEmpty ? '$aBase – $aSubLabel' : aBase;

              return AlertDialog(
                contentPadding: EdgeInsets.zero,
                titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.swap_horiz, size: 18, color: Colors.indigo.shade700),
                      const SizedBox(width: 8),
                      Expanded(child: Text('Überweisung', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                      IconButton(
                        icon: const Icon(Icons.close, size: 18),
                        onPressed: () => Navigator.pop(dlgCtx),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ]),
                    const SizedBox(height: 4),
                    TabBar(
                      tabs: const [
                        Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                        Tab(icon: Icon(Icons.calendar_today, size: 16), text: 'Termin'),
                        Tab(icon: Icon(Icons.history, size: 16), text: 'Verlauf'),
                        Tab(icon: Icon(Icons.description, size: 16), text: 'Bericht'),
                      ],
                      labelStyle: const TextStyle(fontSize: 12),
                      indicatorColor: Colors.indigo.shade600,
                      labelColor: Colors.indigo.shade700,
                    ),
                  ],
                ),
                content: SizedBox(
                  width: 480,
                  height: 420,
                  child: TabBarView(
                    children: [
                      // ── TAB 1: DETAILS ──
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            FilledButton.icon(
                              icon: const Icon(Icons.edit, size: 14),
                              label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
                              onPressed: () {
                                Navigator.pop(dlgCtx);
                                showUeberweisungDialog(existing: Map<String, dynamic>.from(uData), editIndex: uIdx);
                              },
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: Icon(Icons.check_circle_outline, size: 14, color: uData['status'] == 'erledigt' ? Colors.orange.shade600 : Colors.green.shade600),
                              label: Text(uData['status'] == 'erledigt' ? 'Als offen markieren' : 'Als erledigt', style: TextStyle(fontSize: 12, color: uData['status'] == 'erledigt' ? Colors.orange.shade700 : Colors.green.shade700)),
                              style: OutlinedButton.styleFrom(side: BorderSide(color: uData['status'] == 'erledigt' ? Colors.orange.shade400 : Colors.green.shade400), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
                              onPressed: () {
                                final list = List<dynamic>.from(ueberweisungen);
                                final updated = Map<String, dynamic>.from(uData);
                                updated['status'] = uData['status'] == 'erledigt' ? 'offen' : 'erledigt';
                                list[uIdx] = updated;
                                data['ueberweisungen'] = list;
                                Navigator.pop(dlgCtx);
                                saveAll();
                                setLocalState(() {});
                                setTabState(() {});
                              },
                            ),
                          ]),
                          const SizedBox(height: 12),
                          detailRow(Icons.event_note, 'Datum:', uData['datum']?.toString() ?? ''),
                          detailRow(Icons.person, 'Patient:', '${uData['patient'] ?? ''}${(uData['geb_datum']?.toString() ?? '').isNotEmpty ? ', geb. ${uData['geb_datum']}' : ''}'),
                          detailRow(Icons.location_on, 'Adresse:', uData['adresse']?.toString() ?? ''),
                          detailRow(Icons.category, 'Art:', aLabel),
                          detailRow(Icons.local_hospital, 'Überwiesen an:', uData['an']?.toString() ?? ''),
                          detailRow(Icons.medical_services, 'Fachrichtung:', uData['fachrichtung']?.toString() ?? ''),
                          detailRow(Icons.health_and_safety, 'Krankenkasse:', uData['krankenkasse']?.toString() ?? ''),
                          detailRow(Icons.badge, 'Versicherten-Nr.:', uData['versicherten_nr']?.toString() ?? ''),
                          detailRow(Icons.tag, 'Versicherungsstatus:', uData['versicherungsstatus']?.toString() ?? ''),
                          detailRow(Icons.numbers, 'Kostenträger-IK:', uData['kostentraeger_kennung']?.toString() ?? ''),
                          detailRow(Icons.medical_information, 'Diagnose:', '${uData['diagnose'] ?? ''}${(uData['icd_code']?.toString() ?? '').isNotEmpty ? '  (${uData['icd_code']})' : ''}'),
                          detailRow(Icons.notes, 'Befunde:', uData['befunde']?.toString() ?? ''),
                          detailRow(Icons.assignment, 'Auftrag:', uData['auftrag']?.toString() ?? ''),
                          detailRow(Icons.playlist_add_check, 'Ausführung von:', uData['ausfuehrung_text']?.toString() ?? ''),
                          detailRow(Icons.numbers, 'BSNR:', uData['bsnr']?.toString() ?? ''),
                          detailRow(Icons.numbers, 'LANR:', uData['lanr']?.toString() ?? ''),
                          detailRow(Icons.person_outline, 'Ausgestellt von:', uData['ausgestellt_von']?.toString() ?? ''),
                        ]),
                      ),
                      // ── TAB 2: TERMINPLANUNG ──
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: editingTermin
                          // ── EDIT / NEU ──
                          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.search, size: 16),
                                label: const Text('Praxis aus Datenbank auswählen', style: TextStyle(fontSize: 12)),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.teal.shade400),
                                  foregroundColor: Colors.teal.shade700,
                                  padding: const EdgeInsets.symmetric(vertical: 8),
                                ),
                                onPressed: () {
                                  _showArztSucheDialog(context, anVal, (arzt) {
                                    setDlgState(() {
                                      praxisNameC.text = arzt['praxis_name']?.toString() ?? '';
                                      final str = arzt['strasse']?.toString() ?? '';
                                      final plz = arzt['plz_ort']?.toString() ?? '';
                                      praxisAdresseC.text = [str, plz].where((s) => s.isNotEmpty).join(', ');
                                      praxisTelefonC.text = arzt['telefon']?.toString() ?? '';
                                      praxisFaxC.text = arzt['fax']?.toString() ?? '';
                                      praxisEmailC.text = arzt['email']?.toString() ?? '';
                                      // Store portal info
                                      termin['portal_url'] = arzt['portal_url']?.toString() ?? '';
                                      termin['portal_label'] = arzt['portal_label']?.toString() ?? '';
                                    });
                                  });
                                },
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          if (praxisNameC.text.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(praxisNameC.text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                                if (praxisAdresseC.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(praxisAdresseC.text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                                const SizedBox(height: 4),
                                Wrap(spacing: 12, children: [
                                  if (praxisTelefonC.text.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.phone, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3), Text(praxisTelefonC.text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))]),
                                  if (praxisFaxC.text.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.fax, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3), Text('Fax: ${praxisFaxC.text}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))]),
                                  if (praxisEmailC.text.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.email, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3), Text(praxisEmailC.text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))]),
                                ]),
                              ]),
                            ),
                            // Portal button (e.g. Zugangsticket)
                            if ((termin['portal_url']?.toString() ?? '').isNotEmpty) ...[
                              const SizedBox(height: 8),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton.icon(
                                  onPressed: () {
                                    Navigator.push(context, MaterialPageRoute(
                                      builder: (_) => WebViewScreen(title: termin['portal_label']?.toString() ?? 'Portal', url: termin['portal_url'].toString()),
                                    ));
                                  },
                                  icon: Icon(Icons.open_in_browser, size: 16, color: Colors.deepPurple.shade700),
                                  label: Text(termin['portal_label']?.toString() ?? 'Portal offnen', style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700)),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: Colors.deepPurple.shade300),
                                    backgroundColor: Colors.deepPurple.shade50,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                          ],
                          Row(children: [
                            Expanded(
                              child: TextFormField(
                                controller: terminDatumC,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Termindatum',
                                  prefixIcon: const Icon(Icons.calendar_today, size: 16),
                                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                    final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(terminDatumC.text) ?? DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2099), locale: const Locale('de'));
                                    if (picked != null) setDlgState(() => terminDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                                  }),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextFormField(
                                controller: terminUhrzeitC,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Uhrzeit',
                                  prefixIcon: const Icon(Icons.access_time, size: 16),
                                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  suffixIcon: IconButton(icon: const Icon(Icons.access_time, size: 14), onPressed: () async {
                                    final t = await showTimePicker(context: dlgCtx, initialTime: TimeOfDay.now());
                                    if (t != null) {
                                      final h = t.hour.toString().padLeft(2, '0');
                                      final m = t.minute.toString().padLeft(2, '0');
                                      setDlgState(() => terminUhrzeitC.text = '$h:$m');
                                    }
                                  }),
                                ),
                              ),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          DropdownButtonFormField<String>(
                            isExpanded: true,
                            initialValue: terminStatus,
                            decoration: InputDecoration(labelText: 'Status', prefixIcon: const Icon(Icons.flag, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                            items: const [
                              DropdownMenuItem(value: 'geplant', child: Text('Geplant', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'bestaetigt', child: Text('Bestätigt', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'erledigt', child: Text('Erledigt', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'abgesagt', child: Text('Abgesagt', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (v) => setDlgState(() => terminStatus = v ?? 'geplant'),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: terminNotizenC,
                            maxLines: 3,
                            decoration: InputDecoration(labelText: 'Notizen zum Termin', prefixIcon: const Icon(Icons.notes, size: 16), alignLabelWithHint: true, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                          ),
                          const SizedBox(height: 14),
                          Row(children: [
                            if ((termin['datum']?.toString() ?? '').isNotEmpty) ...[
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.cancel, size: 16),
                                  label: const Text('Abbrechen'),
                                  style: OutlinedButton.styleFrom(foregroundColor: Colors.grey.shade700),
                                  onPressed: () => setDlgState(() => editingTermin = false),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            Expanded(
                              child: FilledButton.icon(
                              icon: const Icon(Icons.save, size: 16),
                              label: const Text('Termin speichern'),
                              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
                              onPressed: () async {
                                // 1. Speichere in Gesundheit-Daten (verschlüsselt)
                                final list = List<dynamic>.from(ueberweisungen);
                                final updated = Map<String, dynamic>.from(uData);
                                updated['termin'] = {
                                  'datum': terminDatumC.text,
                                  'uhrzeit': terminUhrzeitC.text,
                                  'praxis_name': praxisNameC.text,
                                  'praxis_adresse': praxisAdresseC.text,
                                  'praxis_telefon': praxisTelefonC.text,
                                  'praxis_fax': praxisFaxC.text,
                                  'praxis_email': praxisEmailC.text,
                                  'notizen': terminNotizenC.text.trim(),
                                  'status': terminStatus,
                                };
                                list[uIdx] = updated;
                                data['ueberweisungen'] = list;
                                saveAll();
                                setLocalState(() {});
                                setTabState(() {});

                                // 2. Eintrag in Terminverwaltung erstellen
                                if (terminDatumC.text.isNotEmpty) {
                                  try {
                                    final dateParts = terminDatumC.text.split('-');
                                    if (dateParts.length == 3) {
                                      final year = int.parse(dateParts[0]);
                                      final month = int.parse(dateParts[1]);
                                      final day = int.parse(dateParts[2]);
                                      int hour = 8, minute = 0;
                                      if (terminUhrzeitC.text.isNotEmpty) {
                                        final tp = terminUhrzeitC.text.split(':');
                                        if (tp.length == 2) { hour = int.tryParse(tp[0]) ?? 8; minute = int.tryParse(tp[1]) ?? 0; }
                                      }
                                      final terminDateTime = DateTime(year, month, day, hour, minute);
                                      final patientName = '${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''}'.trim();
                                      final praxisTitle = praxisNameC.text.isNotEmpty ? praxisNameC.text : (anVal.isNotEmpty ? anVal : 'Arzttermin');
                                      final title = '$praxisTitle – $patientName';
                                      final desc = [
                                        if (praxisAdresseC.text.isNotEmpty) praxisAdresseC.text,
                                        if (praxisTelefonC.text.isNotEmpty) 'Tel: ${praxisTelefonC.text}',
                                        if (terminNotizenC.text.trim().isNotEmpty) terminNotizenC.text.trim(),
                                        if ((uData['diagnose']?.toString() ?? '').isNotEmpty) 'Diagnose: ${uData['diagnose']}',
                                      ].join('\n');
                                      widget.terminService.setToken(widget.apiService.token ?? '');
                                      await widget.terminService.createTermin(
                                        title: title,
                                        category: 'sonstiges',
                                        description: desc,
                                        terminDate: terminDateTime,
                                        durationMinutes: 60,
                                        location: praxisAdresseC.text.isNotEmpty ? praxisAdresseC.text : anVal,
                                        participantIds: [widget.user.id],
                                      );
                                    }
                                  } catch (e) {
                                    debugPrint('[TERMIN-CREATE] Error: $e');
                                  }
                                }

                                if (dlgCtx.mounted) {
                                  Navigator.pop(dlgCtx);
                                  ScaffoldMessenger.of(dlgCtx).showSnackBar(SnackBar(
                                    content: const Text('Termin gespeichert & in Terminverwaltung eingetragen'),
                                    backgroundColor: Colors.teal.shade600,
                                    duration: const Duration(seconds: 3),
                                  ));
                                }
                              },
                            ),
                          ),
                        ]),
                        ])
                        // ── VIEW MODE ──
                        : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                              Chip(
                                label: Text(
                                  terminStatus == 'bestaetigt' ? 'Bestätigt' :
                                  terminStatus == 'erledigt' ? 'Erledigt' :
                                  terminStatus == 'abgesagt' ? 'Abgesagt' : 'Geplant',
                                  style: const TextStyle(fontSize: 12, color: Colors.white),
                                ),
                                backgroundColor: terminStatus == 'bestaetigt' ? Colors.green.shade600 :
                                  terminStatus == 'erledigt' ? Colors.blue.shade600 :
                                  terminStatus == 'abgesagt' ? Colors.red.shade600 : Colors.orange.shade600,
                                padding: EdgeInsets.zero,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.edit, size: 14),
                                label: const Text('Bearbeiten', style: TextStyle(fontSize: 12)),
                                onPressed: () => setDlgState(() => editingTermin = true),
                              ),
                            ]),
                            const SizedBox(height: 8),
                            if (praxisNameC.text.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                margin: const EdgeInsets.only(bottom: 12),
                                decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text(praxisNameC.text, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                                  if (praxisAdresseC.text.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 3), child: Text(praxisAdresseC.text, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                                  const SizedBox(height: 6),
                                  Wrap(spacing: 12, children: [
                                    if (praxisTelefonC.text.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.phone, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3), Text(praxisTelefonC.text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))]),
                                    if (praxisFaxC.text.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.fax, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3), Text('Fax: ${praxisFaxC.text}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))]),
                                    if (praxisEmailC.text.isNotEmpty) Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.email, size: 12, color: Colors.grey.shade500), const SizedBox(width: 3), Text(praxisEmailC.text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))]),
                                  ]),
                                  // Portal button in read-only
                                  if ((termin['portal_url']?.toString() ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: () {
                                          Navigator.push(context, MaterialPageRoute(
                                            builder: (_) => WebViewScreen(title: termin['portal_label']?.toString() ?? 'Portal', url: termin['portal_url'].toString()),
                                          ));
                                        },
                                        icon: Icon(Icons.open_in_browser, size: 16, color: Colors.deepPurple.shade700),
                                        label: Text(termin['portal_label']?.toString() ?? 'Portal offnen', style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700)),
                                        style: OutlinedButton.styleFrom(
                                          side: BorderSide(color: Colors.deepPurple.shade300),
                                          backgroundColor: Colors.deepPurple.shade50,
                                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                        ),
                                      ),
                                    ),
                                  ],
                                ]),
                              ),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                              child: Row(children: [
                                Icon(Icons.calendar_today, size: 16, color: Colors.indigo.shade400),
                                const SizedBox(width: 8),
                                Text(
                                  terminDatumC.text.isNotEmpty
                                    ? DateFormat('dd.MM.yyyy').format(DateTime.tryParse(terminDatumC.text) ?? DateTime.now())
                                    : '–',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                ),
                                if (terminUhrzeitC.text.isNotEmpty) ...[
                                  const SizedBox(width: 16),
                                  Icon(Icons.access_time, size: 16, color: Colors.indigo.shade400),
                                  const SizedBox(width: 6),
                                  Text(terminUhrzeitC.text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                ],
                              ]),
                            ),
                            if (terminNotizenC.text.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Icon(Icons.notes, size: 14, color: Colors.amber.shade700),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(terminNotizenC.text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
                                ]),
                              ),
                            ],
                          ]),
                      ),
                      // ── TAB 3: VERLAUF ──
                      StatefulBuilder(
                        builder: (vCtx, setVerlaufState) {
                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Add entry button
                                FilledButton.icon(
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Eintrag hinzufügen', style: TextStyle(fontSize: 12)),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero),
                                  onPressed: () {
                                    String aktivitaet = 'wahrgenommen';
                                    final notizC = TextEditingController();
                                    final datumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
                                    showDialog(
                                      context: vCtx,
                                      builder: (addCtx) => StatefulBuilder(
                                        builder: (addCtx, setAddState) => AlertDialog(
                                          title: const Text('Verlauf-Eintrag', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                          content: SizedBox(
                                            width: 360,
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                TextFormField(
                                                  controller: datumC,
                                                  readOnly: true,
                                                  decoration: InputDecoration(
                                                    labelText: 'Datum',
                                                    prefixIcon: const Icon(Icons.calendar_today, size: 16),
                                                    isDense: true,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    suffixIcon: IconButton(
                                                      icon: const Icon(Icons.edit_calendar, size: 14),
                                                      onPressed: () async {
                                                        final picked = await showDatePicker(context: addCtx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2099), locale: const Locale('de'));
                                                        if (picked != null) datumC.text = DateFormat('dd.MM.yyyy').format(picked);
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 12),
                                                DropdownButtonFormField<String>(
                                                  initialValue: aktivitaet,
                                                  isExpanded: true,
                                                  decoration: InputDecoration(labelText: 'Aktivität', prefixIcon: const Icon(Icons.flag, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                                  items: const [
                                                    DropdownMenuItem(value: 'wahrgenommen', child: Text('Termin wahrgenommen', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'nicht_erschienen', child: Text('Nicht erschienen', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'abgesagt_patient', child: Text('Vom Patienten abgesagt', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'abgesagt_praxis', child: Text('Von Praxis abgesagt', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'verschoben', child: Text('Verschoben', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'befund_erhalten', child: Text('Befund erhalten', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'nachtermin', child: Text('Nachtermin vereinbart', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 13))),
                                                  ],
                                                  onChanged: (v) => setAddState(() => aktivitaet = v ?? 'wahrgenommen'),
                                                ),
                                                const SizedBox(height: 12),
                                                TextFormField(
                                                  controller: notizC,
                                                  maxLines: 3,
                                                  decoration: InputDecoration(labelText: 'Notiz', prefixIcon: const Icon(Icons.notes, size: 16), alignLabelWithHint: true, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                                ),
                                              ],
                                            ),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(addCtx), child: const Text('Abbrechen')),
                                            FilledButton(
                                              onPressed: () {
                                                verlauf.insert(0, {
                                                  'datum': datumC.text,
                                                  'aktivitaet': aktivitaet,
                                                  'notiz': notizC.text.trim(),
                                                  'erstellt_am': DateTime.now().toIso8601String(),
                                                });
                                                final list = List<dynamic>.from(ueberweisungen);
                                                final updated = Map<String, dynamic>.from(uData);
                                                updated['verlauf'] = verlauf;
                                                list[uIdx] = updated;
                                                data['ueberweisungen'] = list;
                                                saveAll();
                                                setLocalState(() {});
                                                setTabState(() {});
                                                setVerlaufState(() {});
                                                Navigator.pop(addCtx);
                                              },
                                              child: const Text('Speichern'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                if (verlauf.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                                    child: Column(children: [
                                      Icon(Icons.history, size: 32, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text('Noch keine Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                    ]),
                                  )
                                else
                                  ...verlauf.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final v = entry.value;
                                    final akt = v['aktivitaet']?.toString() ?? '';
                                    final aktLabels = {
                                      'wahrgenommen': ('Termin wahrgenommen', Icons.check_circle, Colors.green.shade600),
                                      'nicht_erschienen': ('Nicht erschienen', Icons.cancel, Colors.red.shade600),
                                      'abgesagt_patient': ('Vom Patienten abgesagt', Icons.person_off, Colors.orange.shade700),
                                      'abgesagt_praxis': ('Von Praxis abgesagt', Icons.business, Colors.red.shade700),
                                      'verschoben': ('Verschoben', Icons.update, Colors.blue.shade600),
                                      'befund_erhalten': ('Befund erhalten', Icons.description, Colors.teal.shade600),
                                      'nachtermin': ('Nachtermin vereinbart', Icons.event_repeat, Colors.purple.shade600),
                                      'sonstiges': ('Sonstiges', Icons.info_outline, Colors.grey.shade600),
                                    };
                                    final aktInfo = aktLabels[akt] ?? ('Unbekannt', Icons.help_outline, Colors.grey.shade600);
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          // Timeline line
                                          Column(children: [
                                            Container(
                                              width: 28, height: 28,
                                              decoration: BoxDecoration(color: aktInfo.$3.withValues(alpha: 0.15), shape: BoxShape.circle),
                                              child: Icon(aktInfo.$2, size: 14, color: aktInfo.$3),
                                            ),
                                            if (idx < verlauf.length - 1)
                                              Container(width: 2, height: 30, color: Colors.grey.shade300),
                                          ]),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Container(
                                              padding: const EdgeInsets.all(10),
                                              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                Row(children: [
                                                  Expanded(
                                                    child: Text(aktInfo.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: aktInfo.$3)),
                                                  ),
                                                  Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                                  const SizedBox(width: 4),
                                                  InkWell(
                                                    onTap: () {
                                                      verlauf.removeAt(idx);
                                                      final list = List<dynamic>.from(ueberweisungen);
                                                      final updated = Map<String, dynamic>.from(uData);
                                                      updated['verlauf'] = verlauf;
                                                      list[uIdx] = updated;
                                                      data['ueberweisungen'] = list;
                                                      saveAll();
                                                      setLocalState(() {});
                                                      setTabState(() {});
                                                      setVerlaufState(() {});
                                                    },
                                                    child: Icon(Icons.close, size: 14, color: Colors.grey.shade400),
                                                  ),
                                                ]),
                                                if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
                                                  const SizedBox(height: 4),
                                                  Text(v['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                                ],
                                              ]),
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  }),
                              ],
                            ),
                          );
                        },
                      ),

                      // ── TAB 4: BERICHT ──
                      StatefulBuilder(
                        builder: (bCtx, setBerichtState) {
                          final berichte = uData['berichte'] is List
                              ? List<Map<String, dynamic>>.from((uData['berichte'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                              : <Map<String, dynamic>>[];

                          return SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FilledButton.icon(
                                  icon: const Icon(Icons.add, size: 16),
                                  label: const Text('Bericht hinzufugen', style: TextStyle(fontSize: 12)),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero),
                                  onPressed: () {
                                    String berichtTyp = 'befund';
                                    final berichtDatumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
                                    final berichtTitelC = TextEditingController();
                                    final berichtInhaltC = TextEditingController();
                                    String berichtStatus = 'erhalten';
                                    final ticketCode1C = TextEditingController();
                                    final ticketCode2C = TextEditingController();
                                    final ticketCode3C = TextEditingController();
                                    final gueltigBisC = TextEditingController();
                                    Map<String, dynamic>? selectedPraxis;

                                    showDialog(
                                      context: bCtx,
                                      builder: (addCtx) => StatefulBuilder(
                                        builder: (addCtx, setAddState) => AlertDialog(
                                          title: const Text('Neuer Bericht', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                          content: SizedBox(
                                            width: 420,
                                            child: SingleChildScrollView(child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                DropdownButtonFormField<String>(
                                                  initialValue: berichtTyp,
                                                  isExpanded: true,
                                                  decoration: InputDecoration(labelText: 'Art des Berichts', prefixIcon: const Icon(Icons.description, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                                  items: const [
                                                    DropdownMenuItem(value: 'befund', child: Text('Befund', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'arztbrief', child: Text('Arztbrief', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'laborbericht', child: Text('Laborbericht', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'roentgen', child: Text('Rontgenbefund', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'mrt', child: Text('MRT-Befund', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'ct', child: Text('CT-Befund', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'op_bericht', child: Text('OP-Bericht', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'therapiebericht', child: Text('Therapiebericht', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'zervixkarzinom', child: Text('Zervixkarzinom-Screening (HPV/Pap)', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 13))),
                                                  ],
                                                  onChanged: (v) => setAddState(() => berichtTyp = v ?? 'befund'),
                                                ),
                                                const SizedBox(height: 10),
                                                TextFormField(
                                                  controller: berichtDatumC,
                                                  readOnly: true,
                                                  decoration: InputDecoration(
                                                    labelText: 'Datum',
                                                    prefixIcon: const Icon(Icons.calendar_today, size: 16),
                                                    isDense: true,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    suffixIcon: IconButton(
                                                      icon: const Icon(Icons.edit_calendar, size: 14),
                                                      onPressed: () async {
                                                        final picked = await showDatePicker(context: addCtx, initialDate: DateTime.now(), firstDate: DateTime(2024), lastDate: DateTime(2099), locale: const Locale('de'));
                                                        if (picked != null) berichtDatumC.text = DateFormat('dd.MM.yyyy').format(picked);
                                                      },
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(height: 10),
                                                TextFormField(controller: berichtTitelC, decoration: InputDecoration(labelText: 'Titel / Betreff', prefixIcon: const Icon(Icons.title, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                                const SizedBox(height: 10),
                                                TextFormField(controller: berichtInhaltC, maxLines: 3, decoration: InputDecoration(labelText: 'Inhalt / Zusammenfassung', prefixIcon: const Icon(Icons.notes, size: 16), alignLabelWithHint: true, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                                const SizedBox(height: 10),
                                                DropdownButtonFormField<String>(
                                                  initialValue: berichtStatus,
                                                  isExpanded: true,
                                                  decoration: InputDecoration(labelText: 'Status', prefixIcon: const Icon(Icons.flag, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                                  items: const [
                                                    DropdownMenuItem(value: 'erhalten', child: Text('Erhalten', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'ausgewertet', child: Text('Ausgewertet', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'weitergeleitet', child: Text('Weitergeleitet', style: TextStyle(fontSize: 13))),
                                                    DropdownMenuItem(value: 'ausstehend', child: Text('Ausstehend', style: TextStyle(fontSize: 13))),
                                                  ],
                                                  onChanged: (v) => setAddState(() => berichtStatus = v ?? 'erhalten'),
                                                ),
                                                const SizedBox(height: 12),
                                                // Praxis auswählen (for portal link)
                                                Text('Praxis / Quelle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                                const SizedBox(height: 6),
                                                OutlinedButton.icon(
                                                  icon: Icon(Icons.search, size: 16, color: Colors.teal.shade700),
                                                  label: Text(selectedPraxis != null ? (selectedPraxis!['praxis_name']?.toString() ?? 'Praxis') : 'Praxis auswahlen', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
                                                  style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                                                  onPressed: () {
                                                    _showArztSucheDialog(context, '', (arzt) {
                                                      setAddState(() => selectedPraxis = Map<String, dynamic>.from(arzt));
                                                    });
                                                  },
                                                ),
                                                if (selectedPraxis != null) ...[
                                                  const SizedBox(height: 8),
                                                  Container(
                                                    width: double.infinity,
                                                    padding: const EdgeInsets.all(10),
                                                    decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
                                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                                      Text(selectedPraxis!['praxis_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                                                      if ((selectedPraxis!['strasse']?.toString() ?? '').isNotEmpty)
                                                        Text('${selectedPraxis!['strasse']}, ${selectedPraxis!['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                                      if ((selectedPraxis!['telefon']?.toString() ?? '').isNotEmpty)
                                                        Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [Icon(Icons.phone, size: 12, color: Colors.grey.shade500), const SizedBox(width: 4), Text(selectedPraxis!['telefon'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600))])),
                                                    ]),
                                                  ),
                                                  // Portal link if praxis has one
                                                  if ((selectedPraxis!['portal_url']?.toString() ?? '').isNotEmpty) ...[
                                                    const SizedBox(height: 8),
                                                    SizedBox(
                                                      width: double.infinity,
                                                      child: OutlinedButton.icon(
                                                        onPressed: () {
                                                          Navigator.push(context, MaterialPageRoute(
                                                            builder: (_) => WebViewScreen(title: selectedPraxis!['portal_label']?.toString() ?? 'Portal', url: selectedPraxis!['portal_url'].toString()),
                                                          ));
                                                        },
                                                        icon: Icon(Icons.open_in_browser, size: 16, color: Colors.deepPurple.shade700),
                                                        label: Text(selectedPraxis!['portal_label']?.toString() ?? 'Portal offnen', style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700)),
                                                        style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.deepPurple.shade300), backgroundColor: Colors.deepPurple.shade50, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
                                                      ),
                                                    ),
                                                  ],
                                                ],
                                                const SizedBox(height: 12),
                                                // Ticket-Code (3 x 4 characters)
                                                Text('Ticket-Code', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                                const SizedBox(height: 6),
                                                Row(children: [
                                                  Expanded(child: TextFormField(controller: ticketCode1C, maxLength: 4, textCapitalization: TextCapitalization.characters, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 3), decoration: InputDecoration(counterText: '', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
                                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(' - ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade400))),
                                                  Expanded(child: TextFormField(controller: ticketCode2C, maxLength: 4, textCapitalization: TextCapitalization.characters, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 3), decoration: InputDecoration(counterText: '', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
                                                  Padding(padding: const EdgeInsets.symmetric(horizontal: 6), child: Text(' - ', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey.shade400))),
                                                  Expanded(child: TextFormField(controller: ticketCode3C, maxLength: 4, textCapitalization: TextCapitalization.characters, textAlign: TextAlign.center, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 3), decoration: InputDecoration(counterText: '', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10)))),
                                                ]),
                                                const SizedBox(height: 10),
                                                // Geburtsdatum des Mitglieds
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                                                  child: Row(children: [
                                                    Icon(Icons.cake, size: 16, color: Colors.blue.shade600),
                                                    const SizedBox(width: 8),
                                                    Text('Geburtsdatum: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                                    Text(
                                                      () {
                                                        final geb = widget.user.geburtsdatum ?? '';
                                                        if (geb.contains('-') && geb.length == 10) {
                                                          final parts = geb.split('-');
                                                          return '${parts[2]}.${parts[1]}.${parts[0]}';
                                                        }
                                                        return geb.isNotEmpty ? geb : 'Nicht hinterlegt';
                                                      }(),
                                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800),
                                                    ),
                                                  ]),
                                                ),
                                                const SizedBox(height: 10),
                                                // Gültig bis
                                                TextFormField(
                                                  controller: gueltigBisC,
                                                  readOnly: true,
                                                  decoration: InputDecoration(
                                                    labelText: 'Gultig bis',
                                                    prefixIcon: const Icon(Icons.event_available, size: 16),
                                                    isDense: true,
                                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                    suffixIcon: IconButton(
                                                      icon: const Icon(Icons.edit_calendar, size: 14),
                                                      onPressed: () async {
                                                        final picked = await showDatePicker(context: addCtx, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime.now(), lastDate: DateTime(2099), locale: const Locale('de'));
                                                        if (picked != null) gueltigBisC.text = DateFormat('dd.MM.yyyy').format(picked);
                                                      },
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            )),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(addCtx), child: const Text('Abbrechen')),
                                            FilledButton(
                                              onPressed: () {
                                                final ticketCode = [ticketCode1C.text.trim(), ticketCode2C.text.trim(), ticketCode3C.text.trim()].where((s) => s.isNotEmpty).join('-');
                                                berichte.insert(0, {
                                                  'bericht_id': 'b_${DateTime.now().millisecondsSinceEpoch}',
                                                  'typ': berichtTyp,
                                                  'datum': berichtDatumC.text,
                                                  'titel': berichtTitelC.text.trim(),
                                                  'inhalt': berichtInhaltC.text.trim(),
                                                  'status': berichtStatus,
                                                  'ticket_code': ticketCode,
                                                  'gueltig_bis': gueltigBisC.text.trim(),
                                                  'praxis_name': selectedPraxis?['praxis_name']?.toString() ?? '',
                                                  'portal_url': selectedPraxis?['portal_url']?.toString() ?? '',
                                                  'portal_label': selectedPraxis?['portal_label']?.toString() ?? '',
                                                  'erstellt_am': DateTime.now().toIso8601String(),
                                                });
                                                final list = List<dynamic>.from(ueberweisungen);
                                                final updated = Map<String, dynamic>.from(uData);
                                                updated['berichte'] = berichte;
                                                list[uIdx] = updated;
                                                data['ueberweisungen'] = list;
                                                saveAll();
                                                setLocalState(() {});
                                                setTabState(() {});
                                                setBerichtState(() {});
                                                Navigator.pop(addCtx);
                                              },
                                              child: const Text('Speichern'),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                const SizedBox(height: 12),
                                if (berichte.isEmpty)
                                  Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                                    child: Column(children: [
                                      Icon(Icons.description, size: 32, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text('Noch keine Berichte', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                    ]),
                                  )
                                else
                                  ...berichte.asMap().entries.map((entry) {
                                    final idx = entry.key;
                                    final b = entry.value;
                                    final typLabels = {
                                      'befund': ('Befund', Icons.biotech, Colors.teal),
                                      'arztbrief': ('Arztbrief', Icons.mail, Colors.blue),
                                      'laborbericht': ('Laborbericht', Icons.science, Colors.purple),
                                      'roentgen': ('Rontgen', Icons.image, Colors.orange),
                                      'mrt': ('MRT', Icons.image_search, Colors.indigo),
                                      'ct': ('CT', Icons.image_search, Colors.brown),
                                      'op_bericht': ('OP-Bericht', Icons.local_hospital, Colors.red),
                                      'therapiebericht': ('Therapiebericht', Icons.healing, Colors.green),
                                      'sonstiges': ('Sonstiges', Icons.info, Colors.grey),
                                    };
                                    final bInfo = typLabels[b['typ']] ?? ('Bericht', Icons.description, Colors.grey);
                                    final statusColors = {'erhalten': Colors.green, 'ausgewertet': Colors.blue, 'weitergeleitet': Colors.purple, 'ausstehend': Colors.orange};
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: bInfo.$3.shade50,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: bInfo.$3.shade200),
                                      ),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Row(children: [
                                          Icon(bInfo.$2, size: 16, color: bInfo.$3.shade700),
                                          const SizedBox(width: 6),
                                          Text(bInfo.$1, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: bInfo.$3.shade700)),
                                          const SizedBox(width: 8),
                                          PopupMenuButton<String>(
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 0, minHeight: 0),
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: (statusColors[b['status']] ?? Colors.grey).shade100, borderRadius: BorderRadius.circular(4)),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                Text(b['status']?.toString() ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: (statusColors[b['status']] ?? Colors.grey).shade700)),
                                                Icon(Icons.arrow_drop_down, size: 14, color: (statusColors[b['status']] ?? Colors.grey).shade700),
                                              ]),
                                            ),
                                            itemBuilder: (_) => [
                                              for (final s in ['erhalten', 'ausgewertet', 'weitergeleitet', 'ausstehend'])
                                                PopupMenuItem(value: s, height: 32, child: Row(children: [
                                                  Icon(Icons.circle, size: 10, color: (statusColors[s] ?? Colors.grey).shade600),
                                                  const SizedBox(width: 6),
                                                  Text(s[0].toUpperCase() + s.substring(1), style: const TextStyle(fontSize: 12)),
                                                ])),
                                            ],
                                            onSelected: (newStatus) {
                                              b['status'] = newStatus;
                                              final list = List<dynamic>.from(ueberweisungen);
                                              final updated = Map<String, dynamic>.from(uData);
                                              updated['berichte'] = berichte;
                                              list[uIdx] = updated;
                                              data['ueberweisungen'] = list;
                                              saveAll();
                                              setLocalState(() {});
                                              setTabState(() {});
                                              setBerichtState(() {});
                                            },
                                          ),
                                          const Spacer(),
                                          Text(b['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                          const SizedBox(width: 4),
                                          IconButton(
                                            icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                                            tooltip: 'Bericht loschen',
                                            padding: EdgeInsets.zero,
                                            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                            onPressed: () {
                                              showDialog(context: bCtx, builder: (dc) => AlertDialog(
                                                title: const Text('Bericht loschen?', style: TextStyle(fontSize: 14)),
                                                content: Text('„${b['titel'] ?? b['typ'] ?? 'Bericht'}" wirklich loschen?', style: const TextStyle(fontSize: 12)),
                                                actions: [
                                                  TextButton(onPressed: () => Navigator.pop(dc), child: const Text('Abbrechen')),
                                                  FilledButton(
                                                    style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                                    onPressed: () {
                                                      Navigator.pop(dc);
                                                      berichte.removeAt(idx);
                                                      final list = List<dynamic>.from(ueberweisungen);
                                                      final updated = Map<String, dynamic>.from(uData);
                                                      updated['berichte'] = berichte;
                                                      list[uIdx] = updated;
                                                      data['ueberweisungen'] = list;
                                                      saveAll();
                                                      setLocalState(() {});
                                                      setTabState(() {});
                                                      setBerichtState(() {});
                                                    },
                                                    child: const Text('Loschen'),
                                                  ),
                                                ],
                                              ));
                                            },
                                          ),
                                        ]),
                                        if ((b['titel']?.toString() ?? '').isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(b['titel'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                                        ],
                                        if ((b['inhalt']?.toString() ?? '').isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(b['inhalt'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                        ],
                                        // Portal link per Bericht (above code)
                                        if ((b['portal_url']?.toString() ?? '').isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () {
                                                Navigator.push(context, MaterialPageRoute(
                                                  builder: (_) => WebViewScreen(title: b['portal_label']?.toString() ?? 'Portal', url: b['portal_url'].toString()),
                                                ));
                                              },
                                              icon: Icon(Icons.open_in_browser, size: 14, color: Colors.deepPurple.shade700),
                                              label: Text(b['portal_label']?.toString() ?? 'Portal offnen', style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade700)),
                                              style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.deepPurple.shade200), backgroundColor: Colors.deepPurple.shade50, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                            ),
                                          ),
                                        ],
                                        // Ticket-Code
                                        if ((b['ticket_code']?.toString() ?? '').isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.indigo.shade200)),
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Row(children: [
                                                Icon(Icons.vpn_key, size: 14, color: Colors.indigo.shade600),
                                                const SizedBox(width: 6),
                                                Text('Ticket-Code: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                                Text(b['ticket_code'].toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 2, color: Colors.indigo.shade800)),
                                                if ((b['gueltig_bis']?.toString() ?? '').isNotEmpty) ...[
                                                  const Spacer(),
                                                  Text('bis ${b['gueltig_bis']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                                ],
                                              ]),
                                              const SizedBox(height: 4),
                                              // Geburtsdatum
                                              Row(children: [
                                                Icon(Icons.cake, size: 13, color: Colors.blue.shade500),
                                                const SizedBox(width: 6),
                                                Text('Geburtsdatum: ', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                                Text(
                                                  () {
                                                    final geb = widget.user.geburtsdatum ?? '';
                                                    if (geb.contains('-') && geb.length == 10) {
                                                      final parts = geb.split('-');
                                                      return '${parts[2]}.${parts[1]}.${parts[0]}';
                                                    }
                                                    return geb.isNotEmpty ? geb : '–';
                                                  }(),
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                                                ),
                                              ]),
                                            ]),
                                          ),
                                        ],
                                        // ── Dokument upload per Bericht ──
                                        const SizedBox(height: 8),
                                        _buildBerichtDokumente(type, b['bericht_id']?.toString() ?? 'b_$idx', setBerichtState),
                                      ]),
                                    );
                                  }),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final artLabels = {
      'kurativ': 'Kurativ',
      'praeventiv': 'Präventiv',
      '116b': 'Gem. § 116b SGB V',
      'belegaerztlich': 'Belegärztlich',
      'mitbehandlung': 'Mitbehandlung',
      'weiterbehandlung': 'Weiterbehandlung',
      'konsil': 'Konsiliaruntersuchung',
      'auftragsleistung': 'Auftragsleistung',
      'ausfuehrung': 'Auftragsleistung',        // backward compat
      'diagnostik': 'Mitbehandlung',            // backward compat
    };

    return StatefulBuilder(
      builder: (context, setTabState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info banner (Muster 6)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Überweisungsschein (Muster 6) – ausgestellt von $arztTitle an einen anderen Arzt oder eine Fachklinik.',
                        style: TextStyle(fontSize: 11, color: Colors.indigo.shade900, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              // Header + Add button
              Row(
                children: [
                  Icon(Icons.swap_horiz, size: 16, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Überweisungen (${ueberweisungen.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Hinzufügen', style: TextStyle(fontSize: 12)),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.indigo.shade600,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                    ),
                    onPressed: () async {
                      Map<String, dynamic>? kkData;
                      try {
                        final res = await widget.apiService.getBehoerdeData(widget.user.id, 'krankenkasse');
                        if (res['data'] != null) kkData = Map<String, dynamic>.from(res['data']);
                      } catch (_) {}
                      // Fetch fresh arzt data to get latest LANR/BSNR
                      final arztId = data['arzt_id']?.toString();
                      if (arztId != null && arztId.isNotEmpty) {
                        try {
                          final arztRes = await widget.apiService.manageArzt({'action': 'search', 'search': ''});
                          if (arztRes['success'] == true && arztRes['data'] is List) {
                            Map<String, dynamic>? found;
                            for (final a in arztRes['data'] as List) {
                              if (a['id']?.toString() == arztId) {
                                found = Map<String, dynamic>.from(a as Map);
                                break;
                              }
                            }
                            if (found != null) {
                              data['selected_arzt'] ??= {};
                              (data['selected_arzt'] as Map)['lanr'] = found['lanr'];
                              (data['selected_arzt'] as Map)['bsnr'] = found['bsnr'];
                              (data['selected_arzt'] as Map)['arzt_name'] = found['arzt_name'];
                              (data['selected_arzt'] as Map)['praxis_name'] = found['praxis_name'];
                            }
                          }
                        } catch (_) {}
                      }
                      if (context.mounted) showUeberweisungDialog(kkData: kkData);
                      setTabState(() {});
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (ueberweisungen.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.swap_horiz, size: 40, color: Colors.grey.shade300),
                      const SizedBox(height: 8),
                      Text('Keine Überweisungen vorhanden', style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                    ],
                  ),
                )
              else
                ...ueberweisungen.asMap().entries.map((e) {
                  final idx = e.key;
                  final u = e.value as Map<String, dynamic>;
                  final istErledigt = u['status'] == 'erledigt';
                  final artBase = artLabels[u['art']] ?? u['art']?.toString() ?? '';
                  final artSubVal = u['art_sub']?.toString() ?? '';
                  final artSubLabel = artSubVal.isNotEmpty ? (artLabels[artSubVal] ?? artSubVal) : '';
                  final artLabel = artSubLabel.isNotEmpty ? '$artBase – $artSubLabel' : artBase;
                  final datum = u['datum']?.toString() ?? '';
                  String datumFormatted = datum;
                  try {
                    if (datum.isNotEmpty) datumFormatted = DateFormat('dd.MM.yyyy').format(DateTime.parse(datum));
                  } catch (_) {}

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(color: istErledigt ? Colors.green.shade200 : Colors.indigo.shade200),
                    ),
                    child: InkWell(
                      onTap: () => showDetailDialog(Map<String, dynamic>.from(u), idx, setTabState, setLocalState),
                      borderRadius: BorderRadius.circular(10),
                      child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: istErledigt ? Colors.green.shade100 : Colors.indigo.shade100,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(artLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: istErledigt ? Colors.green.shade800 : Colors.indigo.shade800)),
                              ),
                              const SizedBox(width: 8),
                              if (datum.isNotEmpty)
                                Text(datumFormatted, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: istErledigt ? Colors.green.shade50 : Colors.orange.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: istErledigt ? Colors.green.shade300 : Colors.orange.shade300),
                                ),
                                child: Text(istErledigt ? 'Erledigt' : 'Offen', style: TextStyle(fontSize: 10, color: istErledigt ? Colors.green.shade700 : Colors.orange.shade700)),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: Icon(Icons.edit, size: 16, color: Colors.indigo.shade400),
                                onPressed: () {
                                  showUeberweisungDialog(existing: Map<String, dynamic>.from(u), editIndex: idx);
                                  setTabState(() {});
                                },
                                tooltip: 'Bearbeiten',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                              IconButton(
                                icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                                onPressed: () {
                                  final list = List<dynamic>.from(ueberweisungen);
                                  list.removeAt(idx);
                                  data['ueberweisungen'] = list;
                                  saveAll();
                                  setLocalState(() {});
                                  setTabState(() {});
                                },
                                tooltip: 'Löschen',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              ),
                            ],
                          ),
                          if ((u['patient']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Row(children: [
                              Icon(Icons.person_outline, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('Patient: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(
                                '${u['patient']}${(u['geb_datum']?.toString() ?? '').isNotEmpty ? ', geb. ${u['geb_datum']}' : ''}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              )),
                            ]),
                          ],
                          if ((u['adresse']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.location_on, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Expanded(child: Text(
                                u['adresse'].toString(),
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                              )),
                            ]),
                          ],
                          if ((u['krankenkasse']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.local_hospital, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('KK: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(
                                '${u['krankenkasse']}${(u['versicherungsstatus']?.toString() ?? '').isNotEmpty ? '  •  ${u['versicherungsstatus']}' : ''}',
                                style: const TextStyle(fontSize: 12),
                              )),
                            ]),
                          ],
                          if ((u['an']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.person, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('An: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(u['an'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                            ]),
                          ],
                          if ((u['fachrichtung']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.medical_services, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('Fachrichtung: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(u['fachrichtung'].toString(), style: const TextStyle(fontSize: 12))),
                            ]),
                          ],
                          if ((u['diagnose']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.medical_information, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('Diagnose: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(u['diagnose'].toString(), style: const TextStyle(fontSize: 12))),
                            ]),
                          ],
                          if ((u['icd_code']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(children: [
                              Icon(Icons.code, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('ICD: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Text(u['icd_code'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ]),
                          ],
                          if ((u['befunde']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.notes, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('Befunde: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(u['befunde'].toString(), style: const TextStyle(fontSize: 12))),
                            ]),
                          ],
                          if ((u['auftrag']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.assignment, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('Auftrag: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(u['auftrag'].toString(), style: const TextStyle(fontSize: 12))),
                            ]),
                          ],
                          if ((u['ausfuehrung_text']?.toString() ?? '').isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.playlist_add_check, size: 13, color: Colors.grey.shade500),
                              const SizedBox(width: 4),
                              Text('Ausführung von: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                              Expanded(child: Text(u['ausfuehrung_text'].toString(), style: const TextStyle(fontSize: 12))),
                            ]),
                          ],
                        ],
                      ),
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

  // ========== ARZT TERMINE TAB (DB-based) ==========

  final Map<String, List<Map<String, dynamic>>> _arztTermine = {};
  final Map<String, bool> _arztTermineLoading = {};

  Future<void> _loadArztTermine(String type) async {
    if (_arztTermineLoading[type] == true) return;
    _arztTermineLoading[type] = true;
    try {
      final result = await widget.apiService.getArztTermine(widget.user.id, type);
      if (mounted) {
        setState(() {
          final loaded = List<Map<String, dynamic>>.from(result['termine'] ?? []);
          for (final t in loaded) {
            debugPrint('[ArztTermine] id=${t['id']}, datum=${t['datum']}, keys=${t.keys.toList()}');
          }
          _arztTermine[type] = loaded;
          _arztTermineLoading[type] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _arztTermineLoading[type] = false;
          _arztTermine[type] = [];
        });
      }
    }
  }

  Widget _buildArztTermineTab(String type, String arztTitle, {Map<String, dynamic>? data, VoidCallback? saveAll, StateSetter? setLocalState}) {
    if (!_arztTermine.containsKey(type) && _arztTermineLoading[type] != true) {
      _loadArztTermine(type);
    }
    if (_arztTermineLoading[type] == true) {
      return const Center(child: CircularProgressIndicator());
    }

    final termine = _arztTermine[type] ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.calendar_month, size: 20, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Text('Termine bei $arztTitle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: () => _showTerminAnfrageDialog(type, arztTitle),
                icon: Icon(Icons.send, size: 16, color: Colors.orange.shade700),
                label: Text('Anfrage', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.orange.shade300), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showTerminAbsageDialog(type, arztTitle),
                icon: Icon(Icons.event_busy, size: 16, color: Colors.red.shade700),
                label: Text('Absage', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showTerminVerschiebenDialog(type, arztTitle),
                icon: Icon(Icons.event_repeat, size: 16, color: Colors.blue.shade700),
                label: Text('Verschieben', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.blue.shade300), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showArztTerminDialog(type, arztTitle, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neuer Termin'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
        ),
        if (data != null && saveAll != null && setLocalState != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildVorsorgeErinnerung(type, arztTitle, data, saveAll, setLocalState),
          ),
        const Divider(height: 1),
        Expanded(
          child: termine.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event_busy, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Keine Termine vorhanden', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: termine.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final t = termine[index];
                    final isNotfall = t['typ'] == 'notfall';
                    final isAnfrage = t['typ'] == 'anfrage';
                    return Container(
                      decoration: BoxDecoration(
                        color: isNotfall ? Colors.red.shade50 : (isAnfrage ? Colors.orange.shade50 : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isNotfall ? Colors.red.shade300 : (isAnfrage ? Colors.orange.shade300 : Colors.grey.shade300)),
                      ),
                      child: ListTile(
                        onTap: () => _showArztTerminDetailsDialog(type, arztTitle, t),
                        leading: CircleAvatar(
                          backgroundColor: isNotfall ? Colors.red.shade100 : (isAnfrage ? Colors.orange.shade100 : Colors.teal.shade100),
                          child: Icon(
                            isNotfall ? Icons.emergency : (isAnfrage ? Icons.send : Icons.calendar_today),
                            color: isNotfall ? Colors.red.shade700 : Colors.teal.shade700,
                            size: 20,
                          ),
                        ),
                        title: Row(
                          children: [
                            Text(t['datum'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            if (t['uhrzeit']?.isNotEmpty == true) ...[
                              const SizedBox(width: 8),
                              Text(t['uhrzeit'], style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                            ],
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isNotfall ? Colors.red.shade700 : (isAnfrage ? Colors.orange.shade700 : Colors.teal.shade700),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isNotfall ? 'NOTFALL' : (isAnfrage ? 'ANFRAGE' : 'Normal'),
                                style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (isAnfrage && (t['anfrage_methode']?.isNotEmpty == true)) ...[
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Row(children: [
                                  Icon(Icons.send, size: 12, color: Colors.orange.shade600),
                                  const SizedBox(width: 4),
                                  Text({'online': 'Online', 'email': 'Per E-Mail', 'telefonisch': 'Telefonisch', 'persoenlich': 'Persoenlich', 'postalisch': 'Postalisch'}[t['anfrage_methode']] ?? t['anfrage_methode'], style: TextStyle(fontSize: 11, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                                ]),
                              ),
                            ],
                            if (t['diagnose']?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(t['diagnose'], style: const TextStyle(fontSize: 13)),
                              ),
                            if (t['notizen']?.isNotEmpty == true)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(t['notizen'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                              ),
                          ],
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, size: 18, color: Colors.teal.shade600),
                              tooltip: 'Bearbeiten',
                              onPressed: () => _showArztTerminDialog(type, arztTitle, t),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                              tooltip: 'Löschen',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Termin löschen?'),
                                    content: Text('Termin vom ${t['datum']} wirklich löschen?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                      TextButton(
                                        onPressed: () => Navigator.pop(ctx, true),
                                        child: const Text('Löschen', style: TextStyle(color: Colors.red)),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await widget.apiService.saveArztTermin({
                                    'action': 'delete',
                                    'user_id': widget.user.id,
                                    'arzt_type': type,
                                    'termin_id': t['id'],
                                  });
                                  _arztTermine.remove(type);
                                  _loadArztTermine(type);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showArztTerminDetailsDialog(String type, String arztTitle, Map<String, dynamic> termin) {
    final isNotfall = termin['typ'] == 'notfall';
    final isAnfrage = termin['typ'] == 'anfrage';
    final typLabel = isNotfall ? 'NOTFALL' : (isAnfrage ? 'ANFRAGE' : 'Normal');
    final typColor = isNotfall ? Colors.red : (isAnfrage ? Colors.orange : Colors.teal);

    // Korrespondenz stored in termin data
    List<Map<String, dynamic>> korrespondenz = List<Map<String, dynamic>>.from(termin['korrespondenz'] ?? []);
    // Notizen liste stored in termin data
    List<Map<String, dynamic>> notizenListe = List<Map<String, dynamic>>.from(termin['notizen_liste'] ?? []);
    // Migrate old single notizen to liste
    if (notizenListe.isEmpty && (termin['notizen']?.toString() ?? '').isNotEmpty) {
      notizenListe.add({'text': termin['notizen'], 'datum': termin['datum'] ?? '', 'erstellt': ''});
    }
    final terminId = termin['id'];
    debugPrint('[Notizen] terminId=$terminId, termin keys=${termin.keys.toList()}');

    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: 3,
        child: StatefulBuilder(
          builder: (context, setDState) => Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: SizedBox(
              width: 550,
              height: 500,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: typColor.shade50,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                    ),
                    child: Row(
                      children: [
                        Icon(isNotfall ? Icons.emergency : (isAnfrage ? Icons.send : Icons.calendar_today), color: typColor.shade700),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Termin bei $arztTitle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: typColor.shade800)),
                              const SizedBox(height: 2),
                              Row(children: [
                                Text(termin['datum'] ?? '', style: TextStyle(fontSize: 13, color: typColor.shade700)),
                                if (termin['uhrzeit']?.isNotEmpty == true) ...[
                                  const SizedBox(width: 6),
                                  Text('um ${termin['uhrzeit']} Uhr', style: TextStyle(fontSize: 13, color: typColor.shade600)),
                                ],
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(color: typColor.shade700, borderRadius: BorderRadius.circular(12)),
                                  child: Text(typLabel, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                                ),
                              ]),
                            ],
                          ),
                        ),
                        IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                      ],
                    ),
                  ),
                  // Tabs
                  TabBar(
                    labelColor: typColor.shade700,
                    indicatorColor: typColor.shade700,
                    tabs: const [
                      Tab(text: 'Details'),
                      Tab(text: 'Korrespondenz'),
                      Tab(text: 'Notizen'),
                    ],
                  ),
                  // Tab content
                  Expanded(
                    child: TabBarView(
                      children: [
                        // === Details Tab ===
                        SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _terminDetailRow(Icons.calendar_today, 'Datum', termin['datum'] ?? '-'),
                              if (termin['uhrzeit']?.isNotEmpty == true)
                                _terminDetailRow(Icons.access_time, 'Uhrzeit', termin['uhrzeit']),
                              _terminDetailRow(Icons.category, 'Typ', typLabel),
                              if (isAnfrage && termin['anfrage_methode']?.isNotEmpty == true)
                                _terminDetailRow(Icons.send, 'Anfrage per', {
                                  'online': 'Online', 'email': 'Per E-Mail', 'telefonisch': 'Telefonisch',
                                  'persoenlich': 'Persönlich', 'postalisch': 'Postalisch',
                                }[termin['anfrage_methode']] ?? termin['anfrage_methode']),
                              if (termin['diagnose']?.isNotEmpty == true)
                                _terminDetailRow(Icons.medical_information, 'Diagnose / Grund', termin['diagnose']),
                              if (termin['notizen']?.isNotEmpty == true)
                                _terminDetailRow(Icons.note, 'Notizen', termin['notizen']),
                              if (termin['created_at']?.isNotEmpty == true)
                                _terminDetailRow(Icons.schedule, 'Erstellt am', termin['created_at']),
                            ],
                          ),
                        ),
                        // === Korrespondenz Tab ===
                        Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                              child: Row(
                                children: [
                                  Icon(Icons.mail, size: 18, color: Colors.indigo.shade600),
                                  const SizedBox(width: 6),
                                  Text('Korrespondenz', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                                  const Spacer(),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      setDState(() {
                                        korrespondenz.add({
                                          'datum': DateTime.now().toString().substring(0, 10),
                                          'art': 'email',
                                          'betreff': '',
                                          'inhalt': '',
                                          'richtung': 'ausgehend',
                                          '_editing': true,
                                        });
                                      });
                                    },
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Neue Korrespondenz', style: TextStyle(fontSize: 12)),
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1),
                            Expanded(
                              child: korrespondenz.isEmpty
                                  ? Center(child: Text('Keine Korrespondenz vorhanden', style: TextStyle(color: Colors.grey.shade500)))
                                  : ListView.builder(
                                      padding: const EdgeInsets.all(12),
                                      itemCount: korrespondenz.length,
                                      itemBuilder: (context, idx) {
                                        final k = korrespondenz[idx];
                                        final isEditing = k['_editing'] == true;
                                        final artIcons = {'email': Icons.email, 'telefon': Icons.phone, 'brief': Icons.mail, 'fax': Icons.fax, 'persoenlich': Icons.person};
                                        final artLabels = {'email': 'E-Mail', 'telefon': 'Telefon', 'brief': 'Brief', 'fax': 'Fax', 'persoenlich': 'Persönlich'};
                                        final richtungLabels = {'ausgehend': 'Ausgehend', 'eingehend': 'Eingehend'};

                                        if (isEditing) {
                                          final datumC = TextEditingController(text: k['datum'] ?? '');
                                          final betreffC = TextEditingController(text: k['betreff'] ?? '');
                                          final inhaltC = TextEditingController(text: k['inhalt'] ?? '');
                                          String art = k['art'] ?? 'email';
                                          String richtung = k['richtung'] ?? 'ausgehend';
                                          return Card(
                                            elevation: 2,
                                            child: Padding(
                                              padding: const EdgeInsets.all(12),
                                              child: StatefulBuilder(
                                                builder: (ctx2, setEditState) => Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Row(children: [
                                                      Expanded(
                                                        child: TextField(
                                                          controller: datumC,
                                                          decoration: InputDecoration(
                                                            labelText: 'Datum',
                                                            isDense: true,
                                                            suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 16), onPressed: () async {
                                                              final d = await showDatePicker(context: context, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                                                              if (d != null) datumC.text = d.toString().substring(0, 10);
                                                            }),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      DropdownButton<String>(
                                                        value: richtung,
                                                        items: richtungLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)))).toList(),
                                                        onChanged: (v) => setEditState(() => richtung = v!),
                                                      ),
                                                    ]),
                                                    const SizedBox(height: 8),
                                                    Wrap(spacing: 6, children: artLabels.entries.map((e) => ChoiceChip(
                                                      label: Text(e.value, style: const TextStyle(fontSize: 11)),
                                                      selected: art == e.key,
                                                      onSelected: (_) => setEditState(() => art = e.key),
                                                      selectedColor: Colors.indigo.shade100,
                                                    )).toList()),
                                                    const SizedBox(height: 8),
                                                    TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true)),
                                                    const SizedBox(height: 8),
                                                    TextField(controller: inhaltC, decoration: const InputDecoration(labelText: 'Inhalt / Zusammenfassung', isDense: true), maxLines: 3),
                                                    const SizedBox(height: 10),
                                                    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                                                      TextButton(
                                                        onPressed: () => setDState(() {
                                                          if (k['betreff']?.isEmpty != false && k['inhalt']?.isEmpty != false) {
                                                            korrespondenz.removeAt(idx);
                                                          } else {
                                                            k.remove('_editing');
                                                          }
                                                        }),
                                                        child: const Text('Abbrechen'),
                                                      ),
                                                      const SizedBox(width: 8),
                                                      ElevatedButton(
                                                        onPressed: () async {
                                                          k['datum'] = datumC.text;
                                                          k['art'] = art;
                                                          k['richtung'] = richtung;
                                                          k['betreff'] = betreffC.text;
                                                          k['inhalt'] = inhaltC.text;
                                                          k.remove('_editing');
                                                          // Save to server
                                                          termin['korrespondenz'] = korrespondenz.map((e) {
                                                            final copy = Map<String, dynamic>.from(e);
                                                            copy.remove('_editing');
                                                            return copy;
                                                          }).toList();
                                                          await widget.apiService.saveArztTermin({
                                                            'action': 'update',
                                                            'user_id': widget.user.id,
                                                            'arzt_type': type,
                                                            'termin_id': termin['id'],
                                                            'korrespondenz': termin['korrespondenz'],
                                                          });
                                                          setDState(() {});
                                                        },
                                                        style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
                                                        child: const Text('Speichern'),
                                                      ),
                                                    ]),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          );
                                        }

                                        // Read-only view
                                        return Card(
                                          child: ListTile(
                                            onTap: () {
                                              showDialog(
                                                context: context,
                                                builder: (vCtx) => AlertDialog(
                                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                                  title: Row(children: [
                                                    Icon(artIcons[k['art']] ?? Icons.mail, color: Colors.indigo.shade600),
                                                    const SizedBox(width: 8),
                                                    Expanded(child: Text(k['betreff']?.isNotEmpty == true ? k['betreff'] : 'Korrespondenz', style: TextStyle(fontSize: 16, color: Colors.indigo.shade800))),
                                                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(vCtx)),
                                                  ]),
                                                  content: SingleChildScrollView(
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        _terminDetailRow(Icons.calendar_today, 'Datum', k['datum'] ?? '-'),
                                                        _terminDetailRow(artIcons[k['art']] ?? Icons.mail, 'Art', artLabels[k['art']] ?? '-'),
                                                        _terminDetailRow(k['richtung'] == 'eingehend' ? Icons.call_received : Icons.call_made, 'Richtung', richtungLabels[k['richtung']] ?? '-'),
                                                        if (k['betreff']?.isNotEmpty == true) _terminDetailRow(Icons.subject, 'Betreff', k['betreff']),
                                                        if (k['inhalt']?.isNotEmpty == true) ...[
                                                          const Divider(),
                                                          Text('Inhalt / Zusammenfassung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                                          const SizedBox(height: 6),
                                                          Container(
                                                            width: double.infinity,
                                                            padding: const EdgeInsets.all(10),
                                                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                                                            child: SelectableText(k['inhalt'], style: const TextStyle(fontSize: 13)),
                                                          ),
                                                        ],
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              );
                                            },
                                            leading: Icon(artIcons[k['art']] ?? Icons.mail, color: Colors.indigo.shade600),
                                            title: Row(children: [
                                              Text(k['datum'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                              const SizedBox(width: 8),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(color: k['richtung'] == 'eingehend' ? Colors.green.shade100 : Colors.blue.shade100, borderRadius: BorderRadius.circular(8)),
                                                child: Text(richtungLabels[k['richtung']] ?? '', style: TextStyle(fontSize: 10, color: k['richtung'] == 'eingehend' ? Colors.green.shade700 : Colors.blue.shade700)),
                                              ),
                                              const SizedBox(width: 6),
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                                decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                                                child: Text(artLabels[k['art']] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade700)),
                                              ),
                                            ]),
                                            subtitle: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                if (k['betreff']?.isNotEmpty == true) Text(k['betreff'], style: const TextStyle(fontSize: 13)),
                                                if (k['inhalt']?.isNotEmpty == true) Text(k['inhalt'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600), maxLines: 2, overflow: TextOverflow.ellipsis),
                                              ],
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                IconButton(
                                                  icon: Icon(Icons.edit, size: 16, color: Colors.indigo.shade400),
                                                  onPressed: () => setDState(() => k['_editing'] = true),
                                                ),
                                                IconButton(
                                                  icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
                                                  onPressed: () async {
                                                    korrespondenz.removeAt(idx);
                                                    termin['korrespondenz'] = korrespondenz.map((e) {
                                                      final copy = Map<String, dynamic>.from(e);
                                                      copy.remove('_editing');
                                                      return copy;
                                                    }).toList();
                                                    await widget.apiService.saveArztTermin({
                                                      'action': 'update',
                                                      'user_id': widget.user.id,
                                                      'arzt_type': type,
                                                      'termin_id': termin['id'],
                                                      'korrespondenz': termin['korrespondenz'],
                                                    });
                                                    setDState(() {});
                                                  },
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                        // === Notizen Tab ===
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: StatefulBuilder(builder: (nCtx, setNState) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  Icon(Icons.note_alt, size: 20, color: Colors.amber.shade700),
                                  const SizedBox(width: 8),
                                  Text('Notizen (${notizenListe.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber.shade700)),
                                  const Spacer(),
                                  FilledButton.icon(
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Neue Notiz', style: TextStyle(fontSize: 12)),
                                    style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                                    onPressed: () {
                                      final newNotizC = TextEditingController();
                                      showDialog(
                                        context: nCtx,
                                        builder: (dlg) => AlertDialog(
                                          title: Row(children: [
                                            Icon(Icons.note_add, size: 18, color: Colors.amber.shade700),
                                            const SizedBox(width: 8),
                                            const Text('Neue Notiz', style: TextStyle(fontSize: 15)),
                                          ]),
                                          content: SizedBox(
                                            width: 400, height: 200,
                                            child: TextField(
                                              controller: newNotizC,
                                              maxLines: null, expands: true,
                                              textAlignVertical: TextAlignVertical.top,
                                              autofocus: true,
                                              decoration: InputDecoration(
                                                hintText: 'Notiz eingeben...',
                                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                                filled: true, fillColor: Colors.amber.shade50,
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(onPressed: () => Navigator.pop(dlg), child: const Text('Abbrechen')),
                                            FilledButton.icon(
                                              icon: const Icon(Icons.save, size: 16),
                                              label: const Text('Speichern'),
                                              style: FilledButton.styleFrom(backgroundColor: Colors.amber.shade700),
                                              onPressed: () async {
                                                if (newNotizC.text.trim().isEmpty) return;
                                                final now = DateTime.now();
                                                final notiz = {
                                                  'text': newNotizC.text.trim(),
                                                  'datum': '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
                                                  'erstellt': '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}',
                                                };
                                                notizenListe.insert(0, notiz);
                                                termin['notizen_liste'] = notizenListe;
                                                Navigator.pop(dlg);
                                                // Save to server
                                                try {
                                                  await widget.apiService.saveArztTermin({
                                                    'action': 'update_notizen',
                                                    'user_id': widget.user.id,
                                                    'arzt_type': type,
                                                    'termin_id': terminId,
                                                    'notizen_liste': notizenListe,
                                                  });
                                                  if (nCtx.mounted) {
                                                    setNState(() {});
                                                    ScaffoldMessenger.of(nCtx).showSnackBar(
                                                      const SnackBar(content: Text('Notiz gespeichert'), backgroundColor: Colors.green),
                                                    );
                                                  }
                                                } catch (e) {
                                                  if (nCtx.mounted) {
                                                    ScaffoldMessenger.of(nCtx).showSnackBar(
                                                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                                    );
                                                  }
                                                }
                                              },
                                            ),
                                          ],
                                        ),
                                      );
                                    },
                                  ),
                                ]),
                                const SizedBox(height: 12),
                                Expanded(
                                  child: notizenListe.isEmpty
                                    ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Icon(Icons.note_alt_outlined, size: 40, color: Colors.grey.shade300),
                                        const SizedBox(height: 8),
                                        Text('Keine Notizen vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                                      ]))
                                    : ListView.builder(
                                        itemCount: notizenListe.length,
                                        itemBuilder: (_, i) {
                                          final n = notizenListe[i];
                                          return Container(
                                            margin: const EdgeInsets.only(bottom: 8),
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: Colors.amber.shade50,
                                              borderRadius: BorderRadius.circular(8),
                                              border: Border.all(color: Colors.amber.shade200),
                                            ),
                                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                              Row(children: [
                                                Icon(Icons.note, size: 16, color: Colors.amber.shade700),
                                                const SizedBox(width: 6),
                                                Text('${n['datum'] ?? ''} ${n['erstellt'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.amber.shade600, fontWeight: FontWeight.w600)),
                                                const Spacer(),
                                                InkWell(
                                                  onTap: () async {
                                                    notizenListe.removeAt(i);
                                                    termin['notizen_liste'] = notizenListe;
                                                    try {
                                                      await widget.apiService.saveArztTermin({
                                                        'action': 'update_notizen',
                                                        'user_id': widget.user.id,
                                                        'termin_id': terminId,
                                                        'notizen_liste': notizenListe,
                                                      });
                                                    } catch (_) {}
                                                    setNState(() {});
                                                  },
                                                  child: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                                                ),
                                              ]),
                                              const SizedBox(height: 6),
                                              Text(n['text']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                                            ]),
                                          );
                                        },
                                      ),
                                ),
                              ],
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _terminDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: Colors.grey.shade600),
          const SizedBox(width: 10),
          SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
        ],
      ),
    );
  }

  void _showTerminAnfrageDialog(String type, String arztTitle) {
    String methode = '';
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    final scriptC = TextEditingController();

    final methoden = {
      'online': ('Online', Icons.language),
      'email': ('Per E-Mail', Icons.email),
      'telefonisch': ('Telefonisch', Icons.phone),
      'persoenlich': ('Persoenlich', Icons.person),
      'postalisch': ('Postalisch', Icons.mail),
    };

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.send, size: 20, color: Colors.orange.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Terminanfrage \u2013 $arztTitle', style: const TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Methode
                  Text('Wie wurde die Anfrage gestellt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: methoden.entries.map((m) {
                      final sel = methode == m.key;
                      return ChoiceChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(m.value.$2, size: 14, color: sel ? Colors.white : Colors.orange.shade700),
                          const SizedBox(width: 4),
                          Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.orange.shade700)),
                        ]),
                        selected: sel,
                        selectedColor: Colors.orange.shade600,
                        backgroundColor: Colors.orange.shade50,
                        side: BorderSide(color: sel ? Colors.orange.shade600 : Colors.orange.shade200),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (_) => setDlgState(() => methode = m.key),
                      );
                    }).toList(),
                  ),
                  // Online Anfrage button (from selected arzt's online_termin_url)
                  () {
                    final arztData = _gesundheitData[type] ?? {};
                    final selArzt = arztData['selected_arzt'] as Map? ?? {};
                    final onlineUrl = selArzt['online_termin_url']?.toString() ?? '';
                    final arztName = selArzt['praxis_name']?.toString() ?? selArzt['arzt_name']?.toString() ?? arztTitle;
                    if (onlineUrl.isEmpty) return const SizedBox.shrink();
                    return Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.push(context, MaterialPageRoute(
                              builder: (_) => WebViewScreen(title: 'Online Terminanfrage - $arztName', url: onlineUrl),
                            ));
                          },
                          icon: Icon(Icons.language, size: 16, color: Colors.blue.shade700),
                          label: Text('Online Anfrage ($arztName)', style: TextStyle(fontSize: 12, color: Colors.blue.shade700)),
                          style: OutlinedButton.styleFrom(
                            side: BorderSide(color: Colors.blue.shade300),
                            backgroundColor: Colors.blue.shade50,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          ),
                        ),
                      ),
                    );
                  }(),
                  const SizedBox(height: 14),
                  // Datum
                  TextField(
                    controller: datumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Anfrage am *',
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            datumC.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Betreff / Grund
                  TextField(
                    controller: betreffC,
                    decoration: InputDecoration(
                      labelText: 'Grund der Anfrage',
                      prefixIcon: const Icon(Icons.subject, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Notiz
                  TextField(
                    controller: notizC,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notiz (optional)',
                      prefixIcon: const Icon(Icons.note, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // === SCRIPT ===
                  Row(children: [
                    Icon(Icons.description, size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 6),
                    Text('E-Mail Script', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                    const Spacer(),
                    TextButton.icon(
                      icon: Icon(Icons.auto_fix_high, size: 14, color: Colors.purple.shade600),
                      label: Text('Generieren', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () async {
                        final vorsorge = _getVorsorgeBezeichnung(type);
                        final arztData = _gesundheitData[type] ?? {};
                        final selArzt = arztData['selected_arzt'] as Map? ?? {};
                        final arztEmail = selArzt['email']?.toString() ?? '';
                        final arztPraxis = selArzt['praxis_name']?.toString() ?? '';
                        String kkName = '';
                        String versNr = '';
                        try {
                          final kkRes = await widget.apiService.getBehoerdeData(widget.user.id, 'krankenkasse');
                          if (kkRes['success'] == true && kkRes['data'] != null) {
                            final kkData = Map<String, dynamic>.from(kkRes['data']);
                            kkName = kkData['name']?.toString() ?? '';
                            versNr = kkData['versichertennummer']?.toString() ?? '';
                          }
                        } catch (_) {}
                        final patientName = widget.user.name;
                        final geb = widget.user.geburtsdatum ?? '';
                        final betreff = 'Terminanfrage: $vorsorge – $patientName';
                        betreffC.text = betreff;
                        final intervall = type == 'gesundheit_zahnarzt' ? 'halbjährliche' : 'jährliche';
                        final script = StringBuffer();
                        if (arztEmail.isNotEmpty) script.writeln('An: $arztEmail${arztPraxis.isNotEmpty ? ' ($arztPraxis)' : ''}');
                        script.writeln('Betreff: $betreff');
                        script.writeln();
                        script.writeln('Sehr geehrte Damen und Herren,');
                        script.writeln();
                        script.writeln('hiermit möchte ich einen Termin für eine $vorsorge vereinbaren.');
                        script.writeln();
                        script.writeln('Angaben zum Patienten:');
                        script.writeln('Name: $patientName');
                        if (geb.isNotEmpty) script.writeln('Geburtsdatum: $geb');
                        if (kkName.isNotEmpty) script.writeln('Krankenkasse: $kkName');
                        if (versNr.isNotEmpty) script.writeln('Versichertennummer: $versNr');
                        script.writeln();
                        script.writeln('Ich bitte um einen zeitnahen Termin für die $intervall Vorsorgeuntersuchung.');
                        script.writeln();
                        script.writeln('Bitte teilen Sie mir mögliche Termine per E-Mail mit.');
                        script.writeln();
                        script.writeln('Mit freundlichen Grüßen');
                        script.writeln(patientName);
                        script.writeln();
                        script.writeln('---');
                        script.writeln('Dieser Service wird im Rahmen der ICD360S e.V. – gemeinnützige Organisation 2025–${DateTime.now().year} bereitgestellt.');
                        setDlgState(() => scriptC.text = script.toString());
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.purple.shade200), borderRadius: BorderRadius.circular(8), color: Colors.purple.shade50),
                    child: TextField(
                      controller: scriptC,
                      maxLines: 12,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(hintText: 'Klicken Sie auf "Generieren"...', hintStyle: TextStyle(fontSize: 11, color: Colors.purple.shade300), border: InputBorder.none, contentPadding: const EdgeInsets.all(12)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Builder(builder: (_) {
                      final ad = _gesundheitData[type] ?? {};
                      final sa = ad['selected_arzt'] as Map? ?? {};
                      final em = sa['email']?.toString() ?? '';
                      if (em.isEmpty) return const SizedBox.shrink();
                      return TextButton.icon(
                        icon: Icon(Icons.email, size: 14, color: Colors.blue.shade600),
                        label: Text('E-Mail kopieren', style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                        onPressed: () {
                          if (context.mounted) ClipboardHelper.copy(context, em, 'E-Mail');
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: Icon(Icons.copy, size: 14, color: Colors.purple.shade600),
                      label: Text('Script kopieren', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                      onPressed: () {
                        if (scriptC.text.isNotEmpty) {
                          if (context.mounted) ClipboardHelper.copy(context, scriptC.text, 'Script');
                        }
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.send, size: 16),
              label: const Text('Anfrage speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600),
              onPressed: () async {
                if (datumC.text.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Datum auswahlen'), backgroundColor: Colors.red));
                  return;
                }
                if (methode.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Art der Anfrage auswahlen'), backgroundColor: Colors.red));
                  return;
                }
                try {
                  // Build arzt location for Terminverwaltung
                  final arztData = _gesundheitData[type] ?? {};
                  final selArzt = arztData['selected_arzt'] as Map? ?? {};
                  final arztOrt = [
                    if ((selArzt['praxis_name']?.toString() ?? '').isNotEmpty) selArzt['praxis_name'],
                    if ((selArzt['arzt_name']?.toString() ?? '').isNotEmpty) selArzt['arzt_name'],
                    if ((selArzt['strasse']?.toString() ?? '').isNotEmpty) selArzt['strasse'],
                    if ((selArzt['plz_ort']?.toString() ?? '').isNotEmpty) selArzt['plz_ort'],
                  ].join(', ');

                  final result = await widget.apiService.saveArztTermin({
                    'action': 'add',
                    'user_id': widget.user.id,
                    'arzt_type': type,
                    'datum': datumC.text,
                    'typ': 'anfrage',
                    'anfrage_methode': methode,
                    'diagnose': betreffC.text.trim(),
                    'notizen': notizC.text.trim(),
                    'arzt_ort': arztOrt,
                  });
                  if (result['success'] == true) {
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                    if (mounted) {
                      _arztTermine.remove(type);
                      _loadArztTermine(type);

                      // Auto-create ticket for Anfrage
                      try {
                        final arztData2 = _gesundheitData[type] ?? {};
                        final selArzt2 = arztData2['selected_arzt'] as Map? ?? {};
                        final praxisName = selArzt2['praxis_name']?.toString() ?? selArzt2['arzt_name']?.toString() ?? arztTitle;
                        final patientName = widget.user.name;
                        final ticketSubject = 'Arzt-Anfrage: $arztTitle — $patientName';
                        final ticketMsg = [
                          'Arzt: $praxisName ($arztTitle)',
                          'Patient: $patientName (${widget.user.mitgliedernummer})',
                          'Datum: ${datumC.text}',
                          'Methode: $methode',
                          if (betreffC.text.isNotEmpty) 'Grund: ${betreffC.text}',
                          if (notizC.text.isNotEmpty) 'Notiz: ${notizC.text}',
                          '',
                          'Automatisch erstellt aus Arzt-Terminanfrage.',
                        ].join('\n');

                        await widget.ticketService.createTicket(
                          mitgliedernummer: widget.user.mitgliedernummer,
                          subject: ticketSubject,
                          message: ticketMsg,
                          priority: 'medium',
                          systemTicket: true,
                          scheduledDate: datumC.text,
                        );
                      } catch (e) {
                        debugPrint('[Gesundheit] Ticket create error: $e');
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Terminanfrage gespeichert + Ticket erstellt'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler: ${result['message'] ?? 'Unbekannter Fehler'}'), backgroundColor: Colors.red),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Absage-Dialog — same structure as Anfrage, but for cancelling appointments.
  /// Generates a polite German cancellation letter based on web templates.
  void _showTerminAbsageDialog(String type, String arztTitle) {
    String methode = '';
    final datumC = TextEditingController();          // date of original appointment
    final uhrzeitC = TextEditingController();
    final betreffC = TextEditingController();
    final grundC = TextEditingController();
    final scriptC = TextEditingController();

    final methoden = {
      'telefonisch': ('Telefonisch', Icons.phone),
      'email': ('Per E-Mail', Icons.email),
      'online': ('Online', Icons.language),
      'persoenlich': ('Persoenlich', Icons.person),
      'postalisch': ('Postalisch', Icons.mail),
    };

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.event_busy, size: 20, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Terminabsage \u2013 $arztTitle', style: const TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Methode
                  Text('Wie wurde der Termin abgesagt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: methoden.entries.map((m) {
                      final sel = methode == m.key;
                      return ChoiceChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(m.value.$2, size: 14, color: sel ? Colors.white : Colors.red.shade700),
                          const SizedBox(width: 4),
                          Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.red.shade700)),
                        ]),
                        selected: sel,
                        selectedColor: Colors.red.shade600,
                        backgroundColor: Colors.red.shade50,
                        side: BorderSide(color: sel ? Colors.red.shade600 : Colors.red.shade200),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (_) => setDlgState(() => methode = m.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Datum des ursprünglichen Termins
                  TextField(
                    controller: datumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Ursprünglicher Termin (Datum) *',
                      prefixIcon: const Icon(Icons.event, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            datumC.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Uhrzeit
                  TextField(
                    controller: uhrzeitC,
                    decoration: InputDecoration(
                      labelText: 'Uhrzeit (z.B. 14:30)',
                      prefixIcon: const Icon(Icons.access_time, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Betreff
                  TextField(
                    controller: betreffC,
                    decoration: InputDecoration(
                      labelText: 'Betreff',
                      prefixIcon: const Icon(Icons.subject, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Grund der Absage
                  TextField(
                    controller: grundC,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Grund der Absage (optional)',
                      prefixIcon: const Icon(Icons.info_outline, size: 18),
                      hintText: 'z.B. Krankheit, beruflich verhindert',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // === SCRIPT ===
                  Row(children: [
                    Icon(Icons.description, size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 6),
                    Text('E-Mail Script', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                    const Spacer(),
                    TextButton.icon(
                      icon: Icon(Icons.auto_fix_high, size: 14, color: Colors.purple.shade600),
                      label: Text('Generieren', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () {
                        final arztData = _gesundheitData[type] ?? {};
                        final selArzt = arztData['selected_arzt'] as Map? ?? {};
                        final arztEmail = selArzt['email']?.toString() ?? '';
                        final arztPraxis = selArzt['praxis_name']?.toString() ?? '';
                        final patientName = widget.user.name;
                        final geb = widget.user.geburtsdatum ?? '';
                        final terminDatum = datumC.text.isNotEmpty ? datumC.text : '[Datum eintragen]';
                        final terminZeit = uhrzeitC.text.isNotEmpty ? ' um ${uhrzeitC.text} Uhr' : '';
                        final grundTxt = grundC.text.trim();
                        final betreff = 'Terminabsage – $patientName, am $terminDatum';
                        betreffC.text = betreff;

                        final script = StringBuffer();
                        if (arztEmail.isNotEmpty) script.writeln('An: $arztEmail${arztPraxis.isNotEmpty ? ' ($arztPraxis)' : ''}');
                        script.writeln('Betreff: $betreff');
                        script.writeln();
                        script.writeln('Sehr geehrtes Praxisteam,');
                        script.writeln();
                        script.writeln('leider muss ich meinen Termin am $terminDatum$terminZeit absagen${grundTxt.isNotEmpty ? ', da $grundTxt' : ''}.');
                        script.writeln();
                        script.writeln('Angaben zum Patienten:');
                        script.writeln('Name: $patientName');
                        if (geb.isNotEmpty) script.writeln('Geburtsdatum: $geb');
                        script.writeln();
                        script.writeln('Vielen Dank für Ihr Verständnis.');
                        script.writeln();
                        script.writeln('Mit freundlichen Grüßen');
                        script.writeln(patientName);
                        script.writeln();
                        script.writeln('---');
                        script.writeln('Dieser Service wird im Rahmen der ICD360S e.V. – gemeinnützige Organisation 2025–${DateTime.now().year} bereitgestellt.');
                        setDlgState(() => scriptC.text = script.toString());
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.purple.shade200), borderRadius: BorderRadius.circular(8), color: Colors.purple.shade50),
                    child: TextField(
                      controller: scriptC,
                      maxLines: 12,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(hintText: 'Klicken Sie auf "Generieren"...', hintStyle: TextStyle(fontSize: 11, color: Colors.purple.shade300), border: InputBorder.none, contentPadding: const EdgeInsets.all(12)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Builder(builder: (_) {
                      final ad = _gesundheitData[type] ?? {};
                      final sa = ad['selected_arzt'] as Map? ?? {};
                      final em = sa['email']?.toString() ?? '';
                      if (em.isEmpty) return const SizedBox.shrink();
                      return TextButton.icon(
                        icon: Icon(Icons.email, size: 14, color: Colors.blue.shade600),
                        label: Text('E-Mail kopieren', style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                        onPressed: () {
                          if (context.mounted) ClipboardHelper.copy(context, em, 'E-Mail');
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: Icon(Icons.copy, size: 14, color: Colors.purple.shade600),
                      label: Text('Script kopieren', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                      onPressed: () {
                        if (scriptC.text.isNotEmpty) {
                          if (context.mounted) ClipboardHelper.copy(context, scriptC.text, 'Script');
                        }
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.event_busy, size: 16),
              label: const Text('Absage speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
              onPressed: () async {
                if (datumC.text.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Datum des ursprünglichen Termins auswählen'), backgroundColor: Colors.red));
                  return;
                }
                if (methode.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Art der Absage auswählen'), backgroundColor: Colors.red));
                  return;
                }
                try {
                  final arztData = _gesundheitData[type] ?? {};
                  final selArzt = arztData['selected_arzt'] as Map? ?? {};
                  final arztOrt = [
                    if ((selArzt['praxis_name']?.toString() ?? '').isNotEmpty) selArzt['praxis_name'],
                    if ((selArzt['arzt_name']?.toString() ?? '').isNotEmpty) selArzt['arzt_name'],
                    if ((selArzt['strasse']?.toString() ?? '').isNotEmpty) selArzt['strasse'],
                    if ((selArzt['plz_ort']?.toString() ?? '').isNotEmpty) selArzt['plz_ort'],
                  ].join(', ');

                  final result = await widget.apiService.saveArztTermin({
                    'action': 'add',
                    'user_id': widget.user.id,
                    'arzt_type': type,
                    'datum': datumC.text,
                    'uhrzeit': uhrzeitC.text.trim(),
                    'typ': 'absage',
                    'anfrage_methode': methode,
                    'diagnose': betreffC.text.trim(),
                    'notizen': grundC.text.trim(),
                    'arzt_ort': arztOrt,
                  });
                  if (result['success'] == true) {
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                    if (mounted) {
                      _arztTermine.remove(type);
                      _loadArztTermine(type);

                      // Auto-create ticket for Absage
                      try {
                        final praxisName = selArzt['praxis_name']?.toString() ?? selArzt['arzt_name']?.toString() ?? arztTitle;
                        final patientName = widget.user.name;
                        final ticketSubject = 'Arzt-Absage: $arztTitle — $patientName';
                        final ticketMsg = [
                          'Arzt: $praxisName ($arztTitle)',
                          'Patient: $patientName (${widget.user.mitgliedernummer})',
                          'Termin: ${datumC.text}${uhrzeitC.text.isNotEmpty ? ' um ${uhrzeitC.text}' : ''}',
                          'Absage per: $methode',
                          if (betreffC.text.isNotEmpty) 'Betreff: ${betreffC.text}',
                          if (grundC.text.isNotEmpty) 'Grund: ${grundC.text}',
                          '',
                          'Automatisch erstellt aus Terminabsage.',
                        ].join('\n');

                        await widget.ticketService.createTicket(
                          mitgliedernummer: widget.user.mitgliedernummer,
                          subject: ticketSubject,
                          message: ticketMsg,
                          priority: 'medium',
                          systemTicket: true,
                          scheduledDate: datumC.text,
                        );
                      } catch (e) {
                        debugPrint('[Gesundheit] Ticket create error: $e');
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Terminabsage gespeichert + Ticket erstellt'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler: ${result['message'] ?? 'Unbekannter Fehler'}'), backgroundColor: Colors.red),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Verschieben-Dialog — reschedule an existing appointment to a new date.
  /// New appointments are always proposed in the afternoon (after 13:00).
  void _showTerminVerschiebenDialog(String type, String arztTitle) {
    String methode = '';
    final altDatumC = TextEditingController();       // original appointment date
    final altUhrzeitC = TextEditingController();     // original appointment time
    final neuDatumC = TextEditingController();       // new proposed date
    final neuUhrzeitC = TextEditingController(text: '14:00');  // default afternoon
    final betreffC = TextEditingController();
    final grundC = TextEditingController();
    final scriptC = TextEditingController();

    final methoden = {
      'telefonisch': ('Telefonisch', Icons.phone),
      'email': ('Per E-Mail', Icons.email),
      'online': ('Online', Icons.language),
      'persoenlich': ('Persoenlich', Icons.person),
      'postalisch': ('Postalisch', Icons.mail),
    };

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.event_repeat, size: 20, color: Colors.blue.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Termin verschieben \u2013 $arztTitle', style: const TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Wie wurde die Verschiebung gestellt?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: methoden.entries.map((m) {
                      final sel = methode == m.key;
                      return ChoiceChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(m.value.$2, size: 14, color: sel ? Colors.white : Colors.blue.shade700),
                          const SizedBox(width: 4),
                          Text(m.value.$1, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.blue.shade700)),
                        ]),
                        selected: sel,
                        selectedColor: Colors.blue.shade600,
                        backgroundColor: Colors.blue.shade50,
                        side: BorderSide(color: sel ? Colors.blue.shade600 : Colors.blue.shade200),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        onSelected: (_) => setDlgState(() => methode = m.key),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 14),
                  // Alter Termin (Datum)
                  TextField(
                    controller: altDatumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Alter Termin – Datum *',
                      prefixIcon: const Icon(Icons.event, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            altDatumC.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Alter Termin (Uhrzeit)
                  TextField(
                    controller: altUhrzeitC,
                    decoration: InputDecoration(
                      labelText: 'Alter Termin – Uhrzeit (z.B. 10:30)',
                      prefixIcon: const Icon(Icons.access_time, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  Divider(color: Colors.blue.shade200),
                  const SizedBox(height: 4),
                  // Neuer Termin (Datum)
                  TextField(
                    controller: neuDatumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Neuer Wunschtermin – Datum *',
                      prefixIcon: Icon(Icons.event_available, size: 18, color: Colors.blue.shade700),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.now().add(const Duration(days: 7)), firstDate: DateTime.now(), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            neuDatumC.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Neuer Termin (Uhrzeit) - nur Nachmittag (nach 13 Uhr)
                  TextField(
                    controller: neuUhrzeitC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Neuer Wunschtermin – Uhrzeit (nur Nachmittag)',
                      prefixIcon: Icon(Icons.wb_sunny, size: 18, color: Colors.orange.shade700),
                      helperText: 'Wunschtermin immer nach 13:00 Uhr',
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.schedule, size: 16),
                        onPressed: () async {
                          final picked = await showTimePicker(
                            context: dlgCtx,
                            initialTime: const TimeOfDay(hour: 14, minute: 0),
                            builder: (ctx, child) {
                              return MediaQuery(
                                data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
                                child: child!,
                              );
                            },
                          );
                          if (picked != null) {
                            // Enforce afternoon: force hour >= 13
                            final effectiveHour = picked.hour < 13 ? 13 : picked.hour;
                            neuUhrzeitC.text = '${effectiveHour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                            if (picked.hour < 13 && mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Wunschtermine nur ab 13:00 Uhr — auf 13:00 gesetzt.'), backgroundColor: Colors.orange, duration: Duration(seconds: 2)),
                              );
                            }
                          }
                        },
                      ),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Betreff
                  TextField(
                    controller: betreffC,
                    decoration: InputDecoration(
                      labelText: 'Betreff',
                      prefixIcon: const Icon(Icons.subject, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  // Grund
                  TextField(
                    controller: grundC,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Grund der Verschiebung (optional)',
                      prefixIcon: const Icon(Icons.info_outline, size: 18),
                      hintText: 'z.B. beruflich verhindert',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  // === SCRIPT ===
                  Row(children: [
                    Icon(Icons.description, size: 16, color: Colors.purple.shade700),
                    const SizedBox(width: 6),
                    Text('E-Mail Script', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                    const Spacer(),
                    TextButton.icon(
                      icon: Icon(Icons.auto_fix_high, size: 14, color: Colors.purple.shade600),
                      label: Text('Generieren', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                      style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
                      onPressed: () {
                        final arztData = _gesundheitData[type] ?? {};
                        final selArzt = arztData['selected_arzt'] as Map? ?? {};
                        final arztEmail = selArzt['email']?.toString() ?? '';
                        final arztPraxis = selArzt['praxis_name']?.toString() ?? '';
                        final patientName = widget.user.name;
                        final geb = widget.user.geburtsdatum ?? '';
                        final altDatum = altDatumC.text.isNotEmpty ? altDatumC.text : '[Datum eintragen]';
                        final altZeit = altUhrzeitC.text.isNotEmpty ? ' um ${altUhrzeitC.text} Uhr' : '';
                        final neuDatum = neuDatumC.text.isNotEmpty ? neuDatumC.text : '[Wunschtermin eintragen]';
                        final neuZeit = neuUhrzeitC.text.isNotEmpty ? ' um ${neuUhrzeitC.text} Uhr' : ' (Nachmittag)';
                        final grundTxt = grundC.text.trim();
                        final betreff = 'Terminverschiebung – $patientName, vom $altDatum';
                        betreffC.text = betreff;

                        final script = StringBuffer();
                        if (arztEmail.isNotEmpty) script.writeln('An: $arztEmail${arztPraxis.isNotEmpty ? ' ($arztPraxis)' : ''}');
                        script.writeln('Betreff: $betreff');
                        script.writeln();
                        script.writeln('Sehr geehrtes Praxisteam,');
                        script.writeln();
                        script.writeln('leider kann ich meinen Termin am $altDatum$altZeit nicht wahrnehmen${grundTxt.isNotEmpty ? ', da $grundTxt' : ''}.');
                        script.writeln();
                        script.writeln('Ich möchte den Termin gerne auf den $neuDatum$neuZeit verschieben.');
                        script.writeln();
                        script.writeln('Bitte teilen Sie mir mit, ob dieser Termin möglich ist, oder schlagen Sie einen alternativen Termin am Nachmittag (ab 13:00 Uhr) vor.');
                        script.writeln();
                        script.writeln('Angaben zum Patienten:');
                        script.writeln('Name: $patientName');
                        if (geb.isNotEmpty) script.writeln('Geburtsdatum: $geb');
                        script.writeln();
                        script.writeln('Vielen Dank für Ihr Verständnis.');
                        script.writeln();
                        script.writeln('Mit freundlichen Grüßen');
                        script.writeln(patientName);
                        script.writeln();
                        script.writeln('---');
                        script.writeln('Dieser Service wird im Rahmen der ICD360S e.V. – gemeinnützige Organisation 2025–${DateTime.now().year} bereitgestellt.');
                        setDlgState(() => scriptC.text = script.toString());
                      },
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Container(
                    decoration: BoxDecoration(border: Border.all(color: Colors.purple.shade200), borderRadius: BorderRadius.circular(8), color: Colors.purple.shade50),
                    child: TextField(
                      controller: scriptC,
                      maxLines: 12,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      decoration: InputDecoration(hintText: 'Klicken Sie auf "Generieren"...', hintStyle: TextStyle(fontSize: 11, color: Colors.purple.shade300), border: InputBorder.none, contentPadding: const EdgeInsets.all(12)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Builder(builder: (_) {
                      final ad = _gesundheitData[type] ?? {};
                      final sa = ad['selected_arzt'] as Map? ?? {};
                      final em = sa['email']?.toString() ?? '';
                      if (em.isEmpty) return const SizedBox.shrink();
                      return TextButton.icon(
                        icon: Icon(Icons.email, size: 14, color: Colors.blue.shade600),
                        label: Text('E-Mail kopieren', style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                        onPressed: () {
                          if (context.mounted) ClipboardHelper.copy(context, em, 'E-Mail');
                        },
                      );
                    }),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      icon: Icon(Icons.copy, size: 14, color: Colors.purple.shade600),
                      label: Text('Script kopieren', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                      onPressed: () {
                        if (scriptC.text.isNotEmpty) {
                          if (context.mounted) ClipboardHelper.copy(context, scriptC.text, 'Script');
                        }
                      },
                    ),
                  ]),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.event_repeat, size: 16),
              label: const Text('Verschiebung speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600),
              onPressed: () async {
                if (altDatumC.text.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte altes Termin-Datum auswählen'), backgroundColor: Colors.red));
                  return;
                }
                if (neuDatumC.text.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte neuen Wunschtermin auswählen'), backgroundColor: Colors.red));
                  return;
                }
                if (methode.isEmpty) {
                  if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Art der Anfrage auswählen'), backgroundColor: Colors.red));
                  return;
                }
                try {
                  final arztData = _gesundheitData[type] ?? {};
                  final selArzt = arztData['selected_arzt'] as Map? ?? {};
                  final arztOrt = [
                    if ((selArzt['praxis_name']?.toString() ?? '').isNotEmpty) selArzt['praxis_name'],
                    if ((selArzt['arzt_name']?.toString() ?? '').isNotEmpty) selArzt['arzt_name'],
                    if ((selArzt['strasse']?.toString() ?? '').isNotEmpty) selArzt['strasse'],
                    if ((selArzt['plz_ort']?.toString() ?? '').isNotEmpty) selArzt['plz_ort'],
                  ].join(', ');

                  // Save as new appointment entry with typ='verschoben'
                  final result = await widget.apiService.saveArztTermin({
                    'action': 'add',
                    'user_id': widget.user.id,
                    'arzt_type': type,
                    'datum': neuDatumC.text,
                    'uhrzeit': neuUhrzeitC.text.trim(),
                    'typ': 'verschoben',
                    'anfrage_methode': methode,
                    'diagnose': betreffC.text.trim(),
                    'notizen': [
                      'Alter Termin: ${altDatumC.text}${altUhrzeitC.text.isNotEmpty ? ' um ${altUhrzeitC.text}' : ''}',
                      if (grundC.text.trim().isNotEmpty) 'Grund: ${grundC.text.trim()}',
                    ].join('\n'),
                    'arzt_ort': arztOrt,
                  });
                  if (result['success'] == true) {
                    if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                    if (mounted) {
                      _arztTermine.remove(type);
                      _loadArztTermine(type);

                      // Auto-create ticket for Verschiebung
                      try {
                        final praxisName = selArzt['praxis_name']?.toString() ?? selArzt['arzt_name']?.toString() ?? arztTitle;
                        final patientName = widget.user.name;
                        final ticketSubject = 'Arzt-Verschiebung: $arztTitle — $patientName';
                        final ticketMsg = [
                          'Arzt: $praxisName ($arztTitle)',
                          'Patient: $patientName (${widget.user.mitgliedernummer})',
                          'Alter Termin: ${altDatumC.text}${altUhrzeitC.text.isNotEmpty ? ' um ${altUhrzeitC.text}' : ''}',
                          'Neuer Wunschtermin: ${neuDatumC.text}${neuUhrzeitC.text.isNotEmpty ? ' um ${neuUhrzeitC.text}' : ''} (Nachmittag)',
                          'Methode: $methode',
                          if (betreffC.text.isNotEmpty) 'Betreff: ${betreffC.text}',
                          if (grundC.text.isNotEmpty) 'Grund: ${grundC.text}',
                          '',
                          'Automatisch erstellt aus Terminverschiebung.',
                        ].join('\n');

                        await widget.ticketService.createTicket(
                          mitgliedernummer: widget.user.mitgliedernummer,
                          subject: ticketSubject,
                          message: ticketMsg,
                          priority: 'medium',
                          systemTicket: true,
                          scheduledDate: neuDatumC.text,
                        );
                      } catch (e) {
                        debugPrint('[Gesundheit] Ticket create error: $e');
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Terminverschiebung gespeichert + Ticket erstellt'), backgroundColor: Colors.green),
                        );
                      }
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Fehler: ${result['message'] ?? 'Unbekannter Fehler'}'), backgroundColor: Colors.red),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showArztTerminDialog(String type, String arztTitle, Map<String, dynamic>? existing) async {
    final isEdit = existing != null;
    final datumController = TextEditingController(text: existing?['datum'] ?? '');
    final uhrzeitController = TextEditingController(text: existing?['uhrzeit'] ?? '');
    final diagnoseController = TextEditingController(text: existing?['diagnose'] ?? '');
    final notizenController = TextEditingController(text: existing?['notizen'] ?? '');
    String typ = existing?['typ'] ?? 'normal';
    bool saving = false;

    // Get online termin URL from selected arzt
    final activeData = _gesundheitData[type] ?? {};
    Map<String, dynamic> selArzt = {};
    final rawArzt = activeData['selected_arzt'];
    if (rawArzt is Map) {
      selArzt = Map<String, dynamic>.from(rawArzt);
    } else if (rawArzt is String && rawArzt.isNotEmpty) {
      try { selArzt = Map<String, dynamic>.from(jsonDecode(rawArzt)); } catch (_) {}
    }
    final hasArzt = selArzt.isNotEmpty || (activeData['arzt_name']?.toString() ?? '').isNotEmpty || (activeData['behandelnder_arzt']?.toString() ?? '').isNotEmpty;
    String onlineTerminUrl = selArzt['online_termin_url']?.toString() ?? '';

    // If URL missing but arzt_id exists, refresh from central DB
    final arztId = activeData['arzt_id']?.toString();
    if (onlineTerminUrl.isEmpty && arztId != null && arztId.isNotEmpty) {
      try {
        final result = await widget.apiService.searchAerzte(search: selArzt['arzt_name']?.toString() ?? selArzt['praxis_name']?.toString() ?? '');
        final aerzte = result['aerzte'] as List? ?? [];
        for (final a in aerzte) {
          if (a['id'].toString() == arztId && (a['online_termin_url']?.toString() ?? '').isNotEmpty) {
            selArzt = Map<String, dynamic>.from(a as Map);
            activeData['selected_arzt'] = selArzt;
            _gesundheitData[type] = activeData;
            widget.apiService.saveGesundheitData(widget.user.id, type, activeData);
            onlineTerminUrl = selArzt['online_termin_url']?.toString() ?? '';
            break;
          }
        }
      } catch (_) {}
    }

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(isEdit ? Icons.edit_calendar : Icons.add_circle, color: Colors.teal.shade700, size: 22),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'Termin bearbeiten' : 'Neuer Termin bei $arztTitle', style: const TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Online Termin link — always show when doctor is selected
                      if (hasArzt && !isEdit)
                        Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: onlineTerminUrl.isNotEmpty
                            ? InkWell(
                                onTap: () {
                                  Navigator.pop(ctx);
                                  Navigator.push(context, MaterialPageRoute(
                                    builder: (_) {
                                      final geb = widget.user.geburtsdatum;
                                      String gebTag = '', gebMonat = '', gebJahr = '';
                                      if (geb != null) {
                                        final parts = geb.toString().split(RegExp(r'[-./]'));
                                        if (parts.length == 3) {
                                          if (parts[0].length == 4) { gebJahr = parts[0]; gebMonat = parts[1]; gebTag = parts[2]; }
                                          else { gebTag = parts[0]; gebMonat = parts[1]; gebJahr = parts[2]; }
                                        }
                                      }
                                      return WebViewScreen(
                                        title: 'Online Termin — $arztTitle',
                                        url: onlineTerminUrl,
                                        go2docAutoFill: {
                                          'vorname': widget.user.vorname ?? '',
                                          'nachname': widget.user.nachname ?? '',
                                          'geb_tag': gebTag,
                                          'geb_monat': gebMonat,
                                          'geb_jahr': gebJahr,
                                          'email': 'icd@icd360s.de',
                                          'versicherung': 'gesetzlich',
                                        },
                                      );
                                    },
                                  ));
                                },
                                child: Row(children: [
                                  Icon(Icons.language, size: 20, color: Colors.blue.shade700),
                                  const SizedBox(width: 8),
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Text('Online Termin buchen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                    Text('Direkt beim Arzt online einen Termin vereinbaren', style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                                  ])),
                                  Icon(Icons.open_in_new, size: 16, color: Colors.blue.shade700),
                                ]),
                              )
                            : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Icon(Icons.language, size: 20, color: Colors.grey.shade500),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text('Online Termin — Link fehlt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700))),
                                ]),
                                const SizedBox(height: 6),
                                Text('Bitte die URL für Online-Terminbuchung eintragen:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                const SizedBox(height: 6),
                                Row(children: [
                                  Expanded(child: TextField(
                                    decoration: InputDecoration(hintText: 'https://...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)), contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8)),
                                    style: const TextStyle(fontSize: 12),
                                    onSubmitted: (url) {
                                      if (url.trim().isNotEmpty) {
                                        selArzt['online_termin_url'] = url.trim();
                                        activeData['selected_arzt'] = selArzt;
                                        _saveGesundheitData(type, activeData);
                                        setDialogState(() {});
                                      }
                                    },
                                  )),
                                  const SizedBox(width: 6),
                                  IconButton(icon: Icon(Icons.save, size: 18, color: Colors.teal.shade600), tooltip: 'Speichern', onPressed: () {}),
                                ]),
                              ]),
                        ),
                      // Typ selection
                      Text('Art des Termins', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => typ = 'normal'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: typ == 'normal' ? Colors.teal.shade50 : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: typ == 'normal' ? Colors.teal.shade400 : Colors.grey.shade300, width: typ == 'normal' ? 2 : 1),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.calendar_today, size: 18, color: typ == 'normal' ? Colors.teal.shade700 : Colors.grey.shade500),
                                    const SizedBox(width: 6),
                                    Text('Normaler Termin', style: TextStyle(fontWeight: typ == 'normal' ? FontWeight.bold : FontWeight.normal, color: typ == 'normal' ? Colors.teal.shade700 : Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setDialogState(() => typ = 'notfall'),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                decoration: BoxDecoration(
                                  color: typ == 'notfall' ? Colors.red.shade50 : Colors.grey.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: typ == 'notfall' ? Colors.red.shade400 : Colors.grey.shade300, width: typ == 'notfall' ? 2 : 1),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.emergency, size: 18, color: typ == 'notfall' ? Colors.red.shade700 : Colors.grey.shade500),
                                    const SizedBox(width: 6),
                                    Text('Notfall', style: TextStyle(fontWeight: typ == 'notfall' ? FontWeight.bold : FontWeight.normal, color: typ == 'notfall' ? Colors.red.shade700 : Colors.grey.shade600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      // Datum + Uhrzeit
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: datumController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Datum *',
                                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.edit_calendar, size: 18),
                                  onPressed: () async {
                                    final picked = await showDatePicker(
                                      context: ctx,
                                      initialDate: DateTime.now(),
                                      firstDate: DateTime(2020),
                                      lastDate: DateTime(2099),
                                      locale: const Locale('de'),
                                    );
                                    if (picked != null) {
                                      datumController.text = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: uhrzeitController,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Uhrzeit',
                                prefixIcon: const Icon(Icons.access_time, size: 18),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.schedule, size: 18),
                                  onPressed: () async {
                                    final picked = await showTimePicker(
                                      context: ctx,
                                      initialTime: TimeOfDay.now(),
                                    );
                                    if (picked != null) {
                                      uhrzeitController.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                    }
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: diagnoseController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Diagnose / Grund',
                          prefixIcon: Icon(Icons.description, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'Grund des Besuchs...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notizenController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notizen',
                          prefixIcon: Icon(Icons.note, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'Zusätzliche Informationen...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Abbrechen'),
                ),
                ElevatedButton.icon(
                  onPressed: saving ? null : () async {
                    if (datumController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Datum ist erforderlich'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    setDialogState(() => saving = true);
                    try {
                      // Build arzt location for Terminverwaltung
                      final arztData = _gesundheitData[type] ?? {};
                      final selArzt = arztData['selected_arzt'] as Map? ?? {};
                      final arztOrt = [
                        if ((selArzt['praxis_name']?.toString() ?? '').isNotEmpty) selArzt['praxis_name'],
                        if ((selArzt['arzt_name']?.toString() ?? '').isNotEmpty) selArzt['arzt_name'],
                        if ((selArzt['strasse']?.toString() ?? '').isNotEmpty) selArzt['strasse'],
                        if ((selArzt['plz_ort']?.toString() ?? '').isNotEmpty) selArzt['plz_ort'],
                      ].join(', ');

                      await widget.apiService.saveArztTermin({
                        'action': isEdit ? 'update' : 'add',
                        'user_id': widget.user.id,
                        'arzt_type': type,
                        if (isEdit) 'termin_id': existing['id'],
                        'datum': datumController.text.trim(),
                        'uhrzeit': uhrzeitController.text.trim(),
                        'typ': typ,
                        'diagnose': diagnoseController.text.trim(),
                        'notizen': notizenController.text.trim(),
                        'arzt_ort': arztOrt,
                      });
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      if (mounted) {
                        _arztTermine.remove(type);
                        _loadArztTermine(type);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isEdit ? 'Termin aktualisiert' : 'Termin gespeichert'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (ctx.mounted) setDialogState(() => saving = false);
                    }
                  },
                  icon: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(isEdit ? Icons.save : Icons.add, size: 18),
                  label: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ========== ARZT MEDIKAMENTE TAB (DB-based) ==========

  final Map<String, List<Map<String, dynamic>>> _arztMedikamente = {};
  final Map<String, bool> _arztMedikamenteLoading = {};

  Future<void> _loadArztMedikamente(String type) async {
    if (_arztMedikamenteLoading[type] == true) return;
    _arztMedikamenteLoading[type] = true;
    try {
      final result = await widget.apiService.getArztMedikamente(widget.user.id, type);
      if (mounted) {
        setState(() {
          _arztMedikamente[type] = List<Map<String, dynamic>>.from(result['medikamente'] ?? []);
          _arztMedikamenteLoading[type] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _arztMedikamenteLoading[type] = false;
          _arztMedikamente[type] = [];
        });
      }
    }
  }

  // Bericht docs cache
  final Map<String, List<Map<String, dynamic>>> _berichtDocs = {};
  final Map<String, bool> _berichtDocsLoading = {};

  Widget _buildBerichtDokumente(String type, String berichtId, StateSetter setBerichtState) {
    final key = '${type}_$berichtId';
    // Lazy load docs
    if (!_berichtDocs.containsKey(key) && _berichtDocsLoading[key] != true) {
      _berichtDocsLoading[key] = true;
      widget.apiService.listGesundheitDocs(userId: widget.user.id, gesundheitType: type, analyseId: berichtId).then((result) {
        if (mounted) {
          setState(() {
            _berichtDocs[key] = List<Map<String, dynamic>>.from(result['dokumente'] ?? []);
            _berichtDocsLoading[key] = false;
          });
        }
      });
    }
    final docs = _berichtDocs[key] ?? [];
    final isLoading = _berichtDocsLoading[key] == true;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.attach_file, size: 14, color: Colors.indigo.shade600),
            const SizedBox(width: 4),
            Text('Dokumente (${docs.length})', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade600)),
            const Spacer(),
            InkWell(
              onTap: () async {
                final result = await FilePicker.platform.pickFiles(type: FileType.any, allowMultiple: true);
                if (result == null || result.files.isEmpty || !mounted) return;
                for (final f in result.files) {
                  if (f.path == null) continue;
                  try {
                    await widget.apiService.uploadGesundheitDoc(
                      userId: widget.user.id,
                      gesundheitType: type,
                      analyseId: berichtId,
                      filePath: f.path!,
                      fileName: f.name,
                    );
                  } catch (_) {}
                }
                // Reload docs
                _berichtDocs.remove(key);
                _berichtDocsLoading.remove(key);
                if (mounted) setState(() {});
                setBerichtState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.indigo.shade200)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.upload_file, size: 12, color: Colors.indigo.shade600),
                  const SizedBox(width: 4),
                  Text('Hochladen', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ]),
          if (isLoading)
            const Padding(padding: EdgeInsets.all(8), child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))))
          else if (docs.isNotEmpty) ...[
            const SizedBox(height: 6),
            ...docs.map((doc) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: InkWell(
                onTap: () async {
                  try {
                    final response = await widget.apiService.downloadGesundheitDokument(doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString()));
                    if (response.statusCode == 200) {
                      final dir = await getTemporaryDirectory();
                      final file = File('${dir.path}/${doc['original_name'] ?? 'dokument'}');
                      await file.writeAsBytes(response.bodyBytes);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${doc['original_name']} heruntergeladen'), backgroundColor: Colors.green));
                      }
                    }
                  } catch (_) {}
                },
                child: Row(children: [
                  Icon(
                    (doc['original_name']?.toString() ?? '').endsWith('.pdf') ? Icons.picture_as_pdf : Icons.insert_drive_file,
                    size: 14,
                    color: (doc['original_name']?.toString() ?? '').endsWith('.pdf') ? Colors.red.shade400 : Colors.blue.shade400,
                  ),
                  const SizedBox(width: 6),
                  Expanded(child: Text(doc['original_name']?.toString() ?? 'Dokument', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  Text(doc['created_at']?.toString().substring(0, 10) ?? '', style: TextStyle(fontSize: 9, color: Colors.grey.shade400)),
                  const SizedBox(width: 4),
                  InkWell(
                    onTap: () async {
                      try {
                        await widget.apiService.deleteGesundheitDokument(doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString()));
                        _berichtDocs.remove(key);
                        _berichtDocsLoading.remove(key);
                        if (mounted) setState(() {});
                        setBerichtState(() {});
                      } catch (_) {}
                    },
                    child: Icon(Icons.close, size: 12, color: Colors.red.shade300),
                  ),
                ]),
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildArztMedikamenteTab(String type, String arztTitle) {
    if (!_arztMedikamente.containsKey(type) && _arztMedikamenteLoading[type] != true) {
      _loadArztMedikamente(type);
    }
    if (_arztMedikamenteLoading[type] == true) {
      return const Center(child: CircularProgressIndicator());
    }

    final medikamente = _arztMedikamente[type] ?? [];

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              Icon(Icons.medication, size: 20, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Text('Medikamente von $arztTitle', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
              const Spacer(),
              if (medikamente.isNotEmpty)
                ElevatedButton.icon(
                  onPressed: () => _generateMedikamentenPlan(type, arztTitle, medikamente),
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('PDF'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                ),
              if (medikamente.isNotEmpty) const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => _showMedikamentDialog(type, arztTitle, null),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neues Medikament'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
        ),
        // Legend
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _dosisLegend(Icons.wb_sunny_outlined, 'Morgens', Colors.orange.shade700),
              const SizedBox(width: 12),
              _dosisLegend(Icons.wb_sunny, 'Mittags', Colors.amber.shade700),
              const SizedBox(width: 12),
              _dosisLegend(Icons.nights_stay_outlined, 'Abends', Colors.indigo.shade400),
              const SizedBox(width: 12),
              _dosisLegend(Icons.dark_mode, 'Nachts', Colors.indigo.shade800),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Divider(height: 1),
        Expanded(
          child: medikamente.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.medication_outlined, size: 48, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Keine Medikamente eingetragen', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(12),
                  itemCount: medikamente.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final m = medikamente[index];
                    final morgensVal = double.tryParse(m['morgens']?.toString() ?? '0') ?? 0;
                    final mittagsVal = double.tryParse(m['mittags']?.toString() ?? '0') ?? 0;
                    final abendsVal = double.tryParse(m['abends']?.toString() ?? '0') ?? 0;
                    final nachtsVal = double.tryParse(m['nachts']?.toString() ?? '0') ?? 0;
                    return Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.teal.shade100,
                          child: Icon(Icons.medication, color: Colors.teal.shade700, size: 20),
                        ),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(m['medikament_name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            ),
                            if (m['dosis']?.isNotEmpty == true)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.purple.shade200)),
                                child: Text(m['dosis'], style: TextStyle(fontSize: 11, color: Colors.purple.shade700, fontWeight: FontWeight.bold)),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  _dosisChip(Icons.wb_sunny_outlined, 'Morgens', morgensVal, Colors.orange),
                                  const SizedBox(width: 6),
                                  _dosisChip(Icons.wb_sunny, 'Mittags', mittagsVal, Colors.amber),
                                  const SizedBox(width: 6),
                                  _dosisChip(Icons.nights_stay_outlined, 'Abends', abendsVal, Colors.indigo.shade300),
                                  const SizedBox(width: 6),
                                  _dosisChip(Icons.dark_mode, 'Nachts', nachtsVal, Colors.indigo.shade700),
                                ],
                              ),
                              if (m['einnahmehinweis']?.toString().isNotEmpty == true && m['einnahmehinweis'] != null) ...[
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Row(
                                    children: [
                                      Icon(Icons.restaurant_menu, size: 13, color: Colors.teal.shade400),
                                      const SizedBox(width: 4),
                                      Text(_einnahmehinweisLabel(m['einnahmehinweis'].toString()), style: TextStyle(fontSize: 11, color: Colors.teal.shade700, fontWeight: FontWeight.w500)),
                                    ],
                                  ),
                                ),
                              ],
                              if (m['notizen']?.isNotEmpty == true)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(m['notizen'], style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                                ),
                            ],
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Icon(Icons.edit, size: 18, color: Colors.teal.shade600),
                              tooltip: 'Bearbeiten',
                              onPressed: () => _showMedikamentDialog(type, arztTitle, m),
                            ),
                            IconButton(
                              icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                              tooltip: 'Löschen',
                              onPressed: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: const Text('Medikament löschen?'),
                                    content: Text('${m['medikament_name']} wirklich löschen?'),
                                    actions: [
                                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                      TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await widget.apiService.saveArztMedikament({
                                    'action': 'delete',
                                    'user_id': widget.user.id,
                                    'arzt_type': type,
                                    'medikament_id': m['id'],
                                  });
                                  _arztMedikamente.remove(type);
                                  _loadArztMedikamente(type);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _dosisChip(IconData icon, String label, double anzahl, Color color) {
    final active = anzahl > 0;
    final display = anzahl == anzahl.toInt() ? anzahl.toInt().toString() : anzahl.toString();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: active ? color.withValues(alpha: 0.15) : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: active ? color : Colors.grey.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: active ? color : Colors.grey.shade400),
          const SizedBox(width: 3),
          Text(active ? '$display x $label' : label, style: TextStyle(fontSize: 10, color: active ? color : Colors.grey.shade400, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  String _einnahmehinweisLabel(String val) {
    const labels = {
      'nüchtern': 'Nüchtern (auf leeren Magen)',
      'vor_essen': 'Vor dem Essen (30-60 Min.)',
      'zum_essen': 'Zum Essen',
      'nach_essen': 'Nach dem Essen (1-2h)',
      'unabhaengig': 'Unabhängig von Mahlzeiten',
      'mit_wasser': 'Mit viel Wasser (mind. 200ml)',
      'nicht_zerkauen': 'Nicht zerkauen/teilen',
    };
    if (val.startsWith('custom:')) return val.substring(7);
    return labels[val] ?? val;
  }

  Widget _dosisLegend(IconData icon, String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: color)),
      ],
    );
  }

  void _showMedikamentDialog(String type, String arztTitle, Map<String, dynamic>? existing) {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?['medikament_name'] ?? '');
    final dosisController = TextEditingController(text: existing?['dosis'] ?? '');
    final notizenController = TextEditingController(text: existing?['notizen'] ?? '');
    // Einnahmehinweis
    String einnahmehinweis = existing?['einnahmehinweis']?.toString() ?? '';
    final einnahmeCustomController = TextEditingController(
      text: einnahmehinweis.startsWith('custom:') ? einnahmehinweis.substring(7) : '',
    );
    if (einnahmehinweis.startsWith('custom:')) einnahmehinweis = 'custom';
    // Anzahl Tabletten per Tageszeit (0 = keine Einnahme, >0 = Anzahl)
    String parseAnzahl(dynamic val) {
      if (val == null) return '';
      final s = val.toString();
      if (s == '0' || s == 'false' || s.isEmpty) return '';
      if (s == '1' || s == 'true') return '1';
      return s; // keep existing numeric value like "2", "0.5"
    }
    final morgensController = TextEditingController(text: parseAnzahl(existing?['morgens']));
    final mittagsController = TextEditingController(text: parseAnzahl(existing?['mittags']));
    final abendsController = TextEditingController(text: parseAnzahl(existing?['abends']));
    final nachtsController = TextEditingController(text: parseAnzahl(existing?['nachts']));
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.medication, color: Colors.teal.shade700, size: 22),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'Medikament bearbeiten' : 'Neues Medikament', style: const TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 450,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Medikament-Name *',
                          prefixIcon: Icon(Icons.medication, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'z.B. Ibuprofen, Metformin...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: dosisController,
                        decoration: const InputDecoration(
                          labelText: 'Dosis',
                          prefixIcon: Icon(Icons.science, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'z.B. 400mg, 2 Tabletten...',
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text('Einnahmehinweis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue: einnahmehinweis.isEmpty ? null : einnahmehinweis,
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.restaurant_menu, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'Wann einnehmen?',
                        ),
                        items: const [
                          DropdownMenuItem(value: 'nüchtern', child: Text('Nüchtern (auf leeren Magen, 1h vor Essen)')),
                          DropdownMenuItem(value: 'vor_essen', child: Text('Vor dem Essen (30-60 Min. vorher)')),
                          DropdownMenuItem(value: 'zum_essen', child: Text('Zum Essen (während der Mahlzeit)')),
                          DropdownMenuItem(value: 'nach_essen', child: Text('Nach dem Essen (1-2h danach)')),
                          DropdownMenuItem(value: 'unabhaengig', child: Text('Unabhängig von Mahlzeiten')),
                          DropdownMenuItem(value: 'mit_wasser', child: Text('Mit viel Wasser (mind. 200ml)')),
                          DropdownMenuItem(value: 'nicht_zerkauen', child: Text('Nicht zerkauen/teilen (ganz schlucken)')),
                          DropdownMenuItem(value: 'custom', child: Text('Sonstiges (eigener Hinweis)...')),
                        ],
                        onChanged: (val) {
                          setDialogState(() => einnahmehinweis = val ?? '');
                        },
                      ),
                      if (einnahmehinweis == 'custom') ...[
                        const SizedBox(height: 8),
                        TextField(
                          controller: einnahmeCustomController,
                          decoration: const InputDecoration(
                            labelText: 'Eigener Einnahmehinweis',
                            prefixIcon: Icon(Icons.edit_note, size: 18),
                            border: OutlineInputBorder(),
                            isDense: true,
                            hintText: 'z.B. 15 Min. Abstand zwischen Medikamenten...',
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text('Anzahl Tabletten pro Tageszeit', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Text('Leer oder 0 = keine Einnahme', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: morgensController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Morgens',
                                prefixIcon: Icon(Icons.wb_sunny_outlined, size: 18, color: Colors.orange.shade700),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintText: '0',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: mittagsController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Mittags',
                                prefixIcon: Icon(Icons.wb_sunny, size: 18, color: Colors.amber.shade700),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintText: '0',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: abendsController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Abends',
                                prefixIcon: Icon(Icons.nights_stay_outlined, size: 18, color: Colors.indigo.shade400),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintText: '0',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: nachtsController,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: InputDecoration(
                                labelText: 'Nachts',
                                prefixIcon: Icon(Icons.dark_mode, size: 18, color: Colors.indigo.shade800),
                                border: const OutlineInputBorder(),
                                isDense: true,
                                hintText: '0',
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: notizenController,
                        maxLines: 3,
                        decoration: const InputDecoration(
                          labelText: 'Notizen',
                          prefixIcon: Icon(Icons.note, size: 18),
                          border: OutlineInputBorder(),
                          isDense: true,
                          hintText: 'Zusätzliche Hinweise...',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton.icon(
                  onPressed: saving ? null : () async {
                    if (nameController.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Medikament-Name ist erforderlich'), backgroundColor: Colors.red),
                      );
                      return;
                    }
                    setDialogState(() => saving = true);
                    try {
                      await widget.apiService.saveArztMedikament({
                        'action': isEdit ? 'update' : 'add',
                        'user_id': widget.user.id,
                        'arzt_type': type,
                        if (isEdit) 'medikament_id': existing['id'],
                        'medikament_name': nameController.text.trim(),
                        'dosis': dosisController.text.trim(),
                        'morgens': morgensController.text.trim().isEmpty ? '0' : morgensController.text.trim(),
                        'mittags': mittagsController.text.trim().isEmpty ? '0' : mittagsController.text.trim(),
                        'abends': abendsController.text.trim().isEmpty ? '0' : abendsController.text.trim(),
                        'nachts': nachtsController.text.trim().isEmpty ? '0' : nachtsController.text.trim(),
                        'einnahmehinweis': einnahmehinweis == 'custom'
                            ? 'custom:${einnahmeCustomController.text.trim()}'
                            : einnahmehinweis,
                        'notizen': notizenController.text.trim(),
                      });
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (mounted) {
                        _arztMedikamente.remove(type);
                        _loadArztMedikamente(type);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(isEdit ? 'Medikament aktualisiert' : 'Medikament gespeichert'), backgroundColor: Colors.green),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                        );
                      }
                    } finally {
                      if (ctx.mounted) setDialogState(() => saving = false);
                    }
                  },
                  icon: saving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Icon(isEdit ? Icons.save : Icons.add, size: 18),
                  label: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, foregroundColor: Colors.white),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _generateMedikamentenPlan(String type, String arztTitle, List<Map<String, dynamic>> medikamente) async {
    final user = widget.user;
    final userName = '${user.vorname ?? ''} ${user.nachname ?? ''}'.trim();
    final now = DateFormat('dd.MM.yyyy', 'de').format(DateTime.now());

    // Load Verein data
    Map<String, dynamic> vereinData = {};
    try {
      final result = await widget.apiService.getVereineinstellungen();
      if (result['success'] == true && result['data'] != null) {
        vereinData = Map<String, dynamic>.from(result['data']);
      }
    } catch (_) {}

    // Load doctor data
    final arztData = _gesundheitData[type] ?? {};
    final selectedArzt = arztData['selected_arzt'] != null
        ? Map<String, dynamic>.from(arztData['selected_arzt'])
        : <String, dynamic>{};
    final behandelnderArzt = arztData['behandelnder_arzt'] ?? '';

    final vereinName = vereinData['vereinsname'] ?? 'ICD360S e.V.';
    final vereinAdresse = vereinData['adresse'] ?? '';
    final vereinTelefon = (vereinData['telefon_fix'] ?? '').toString().replaceAll(RegExp(r'[^\d+\-\s/()]'), '');
    final vereinEmail = vereinData['email'] ?? '';
    final vereinRegNr = vereinData['registernummer'] ?? '';

    // Colors (no Google Fonts — only built-in Helvetica)
    final teal = PdfColor.fromHex('#00796B');
    final tealLight = PdfColor.fromHex('#E0F2F1');
    final tealDark = PdfColor.fromHex('#004D40');
    final bgLight = PdfColor.fromHex('#FAFAFA');

    final pdf = pw.Document();

    // Styles
    final titleStyle = pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold, color: PdfColors.white);
    final subtitleStyle = pw.TextStyle(fontSize: 11, color: PdfColor.fromHex('#B2DFDB'));
    final sectionStyle = pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: teal);
    final labelStyle = pw.TextStyle(fontSize: 8, color: PdfColors.grey600);
    final valueStyle = pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold);
    final smallStyle = pw.TextStyle(fontSize: 7, color: PdfColors.grey500);

    // Info row helper — compact, text wraps
    pw.Widget infoRow(String label, String value) {
      final cleanVal = value.trim();
      if (cleanVal.isEmpty || cleanVal == ',' || cleanVal == ', ') return pw.SizedBox();
      return pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 55, child: pw.Text(label, style: labelStyle)),
            pw.Expanded(child: pw.Text(cleanVal, style: valueStyle, maxLines: 2, overflow: pw.TextOverflow.clip)),
          ],
        ),
      );
    }

    // Pictograms drawn with CustomPaint — real sunrise/sun/sunset/moon
    // Morgens = Sunrise (half sun + rays above horizon)
    pw.Widget morgensPicto() {
      return pw.Container(
        width: 22, height: 22,
        child: pw.CustomPaint(
          size: const PdfPoint(22, 22),
          painter: (PdfGraphics canvas, PdfPoint size) {
            // PDF coords: 0,0 = bottom-left
            final cx = size.x / 2;
            final horizonY = 6.0; // horizon near bottom
            // Horizon line
            canvas.setColor(PdfColor.fromHex('#FF8F00'));
            canvas.drawRect(1, horizonY - 0.4, size.x - 2, 0.8);
            canvas.fillPath();
            // Half sun above horizon
            canvas.setColor(PdfColor.fromHex('#FF8F00'));
            canvas.drawEllipse(cx, horizonY, 5, 5);
            canvas.fillPath();
            // White rect to hide bottom half
            canvas.setColor(PdfColors.white);
            canvas.drawRect(0, 0, size.x, horizonY);
            canvas.fillPath();
            // Redraw horizon
            canvas.setColor(PdfColor.fromHex('#FF8F00'));
            canvas.drawRect(1, horizonY - 0.4, size.x - 2, 0.8);
            canvas.fillPath();
            // 5 rays above horizon
            for (var i = 0; i < 5; i++) {
              final angle = (30 + i * 30) * math.pi / 180; // 30° to 150°
              final x1 = cx + 6.5 * math.cos(angle);
              final y1 = horizonY + 6.5 * math.sin(angle);
              final x2 = cx + 9.5 * math.cos(angle);
              final y2 = horizonY + 9.5 * math.sin(angle);
              canvas.setColor(PdfColor.fromHex('#FF8F00'));
              canvas.setLineWidth(1.0);
              canvas.moveTo(x1, y1);
              canvas.lineTo(x2, y2);
              canvas.strokePath();
            }
          },
        ),
      );
    }

    // Mittags = Full sun with 8 rays
    pw.Widget mittagsPicto() {
      return pw.Container(
        width: 22, height: 22,
        child: pw.CustomPaint(
          size: const PdfPoint(22, 22),
          painter: (PdfGraphics canvas, PdfPoint size) {
            final cx = size.x / 2;
            final cy = size.y / 2;
            // Sun circle
            canvas.setColor(PdfColor.fromHex('#F9A825'));
            canvas.drawEllipse(cx, cy, 4.5, 4.5);
            canvas.fillPath();
            // 8 rays
            for (var i = 0; i < 8; i++) {
              final angle = i * math.pi / 4;
              final x1 = cx + 6.0 * math.cos(angle);
              final y1 = cy + 6.0 * math.sin(angle);
              final x2 = cx + 9.0 * math.cos(angle);
              final y2 = cy + 9.0 * math.sin(angle);
              canvas.setColor(PdfColor.fromHex('#F9A825'));
              canvas.setLineWidth(1.2);
              canvas.moveTo(x1, y1);
              canvas.lineTo(x2, y2);
              canvas.strokePath();
            }
          },
        ),
      );
    }

    // Abends = Sunset (small sun going below horizon, fewer rays)
    pw.Widget abendsPicto() {
      return pw.Container(
        width: 22, height: 22,
        child: pw.CustomPaint(
          size: const PdfPoint(22, 22),
          painter: (PdfGraphics canvas, PdfPoint size) {
            final cx = size.x / 2;
            final horizonY = 8.0;
            // Horizon line
            canvas.setColor(PdfColor.fromHex('#E65100'));
            canvas.drawRect(1, horizonY - 0.4, size.x - 2, 0.8);
            canvas.fillPath();
            // Small sun barely peeking
            canvas.setColor(PdfColor.fromHex('#E65100'));
            canvas.drawEllipse(cx, horizonY, 3.5, 3.5);
            canvas.fillPath();
            // White to hide bottom
            canvas.setColor(PdfColors.white);
            canvas.drawRect(0, 0, size.x, horizonY);
            canvas.fillPath();
            // Redraw horizon
            canvas.setColor(PdfColor.fromHex('#E65100'));
            canvas.drawRect(1, horizonY - 0.4, size.x - 2, 0.8);
            canvas.fillPath();
            // 3 short rays
            for (var i = 0; i < 3; i++) {
              final angle = (50 + i * 40) * math.pi / 180;
              final x1 = cx + 5.0 * math.cos(angle);
              final y1 = horizonY + 5.0 * math.sin(angle);
              final x2 = cx + 7.5 * math.cos(angle);
              final y2 = horizonY + 7.5 * math.sin(angle);
              canvas.setColor(PdfColor.fromHex('#E65100'));
              canvas.setLineWidth(0.9);
              canvas.moveTo(x1, y1);
              canvas.lineTo(x2, y2);
              canvas.strokePath();
            }
            // Down arrow hint
            canvas.setColor(PdfColor.fromHex('#E65100'));
            canvas.setLineWidth(0.8);
            canvas.moveTo(cx, horizonY - 1);
            canvas.lineTo(cx, horizonY - 4);
            canvas.strokePath();
            canvas.moveTo(cx - 1.5, horizonY - 2.5);
            canvas.lineTo(cx, horizonY - 1);
            canvas.lineTo(cx + 1.5, horizonY - 2.5);
            canvas.strokePath();
          },
        ),
      );
    }

    // Nachts = Crescent moon + star
    pw.Widget nachtsPicto() {
      return pw.Container(
        width: 22, height: 22,
        child: pw.CustomPaint(
          size: const PdfPoint(22, 22),
          painter: (PdfGraphics canvas, PdfPoint size) {
            final cx = size.x / 2;
            final cy = size.y / 2;
            // Full moon
            canvas.setColor(PdfColor.fromHex('#1A237E'));
            canvas.drawEllipse(cx - 1, cy, 6.5, 6.5);
            canvas.fillPath();
            // Cut-out for crescent
            canvas.setColor(PdfColors.white);
            canvas.drawEllipse(cx + 2, cy + 1.5, 5, 5);
            canvas.fillPath();
            // Small star top-right
            canvas.setColor(PdfColor.fromHex('#FFC107'));
            canvas.drawEllipse(cx + 6, cy + 5, 1.2, 1.2);
            canvas.fillPath();
            // Tiny star
            canvas.setColor(PdfColor.fromHex('#FFC107'));
            canvas.drawEllipse(cx + 3.5, cy + 7.5, 0.7, 0.7);
            canvas.fillPath();
          },
        ),
      );
    }

    // Fork + Spoon icon (restaurant style)
    pw.Widget besteckPicto({double size = 14}) {
      return pw.Container(
        width: size, height: size,
        child: pw.CustomPaint(
          size: PdfPoint(size, size),
          painter: (PdfGraphics canvas, PdfPoint s) {
            final col = PdfColor.fromHex('#5D4037'); // brown
            canvas.setColor(col);
            // Fork (left) — 3 prongs + handle
            canvas.setLineWidth(0.7);
            final fx = s.x * 0.25;
            // Prongs
            canvas.moveTo(fx - 2, s.y * 0.95);
            canvas.lineTo(fx - 2, s.y * 0.6);
            canvas.strokePath();
            canvas.moveTo(fx, s.y * 0.95);
            canvas.lineTo(fx, s.y * 0.6);
            canvas.strokePath();
            canvas.moveTo(fx + 2, s.y * 0.95);
            canvas.lineTo(fx + 2, s.y * 0.6);
            canvas.strokePath();
            // Fork base
            canvas.setLineWidth(1.0);
            canvas.moveTo(fx, s.y * 0.6);
            canvas.lineTo(fx, s.y * 0.05);
            canvas.strokePath();
            // Spoon (right) — oval head + handle
            final sx = s.x * 0.75;
            canvas.drawEllipse(sx, s.y * 0.8, 2.5, 3.5);
            canvas.fillPath();
            canvas.setLineWidth(1.0);
            canvas.moveTo(sx, s.y * 0.8 - 3.5);
            canvas.lineTo(sx, s.y * 0.05);
            canvas.strokePath();
          },
        ),
      );
    }

    // Pill icon
    pw.Widget pillPicto({double size = 10}) {
      return pw.Container(
        width: size * 1.6, height: size,
        child: pw.CustomPaint(
          size: PdfPoint(size * 1.6, size),
          painter: (PdfGraphics canvas, PdfPoint s) {
            final cx = s.x / 2;
            final cy = s.y / 2;
            final rx = s.x * 0.45;
            final ry = s.y * 0.4;
            // Left half
            canvas.setColor(PdfColor.fromHex('#E53935'));
            canvas.drawEllipse(cx, cy, rx, ry);
            canvas.fillPath();
            // Right half overlay
            canvas.setColor(PdfColors.white);
            canvas.drawRect(cx, 0, s.x, s.y);
            canvas.fillPath();
            canvas.setColor(PdfColor.fromHex('#FFB74D'));
            canvas.drawEllipse(cx, cy, rx, ry);
            canvas.fillPath();
            canvas.setColor(PdfColors.white);
            canvas.drawRect(0, 0, cx, s.y);
            canvas.fillPath();
            // Redraw left
            canvas.setColor(PdfColor.fromHex('#E53935'));
            canvas.moveTo(cx, cy - ry);
            canvas.curveTo(cx - rx * 1.1, cy - ry, cx - rx * 1.1, cy + ry, cx, cy + ry);
            canvas.closePath();
            canvas.fillPath();
            // Redraw right
            canvas.setColor(PdfColor.fromHex('#FFB74D'));
            canvas.moveTo(cx, cy - ry);
            canvas.curveTo(cx + rx * 1.1, cy - ry, cx + rx * 1.1, cy + ry, cx, cy + ry);
            canvas.closePath();
            canvas.fillPath();
          },
        ),
      );
    }

    // Water glass icon
    pw.Widget glassPicto({double size = 12}) {
      return pw.Container(
        width: size * 0.7, height: size,
        child: pw.CustomPaint(
          size: PdfPoint(size * 0.7, size),
          painter: (PdfGraphics canvas, PdfPoint s) {
            // Glass outline (trapezoid)
            canvas.setColor(PdfColor.fromHex('#1976D2'));
            canvas.setLineWidth(0.8);
            canvas.moveTo(s.x * 0.15, s.y * 0.95);
            canvas.lineTo(s.x * 0.05, s.y * 0.05);
            canvas.lineTo(s.x * 0.95, s.y * 0.05);
            canvas.lineTo(s.x * 0.85, s.y * 0.95);
            canvas.closePath();
            canvas.strokePath();
            // Water fill
            canvas.setColor(PdfColor.fromHex('#BBDEFB'));
            canvas.moveTo(s.x * 0.18, s.y * 0.7);
            canvas.lineTo(s.x * 0.08, s.y * 0.05);
            canvas.lineTo(s.x * 0.92, s.y * 0.05);
            canvas.lineTo(s.x * 0.82, s.y * 0.7);
            canvas.closePath();
            canvas.fillPath();
          },
        ),
      );
    }

    // Build einnahme cell with pictograms
    pw.Widget einnahmeCell(String hinweisCode) {
      if (hinweisCode.isEmpty) return pw.SizedBox();

      final tealCol = PdfColor.fromHex('#00796B');
      final smallBold = pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold, color: tealCol);
      final smallText = pw.TextStyle(fontSize: 5.5, color: PdfColors.grey700);

      switch (hinweisCode) {
        case 'vor_essen':
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pillPicto(size: 8),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2), child: pw.Text('30-60\'', style: smallText)),
              besteckPicto(size: 12),
            ],
          );
        case 'nach_essen':
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              besteckPicto(size: 12),
              pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2), child: pw.Text('1-2h', style: smallText)),
              pillPicto(size: 8),
            ],
          );
        case 'zum_essen':
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              besteckPicto(size: 12),
              pw.Text('+', style: smallBold),
              pillPicto(size: 8),
            ],
          );
        case 'nüchtern':
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pillPicto(size: 8),
                  pw.Padding(padding: const pw.EdgeInsets.symmetric(horizontal: 2), child: pw.Text('1h', style: smallText)),
                  besteckPicto(size: 12),
                ],
              ),
              pw.Text('nüchtern', style: smallText),
            ],
          );
        case 'mit_wasser':
          return pw.Row(
            mainAxisSize: pw.MainAxisSize.min,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              glassPicto(size: 12),
              pw.SizedBox(width: 2),
              pillPicto(size: 8),
            ],
          );
        case 'nicht_zerkauen':
          return pw.Column(
            mainAxisSize: pw.MainAxisSize.min,
            children: [
              pillPicto(size: 8),
              pw.Text('ganz', style: smallText),
            ],
          );
        case 'unabhaengig':
          return pw.Text('jederzeit', style: smallText);
        default:
          // Custom or unknown
          final label = hinweisCode.startsWith('custom:') ? hinweisCode.substring(7) : hinweisCode;
          return pw.Text(label, style: pw.TextStyle(fontSize: 6, color: tealCol));
      }
    }

    // Table cell — show number of tablets or dash
    pw.Widget zeitCell(dynamic val, PdfColor color) {
      final s = val?.toString() ?? '0';
      final n = double.tryParse(s) ?? 0;
      if (n <= 0) {
        return pw.Container(
          height: 28,
          alignment: pw.Alignment.center,
          child: pw.Text('--', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey300)),
        );
      }
      // Show number (remove trailing .0)
      final display = n == n.toInt() ? n.toInt().toString() : s;
      return pw.Container(
        height: 28,
        alignment: pw.Alignment.center,
        child: pw.Text(display, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: color)),
      );
    }

    // Section box
    pw.Widget sectionBox(String title, List<pw.Widget> children) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          border: pw.Border.all(color: PdfColor.fromHex('#B2DFDB'), width: 0.8),
          borderRadius: pw.BorderRadius.circular(4),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: pw.BoxDecoration(color: tealLight, borderRadius: pw.BorderRadius.circular(2)),
              child: pw.Text(title, style: sectionStyle),
            ),
            pw.SizedBox(height: 6),
            ...children,
          ],
        ),
      );
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(36),
        footer: (pw.Context ctx) {
          return pw.Container(
            padding: const pw.EdgeInsets.only(top: 6),
            decoration: const pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5))),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(vereinName, style: smallStyle),
                pw.Text('Medikamentenplan - $arztTitle', style: smallStyle),
                pw.Text('Seite ${ctx.pageNumber}/${ctx.pagesCount}', style: smallStyle),
                pw.Text(now, style: smallStyle),
              ],
            ),
          );
        },
        build: (pw.Context context) {
          return [
            // ===== HEADER BAR =====
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: pw.BoxDecoration(
                color: teal,
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('MEDIKAMENTENPLAN', style: titleStyle),
                      pw.Text(arztTitle, style: subtitleStyle),
                    ],
                  ),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(vereinName, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold, color: PdfColors.white)),
                      if (vereinRegNr.isNotEmpty)
                        pw.Text(vereinRegNr, style: subtitleStyle),
                      pw.Text('Datum: $now', style: subtitleStyle),
                    ],
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // ===== ROW 1: MITGLIED =====
            sectionBox('Mitglied', [
              pw.Row(
                children: [
                  pw.Expanded(child: infoRow('Name:', userName)),
                  pw.Expanded(child: infoRow('Nr.:', user.mitgliedernummer)),
                  pw.Expanded(child: infoRow('Geb.:', user.geburtsdatum ?? '')),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: infoRow('Adresse:', [user.strasse, user.hausnummer].where((s) => s != null && s.isNotEmpty).join(' '))),
                  pw.Expanded(child: infoRow('Ort:', [user.plz, user.ort].where((s) => s != null && s.isNotEmpty).join(' '))),
                  pw.Expanded(child: infoRow('Tel.:', (user.telefonMobil ?? user.telefonFix ?? '').replaceAll(RegExp(r'[^\d+\-\s/()]'), ''))),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: infoRow('E-Mail:', user.email)),
                  pw.Expanded(child: pw.SizedBox()),
                  pw.Expanded(child: pw.SizedBox()),
                ],
              ),
            ]),
            pw.SizedBox(height: 8),

            // ===== ROW 2: ARZT =====
            sectionBox(arztTitle, selectedArzt.isNotEmpty ? [
              pw.Row(
                children: [
                  pw.Expanded(child: infoRow('Praxis:', selectedArzt['praxis_name'] ?? '')),
                  pw.Expanded(child: infoRow('Arzt:', selectedArzt['arzt_name'] ?? '')),
                  if (behandelnderArzt.isNotEmpty)
                    pw.Expanded(child: infoRow('Beh. Arzt:', behandelnderArzt)),
                ],
              ),
              pw.Row(
                children: [
                  pw.Expanded(child: infoRow('Adresse:', [selectedArzt['strasse'], selectedArzt['plz_ort']].where((s) => s != null && s.toString().isNotEmpty).join(', '))),
                  pw.Expanded(child: infoRow('Tel.:', (selectedArzt['telefon'] ?? '').toString().replaceAll(RegExp(r'[^\d+\-\s/()]'), ''))),
                  pw.Expanded(child: infoRow('E-Mail:', selectedArzt['email'] ?? '')),
                ],
              ),
            ] : [
              pw.Text('Kein Arzt zugewiesen', style: labelStyle),
            ]),
            pw.SizedBox(height: 14),

            // ===== LEGENDE =====
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: pw.BoxDecoration(color: bgLight, borderRadius: pw.BorderRadius.circular(4), border: pw.Border.all(color: PdfColors.grey200)),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.center,
                children: [
                  morgensPicto(), pw.SizedBox(width: 4),
                  pw.Text('Morgens', style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#FF8F00'), fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 16),
                  mittagsPicto(), pw.SizedBox(width: 4),
                  pw.Text('Mittags', style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#F9A825'), fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 16),
                  abendsPicto(), pw.SizedBox(width: 4),
                  pw.Text('Abends', style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#E65100'), fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 16),
                  nachtsPicto(), pw.SizedBox(width: 4),
                  pw.Text('Nachts', style: pw.TextStyle(fontSize: 8, color: PdfColor.fromHex('#1A237E'), fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 24),
                  pw.Text('--', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey400)),
                  pw.SizedBox(width: 4),
                  pw.Text('= Keine Einnahme', style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // ===== MEDIKAMENTEN-TABELLE =====
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: {
                0: const pw.FlexColumnWidth(3),
                1: const pw.FlexColumnWidth(1.5),
                2: const pw.FlexColumnWidth(0.8),
                3: const pw.FlexColumnWidth(0.8),
                4: const pw.FlexColumnWidth(0.8),
                5: const pw.FlexColumnWidth(0.8),
                6: const pw.FlexColumnWidth(2.5),
                7: const pw.FlexColumnWidth(2.5),
              },
              children: [
                // Header
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: tealDark),
                  children: [
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Medikament', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Dosis', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: morgensPicto())),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: mittagsPicto())),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: abendsPicto())),
                    pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: nachtsPicto())),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Einnahme', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                    pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text('Hinweise', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: PdfColors.white))),
                  ],
                ),
                // Data
                ...medikamente.asMap().entries.map((entry) {
                  final i = entry.key;
                  final m = entry.value;
                  final rowBg = i % 2 == 0 ? PdfColors.white : tealLight;
                  return pw.TableRow(
                    decoration: pw.BoxDecoration(color: rowBg),
                    children: [
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['medikament_name'] ?? '', style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['dosis'] ?? '', style: const pw.TextStyle(fontSize: 8))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: zeitCell(m['morgens'], PdfColor.fromHex('#FF8F00'))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: zeitCell(m['mittags'], PdfColor.fromHex('#F9A825'))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: zeitCell(m['abends'], PdfColor.fromHex('#E65100'))),
                      pw.Padding(padding: const pw.EdgeInsets.all(3), child: zeitCell(m['nachts'], PdfColor.fromHex('#1A237E'))),
                      pw.Padding(padding: const pw.EdgeInsets.all(4), child: pw.Center(child: einnahmeCell(m['einnahmehinweis']?.toString() ?? ''))),
                      pw.Padding(padding: const pw.EdgeInsets.all(6), child: pw.Text(m['notizen'] ?? '', style: pw.TextStyle(fontSize: 7, fontStyle: pw.FontStyle.italic, color: PdfColors.grey700))),
                    ],
                  );
                }),
              ],
            ),
            pw.SizedBox(height: 16),

            // ===== TOTAL =====
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(color: tealLight, borderRadius: pw.BorderRadius.circular(4)),
              child: pw.Text('Gesamt: ${medikamente.length} Medikament${medikamente.length == 1 ? '' : 'e'}', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold, color: teal)),
            ),
            pw.SizedBox(height: 16),

            // ===== VEREIN (bottom) =====
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(vereinName, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold, color: teal)),
                  if (vereinAdresse.isNotEmpty)
                    pw.Text(vereinAdresse, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  if (vereinTelefon.isNotEmpty)
                    pw.Text('Tel.: $vereinTelefon', style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                  if (vereinEmail.isNotEmpty)
                    pw.Text(vereinEmail, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
                ],
              ),
            ),
          ];
        },
      ),
    );

    // Save + show in-app
    final pdfBytes = await pdf.save();
    final tempDir = await getTemporaryDirectory();
    final fileName = 'Medikamentenplan_${userName.replaceAll(' ', '_')}_${arztTitle.replaceAll(' ', '_')}_${DateFormat('yyyyMMdd').format(DateTime.now())}.pdf';
    await File('${tempDir.path}/$fileName').writeAsBytes(pdfBytes);

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 850,
          height: 750,
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.teal.shade800,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf, color: Colors.white, size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Medikamentenplan - $userName', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14), overflow: TextOverflow.ellipsis)),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final downloadsDir = await getDownloadsDirectory();
                        if (downloadsDir != null) {
                          final savePath = '${downloadsDir.path}/$fileName';
                          await File(savePath).writeAsBytes(pdfBytes);
                          if (ctx.mounted) {
                            ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Gespeichert: $savePath'), backgroundColor: Colors.green));
                          }
                        }
                      },
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Download'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.teal.shade800, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    ),
                    const SizedBox(width: 6),
                    ElevatedButton.icon(
                      onPressed: () => Printing.layoutPdf(onLayout: (_) async => pdfBytes, name: fileName),
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('Drucken'),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.teal.shade800, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    ),
                    const SizedBox(width: 6),
                    IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 20), onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
              ),
              Expanded(
                child: PdfPreview(
                  build: (_) async => pdfBytes,
                  canChangeOrientation: false,
                  canChangePageFormat: false,
                  canDebug: false,
                  allowPrinting: false,
                  allowSharing: false,
                  pdfFileName: fileName,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showArztNummernDialog(BuildContext context, Map<String, dynamic> arzt, Function(Map<String, dynamic>) onSaved) {
    final lanrC = TextEditingController(text: arzt['lanr']?.toString() ?? '');
    final bsnrC = TextEditingController(text: arzt['bsnr']?.toString() ?? '');

    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.badge, size: 18, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          const Text('LANR / BSNR bearbeiten', style: TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(arzt['praxis_name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    Text(arzt['arzt_name']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: lanrC,
                keyboardType: TextInputType.number,
                maxLength: 9,
                decoration: InputDecoration(
                  labelText: 'LANR – Lebenslange Arztnummer (9 Ziffern)',
                  prefixIcon: Icon(Icons.badge, size: 18, color: Colors.indigo.shade400),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: bsnrC,
                keyboardType: TextInputType.number,
                maxLength: 9,
                decoration: InputDecoration(
                  labelText: 'BSNR – Betriebsstättennummer (9 Ziffern)',
                  prefixIcon: Icon(Icons.business, size: 18, color: Colors.purple.shade400),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              Text('Die BSNR identifiziert die Praxis, die LANR den Arzt persönlich.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Speichern'),
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600),
            onPressed: () async {
              final arztId = arzt['id'];
              if (arztId == null) {
                if (dlgCtx.mounted) ScaffoldMessenger.of(dlgCtx).showSnackBar(const SnackBar(content: Text('Fehler: Arzt-ID nicht gefunden'), backgroundColor: Colors.red));
                return;
              }
              try {
                final result = await widget.apiService.manageArzt({
                  'action': 'update_nummern',
                  'id': arztId,
                  'lanr': lanrC.text.trim(),
                  'bsnr': bsnrC.text.trim(),
                });
                if (!dlgCtx.mounted) return;
                if (result['success'] == true) {
                  Navigator.pop(dlgCtx);
                  onSaved({'lanr': lanrC.text.trim(), 'bsnr': bsnrC.text.trim()});
                } else {
                  ScaffoldMessenger.of(dlgCtx).showSnackBar(SnackBar(content: Text(result['message']?.toString() ?? 'Fehler beim Speichern'), backgroundColor: Colors.red));
                }
              } catch (e) {
                if (dlgCtx.mounted) {
                  ScaffoldMessenger.of(dlgCtx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                }
              }
            },
          ),
        ],
      ),
    );
  }

  void _showArztSucheDialog(BuildContext context, String fachrichtung, Function(Map<String, dynamic>) onSelect) {
    final searchController = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool isLoading = false;
    bool initialLoaded = false;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            Future<void> doSearch() async {
              setDialogState(() => isLoading = true);
              try {
                final isKrankenhaus = fachrichtung.contains('Krankenhaus') || fachrichtung.contains('Klinik') || fachrichtung.contains('Stationare');
                final res = isKrankenhaus
                    ? await widget.apiService.searchKliniken(search: searchController.text.trim())
                    : await widget.apiService.searchAerzte(search: searchController.text.trim());
                final dataKey = isKrankenhaus ? 'kliniken' : 'data';
                if (res['success'] == true && res[dataKey] != null) {
                  var list = List<Map<String, dynamic>>.from(res[dataKey]);
                  if (isKrankenhaus) {
                    list = list.map((k) => {
                      ...k,
                      'arzt_name': k['name'] ?? '',
                      'praxis_name': k['krankenhaus'] ?? k['name'] ?? '',
                      'online_termin_url': k['online_termin_url'] ?? '',
                    }).toList();
                  }
                  setDialogState(() { results = list; isLoading = false; });
                } else {
                  setDialogState(() { results = []; isLoading = false; });
                }
              } catch (e) {
                debugPrint('[AERZTE-DIALOG] Error: $e');
                setDialogState(() { results = []; isLoading = false; });
              }
            }

            // Auto-load on first open only
            if (!initialLoaded) {
              initialLoaded = true;
              Future.microtask(() => doSearch());
            }

            return AlertDialog(
              title: Row(
                children: [
                  Icon(Icons.search, color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  const Text('Arzt aus Datenbank auswählen', style: TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 600,
                height: 450,
                child: Column(
                  children: [
                    // Search field
                    TextField(
                      controller: searchController,
                      decoration: InputDecoration(
                        hintText: 'Name, Praxis oder Ort suchen...',
                        prefixIcon: const Icon(Icons.search, size: 20),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.search, color: Colors.teal),
                          onPressed: doSearch,
                        ),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      onSubmitted: (_) => doSearch(),
                    ),
                    const SizedBox(height: 12),
                    // Results
                    Expanded(
                      child: isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : results.isEmpty
                              ? Center(child: Text('Keine Ärzte gefunden', style: TextStyle(color: Colors.grey.shade500)))
                              : ListView.builder(
                                  itemCount: results.length,
                                  itemBuilder: (ctx, i) {
                                    final arzt = results[i];
                                    return Card(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      child: ListTile(
                                        leading: CircleAvatar(
                                          backgroundColor: Colors.teal.shade100,
                                          child: Icon(Icons.local_hospital, color: Colors.teal.shade700, size: 20),
                                        ),
                                        title: Text(arzt['praxis_name'] ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                        subtitle: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text('${arzt['arzt_name'] ?? ''}${arzt['weitere_aerzte']?.isNotEmpty == true ? ', ${arzt['weitere_aerzte']}' : ''}',
                                                style: const TextStyle(fontSize: 12)),
                                            Text('${arzt['strasse'] ?? ''}, ${arzt['plz_ort'] ?? ''}',
                                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            if (arzt['telefon']?.isNotEmpty == true)
                                              Text('Tel: ${arzt['telefon']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            if ((arzt['lanr']?.isNotEmpty == true) || (arzt['bsnr']?.isNotEmpty == true))
                                              Padding(
                                                padding: const EdgeInsets.only(top: 3),
                                                child: Wrap(spacing: 6, children: [
                                                  if (arzt['lanr']?.isNotEmpty == true)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.indigo.shade200)),
                                                      child: Text('LANR: ${arzt['lanr']}', style: TextStyle(fontSize: 10, color: Colors.indigo.shade700, fontWeight: FontWeight.w600)),
                                                    ),
                                                  if (arzt['bsnr']?.isNotEmpty == true)
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.purple.shade200)),
                                                      child: Text('BSNR: ${arzt['bsnr']}', style: TextStyle(fontSize: 10, color: Colors.purple.shade700, fontWeight: FontWeight.w600)),
                                                    ),
                                                ]),
                                              ),
                                          ],
                                        ),
                                        isThreeLine: true,
                                        onTap: () {
                                          Navigator.of(ctx).pop();
                                          onSelect(arzt);
                                        },
                                        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
                                      ),
                                    );
                                  },
                                ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Abbrechen'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildBehoerdeSectionHeader(IconData icon, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
          Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
        ],
      ),
    );
  }

  Widget _buildBehoerdeTextField(String label, TextEditingController controller, {String hint = '', IconData icon = Icons.edit, int maxLines = 1, VoidCallback? onAutoSave}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Focus(
          onFocusChange: (hasFocus) {
            if (!hasFocus && onAutoSave != null) {
              onAutoSave();
            }
          },
          child: TextField(
            controller: controller,
            maxLines: maxLines,
            decoration: InputDecoration(
              hintText: hint,
              prefixIcon: Icon(icon, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  // REZEPT TAB (Muster 16)
  // ═══════════════════════════════════════════════════════
  Widget _buildRezeptTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    final List<dynamic> rezepte = data['rezepte'] is List ? data['rezepte'] as List : [];

    // ── Rezept-Typ helpers ──
    MaterialColor rTypColor(String t) => t == 'blau' ? Colors.blue : t == 'gruen' ? Colors.green : t == 'gelb' ? Colors.amber : t == 'trezept' ? Colors.blueGrey : Colors.pink;
    int rTypDays(String t) { switch (t) { case 'blau': return 90; case 'gruen': return -1; case 'gelb': return 7; case 'trezept': return 6; default: return 28; } }
    String rTypName(String t) => t == 'blau' ? 'Blaues Rezept (Privatrezept)' : t == 'gruen' ? 'Grünes Rezept (Empfehlung)' : t == 'gelb' ? 'Gelbes Rezept (BtM)' : t == 'trezept' ? 'T-Rezept (Thalidomid)' : 'Rosa Rezept (Muster 16)';
    String rTypShort(String t) => t == 'blau' ? 'Blau' : t == 'gruen' ? 'Grün' : t == 'gelb' ? 'Gelb' : t == 'trezept' ? 'T-Rez.' : 'Rosa';
    // Returns expiry date string or null (for unlimited/no datum)
    String? rTypExpiry(String t, String datum) {
      final days = rTypDays(t);
      if (days < 0) return null; // unlimited
      final d = DateTime.tryParse(datum);
      if (d == null) return null;
      return DateFormat('dd.MM.yyyy').format(d.add(Duration(days: days)));
    }
    bool rTypIsExpired(String t, String datum) {
      final days = rTypDays(t);
      if (days < 0) return false;
      final d = DateTime.tryParse(datum);
      if (d == null) return false;
      return DateTime.now().isAfter(d.add(Duration(days: days)));
    }

    void showRezeptDialog({Map<String, dynamic>? existing, int? editIndex}) {
      final arztData = data['selected_arzt'] is Map ? data['selected_arzt'] as Map : {};
      final user = widget.user;
      final userName = '${user.vorname ?? ''} ${user.nachname ?? ''}'.trim();

      final datumC = TextEditingController(text: existing?['datum']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
      final patientC = TextEditingController(text: existing?['patient']?.toString() ?? userName);
      final gebDatumC = TextEditingController(text: existing?['geb_datum']?.toString() ?? (user.geburtsdatum ?? ''));
      final krankenkasseC = TextEditingController(text: existing?['krankenkasse']?.toString() ?? '');
      final versichertenNrC = TextEditingController(text: existing?['versicherten_nr']?.toString() ?? '');
      final kostentraegerC = TextEditingController(text: existing?['kostentraeger_kennung']?.toString() ?? '');
      final bsnrC = TextEditingController(text: existing?['bsnr']?.toString() ?? arztData['bsnr']?.toString() ?? '');
      final lanrC = TextEditingController(text: existing?['lanr']?.toString() ?? arztData['lanr']?.toString() ?? '');
      final med1C = TextEditingController(text: existing?['med1']?.toString() ?? '');
      final med1MengeC = TextEditingController(text: existing?['med1_menge']?.toString() ?? '');
      final med1DosisC = TextEditingController(text: existing?['med1_dosis']?.toString() ?? '');
      final med2C = TextEditingController(text: existing?['med2']?.toString() ?? '');
      final med2MengeC = TextEditingController(text: existing?['med2_menge']?.toString() ?? '');
      final med2DosisC = TextEditingController(text: existing?['med2_dosis']?.toString() ?? '');
      final med3C = TextEditingController(text: existing?['med3']?.toString() ?? '');
      final med3MengeC = TextEditingController(text: existing?['med3_menge']?.toString() ?? '');
      final med3DosisC = TextEditingController(text: existing?['med3_dosis']?.toString() ?? '');

      bool noctu = existing?['noctu'] == true || existing?['noctu'] == 'true';
      bool autIdem = existing?['aut_idem'] == true || existing?['aut_idem'] == 'true';
      bool unfall = existing?['unfall'] == true || existing?['unfall'] == 'true';
      bool bvg = existing?['bvg'] == true || existing?['bvg'] == 'true';
      bool gebuehrenfrei = existing?['gebuehrenfrei'] == true || existing?['gebuehrenfrei'] == 'true';
      bool gebuehrenpflichtig = existing?['gebuehrenpflichtig'] == true || existing?['gebuehrenpflichtig'] == 'true';
      String status = existing?['status']?.toString() ?? 'ausgestellt';
      // rosa = Muster 16 (Kassenrezept), blau = Privatrezept, gruen = Grünes Rezept
      String rezeptTyp = existing?['rezept_typ']?.toString() ?? 'rosa';

      // Status tab controllers
      bool abgeholt = existing?['abgeholt'] == true || existing?['abgeholt'] == 'true';
      final abgeholtDatumC = TextEditingController(text: existing?['abgeholt_datum']?.toString() ?? '');
      final apothekeDatumC = TextEditingController(text: existing?['apotheke_datum']?.toString() ?? '');
      final kostenC = TextEditingController(text: existing?['kosten']?.toString() ?? '');
      final apothekenNameC = TextEditingController(text: existing?['apotheke_name']?.toString() ?? '');
      String einloeseOrt = existing?['einloese_ort']?.toString() ?? 'apotheke';

      void doSave(Map<String, dynamic> entry, {bool fromStatus = false, StateSetter? setS}) {
        final base = existing != null ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
        base.addAll(entry);
        final list = List<dynamic>.from(rezepte);
        if (editIndex != null && editIndex < list.length) {
          list[editIndex] = base;
        } else {
          list.insert(0, base);
        }
        data['rezepte'] = list;
        _gesundheitData[type] = data;
        // Save directly to server
        debugPrint('[REZEPT-SAVE] type=$type user=${widget.user.id} rezepte=${(data['rezepte'] as List?)?.length ?? 0} keys=${data.keys.toList()}');
        widget.apiService.saveGesundheitData(widget.user.id, type, data).then((r) {
          debugPrint('[REZEPT-SAVE] Result: ${r['success']} ${r['message'] ?? ''}');
        }).catchError((e) {
          debugPrint('[REZEPT-SAVE] Error: $e');
        });
        setLocalState(() {});
        if (!fromStatus) Navigator.pop(context);
        if (setS != null) setS(() {});
      }

      // ── buildEditForm: closes over all local vars from showRezeptDialog ──
      Widget buildEditForm(StateSetter setDlgState, void Function(Map<String, dynamic>) onSave) {
        final arztData2 = data['selected_arzt'] is Map ? data['selected_arzt'] as Map : {};
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Rezept-Typ Auswahl (5 Typen, 2 Reihen: 3+2)
            Builder(builder: (_) {
              Widget typBtn((String, String, String, MaterialColor) typ) => Expanded(child: GestureDetector(
                onTap: () => setDlgState(() => rezeptTyp = typ.$1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  margin: const EdgeInsets.only(right: 4),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: rezeptTyp == typ.$1 ? typ.$4.shade100 : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: rezeptTyp == typ.$1 ? typ.$4.shade400 : Colors.grey.shade300, width: rezeptTyp == typ.$1 ? 2 : 1),
                  ),
                  child: Column(children: [
                    Container(width: 16, height: 16, decoration: BoxDecoration(color: typ.$4.shade400, shape: BoxShape.circle)),
                    const SizedBox(height: 3),
                    Text(typ.$2, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: rezeptTyp == typ.$1 ? typ.$4.shade800 : Colors.grey.shade600), textAlign: TextAlign.center),
                    Text(typ.$3, style: TextStyle(fontSize: 8, color: Colors.grey.shade500), textAlign: TextAlign.center),
                  ]),
                ),
              ));
              return Column(children: [
                Row(children: [
                  typBtn(('rosa',  'Rosa Rezept',   'Muster 16 (GKV)', Colors.pink)),
                  typBtn(('blau',  'Blaues Rezept', 'Privatrezept',    Colors.blue)),
                  typBtn(('gruen', 'Grünes Rezept', 'Empfehlung (OTC)', Colors.green)),
                ]),
                const SizedBox(height: 4),
                Row(children: [
                  typBtn(('gelb',    'Gelbes Rezept', 'BtM (Opioide)',   Colors.amber)),
                  typBtn(('trezept', 'T-Rezept',      'Thalidomid/etc.', Colors.blueGrey)),
                  const Expanded(child: SizedBox.shrink()),
                ]),
              ]);
            }),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: TextFormField(
                  controller: datumC,
                  readOnly: true,
                  decoration: InputDecoration(
                    labelText: 'Ausstellungsdatum',
                    prefixIcon: const Icon(Icons.calendar_today, size: 16),
                    isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                      final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                      if (picked != null) setDlgState(() => datumC.text = DateFormat('yyyy-MM-dd').format(picked));
                    }),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InputDecorator(
                  decoration: InputDecoration(labelText: 'Status', prefixIcon: const Icon(Icons.flag, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  child: DropdownButton<String>(
                    value: status,
                    isExpanded: true,
                    isDense: true,
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(value: 'ausgestellt', child: Text('Ausgestellt', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'abgeholt', child: Text('Abgeholt', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'eingeloest', child: Text('Eingelöst', style: TextStyle(fontSize: 13))),
                      DropdownMenuItem(value: 'abgelaufen', child: Text('Abgelaufen', style: TextStyle(fontSize: 13))),
                    ],
                    onChanged: (v) => setDlgState(() => status = v ?? status),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: TextFormField(controller: patientC, decoration: InputDecoration(labelText: 'Patient', prefixIcon: const Icon(Icons.person, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextFormField(controller: gebDatumC, decoration: InputDecoration(labelText: 'Geburtsdatum', prefixIcon: const Icon(Icons.cake, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(flex: 3, child: TextFormField(controller: krankenkasseC, decoration: InputDecoration(labelText: 'Krankenkasse', prefixIcon: const Icon(Icons.health_and_safety, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: TextFormField(controller: kostentraegerC, decoration: InputDecoration(labelText: 'Kostenträger-IK', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            ]),
            const SizedBox(height: 6),
            TextFormField(controller: versichertenNrC, decoration: InputDecoration(labelText: 'Versicherten-Nr.', prefixIcon: const Icon(Icons.badge, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextFormField(controller: bsnrC, decoration: InputDecoration(labelText: 'BSNR', prefixIcon: const Icon(Icons.numbers, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
              const SizedBox(width: 8),
              Expanded(child: TextFormField(controller: lanrC, decoration: InputDecoration(labelText: 'LANR', prefixIcon: const Icon(Icons.numbers, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.pink.shade100)),
              child: Wrap(spacing: 4, children: [
                _rezeptCheckbox('Noctu', noctu, (v) => setDlgState(() => noctu = v), Colors.orange),
                _rezeptCheckbox('Gebührenfrei', gebuehrenfrei, (v) => setDlgState(() { gebuehrenfrei = v; if (v) gebuehrenpflichtig = false; }), Colors.green),
                _rezeptCheckbox('Gebührenpflichtig', gebuehrenpflichtig, (v) => setDlgState(() { gebuehrenpflichtig = v; if (v) gebuehrenfrei = false; }), Colors.teal),
                _rezeptCheckbox('Aut-idem ✗', autIdem, (v) => setDlgState(() => autIdem = v), Colors.red),
                _rezeptCheckbox('Unfall', unfall, (v) => setDlgState(() => unfall = v), Colors.blue),
                _rezeptCheckbox('BVG', bvg, (v) => setDlgState(() => bvg = v), Colors.purple),
              ]),
            ),
            const SizedBox(height: 12),
            Text('Medikamente (bis zu 3)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
            const SizedBox(height: 8),
            _medikamentRow(1, med1C, med1MengeC, med1DosisC),
            const SizedBox(height: 8),
            _medikamentRow(2, med2C, med2MengeC, med2DosisC),
            const SizedBox(height: 8),
            _medikamentRow(3, med3C, med3MengeC, med3DosisC),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: const Text('Rezept speichern'),
                style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600),
                onPressed: () {
                  if (med1C.text.trim().isEmpty && med2C.text.trim().isEmpty && med3C.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens ein Medikament eingeben'), backgroundColor: Colors.red));
                    return;
                  }
                  onSave({
                    'datum': datumC.text,
                    'patient': patientC.text.trim(),
                    'geb_datum': gebDatumC.text.trim(),
                    'krankenkasse': krankenkasseC.text.trim(),
                    'versicherten_nr': versichertenNrC.text.trim(),
                    'kostentraeger_kennung': kostentraegerC.text.trim(),
                    'bsnr': bsnrC.text.trim(),
                    'lanr': lanrC.text.trim(),
                    'rezept_typ': rezeptTyp,
                    'noctu': noctu,
                    'gebuehrenfrei': gebuehrenfrei,
                    'gebuehrenpflichtig': gebuehrenpflichtig,
                    'aut_idem': autIdem,
                    'unfall': unfall,
                    'bvg': bvg,
                    'status': status,
                    'med1': med1C.text.trim(),
                    'med1_menge': med1MengeC.text.trim(),
                    'med1_dosis': med1DosisC.text.trim(),
                    'med2': med2C.text.trim(),
                    'med2_menge': med2MengeC.text.trim(),
                    'med2_dosis': med2DosisC.text.trim(),
                    'med3': med3C.text.trim(),
                    'med3_menge': med3MengeC.text.trim(),
                    'med3_dosis': med3DosisC.text.trim(),
                    'ausgestellt_von': () {
                      final name = arztData2['arzt_name']?.toString() ?? '';
                      final praxis = arztData2['praxis_name']?.toString() ?? '';
                      if (name.isNotEmpty && praxis.isNotEmpty) return '$name – $praxis';
                      if (name.isNotEmpty) return name;
                      if (praxis.isNotEmpty) return praxis;
                      return arztTitle;
                    }(),
                  });
                },
              ),
            ),
          ]),
        );
      }

      // ── New rezept: simple dialog, no tabs ──
      if (editIndex == null) {
        showDialog(
          context: context,
          builder: (dlgCtx) => StatefulBuilder(
            builder: (dlgCtx, setDlgState) => AlertDialog(
              contentPadding: EdgeInsets.zero,
              titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              title: Row(children: [
                Icon(Icons.receipt_long, size: 18, color: rTypColor(rezeptTyp).shade700),
                const SizedBox(width: 8),
                Expanded(child: Text('Neues ${rTypName(rezeptTyp)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
              ]),
              content: SizedBox(
                width: 520,
                height: 560,
                child: buildEditForm(setDlgState, doSave),
              ),
            ),
          ),
        );
        return;
      }

      // ── Existing rezept: tabbed view ──
      final statusColors = {'ausgestellt': Colors.blue.shade600, 'abgeholt': Colors.orange.shade600, 'eingeloest': Colors.green.shade600, 'abgelaufen': Colors.grey.shade500};
      final statusLabels = {'ausgestellt': 'Ausgestellt', 'abgeholt': 'Abgeholt', 'eingeloest': 'Eingelöst', 'abgelaufen': 'Abgelaufen'};

      final r = existing ?? <String, dynamic>{};

      // ── Auto-expire: if past validity and not yet 'abgelaufen', save silently ──
      final exTyp = r['rezept_typ']?.toString() ?? 'rosa';
      final exDatum = r['datum']?.toString() ?? '';
      if (rTypIsExpired(exTyp, exDatum) && status != 'abgelaufen') {
        status = 'abgelaufen';
        doSave({'status': 'abgelaufen'}, fromStatus: true);
      }

      showDialog(
        context: context,
        builder: (dlgCtx) => StatefulBuilder(
          builder: (dlgCtx, setDlgState) {
            bool editMode = false;

            return StatefulBuilder(builder: (dlgCtx2, setDlgState2) => AlertDialog(
              contentPadding: EdgeInsets.zero,
              titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
              title: Row(children: [
                Icon(Icons.receipt_long, size: 18, color: rTypColor(r['rezept_typ']?.toString() ?? 'rosa').shade700),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(rTypName(r['rezept_typ']?.toString() ?? 'rosa'), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  if ((r['datum']?.toString() ?? '').isNotEmpty)
                    Text(() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(r['datum'].toString())); } catch (_) { return r['datum'].toString(); } }(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
                if (!editMode) IconButton(
                  icon: Icon(Icons.edit, size: 16, color: Colors.pink.shade600),
                  tooltip: 'Bearbeiten',
                  onPressed: () => setDlgState2(() => editMode = true),
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
              ]),
              content: SizedBox(
                width: 520,
                height: 580,
                child: editMode
                  ? buildEditForm(setDlgState2, (entry) {
                      doSave(entry);
                      Navigator.pop(dlgCtx);
                    })
                  : DefaultTabController(
                      length: 2,
                      child: Column(children: [
                        TabBar(
                          labelColor: Colors.pink.shade700,
                          unselectedLabelColor: Colors.grey.shade500,
                          indicatorColor: Colors.pink.shade700,
                          tabs: const [
                            Tab(icon: Icon(Icons.receipt_long, size: 16), text: 'Details'),
                            Tab(icon: Icon(Icons.track_changes, size: 16), text: 'Status'),
                          ],
                        ),
                        Expanded(child: TabBarView(children: [

                          // ── TAB 1: Details (read-only) ──
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              // Rezept-Typ Badge + Status badge
                              Row(children: [
                                () {
                                  final typ = r['rezept_typ']?.toString() ?? 'rosa';
                                  final typColor = rTypColor(typ);
                                  final typLabel = rTypShort(typ);
                                  return Container(
                                    margin: const EdgeInsets.only(right: 6),
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: typColor.shade100, borderRadius: BorderRadius.circular(20), border: Border.all(color: typColor.shade300)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Container(width: 8, height: 8, decoration: BoxDecoration(color: typColor.shade500, shape: BoxShape.circle)),
                                      const SizedBox(width: 4),
                                      Text(typLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: typColor.shade800)),
                                    ]),
                                  );
                                }(),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: (statusColors[r['status']?.toString() ?? 'ausgestellt'] ?? Colors.blue).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                                    Icon(Icons.flag, size: 12, color: statusColors[r['status']?.toString() ?? 'ausgestellt'] ?? Colors.blue),
                                    const SizedBox(width: 4),
                                    Text(statusLabels[r['status']?.toString() ?? 'ausgestellt'] ?? 'Ausgestellt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: statusColors[r['status']?.toString() ?? 'ausgestellt'] ?? Colors.blue)),
                                  ]),
                                ),
                                const Spacer(),
                                if (r['noctu'] == true) _rezeptBadge('Noctu', Colors.orange),
                                if (r['gebuehrenfrei'] == true) _rezeptBadge('Gebührenfrei', Colors.green),
                                if (r['gebuehrenpflichtig'] == true) _rezeptBadge('Gebührenpflichtig', Colors.teal),
                                if (r['aut_idem'] == true) _rezeptBadge('Aut-idem ✗', Colors.red),
                                if (r['unfall'] == true) _rezeptBadge('Unfall', Colors.blue),
                                if (r['bvg'] == true) _rezeptBadge('BVG', Colors.purple),
                              ]),
                              const SizedBox(height: 8),
                              // Gültigkeit / Ablaufdatum
                              () {
                                final typ = r['rezept_typ']?.toString() ?? 'rosa';
                                final datum = r['datum']?.toString() ?? '';
                                final days = rTypDays(typ);
                                final expired = rTypIsExpired(typ, datum);
                                final expiryStr = rTypExpiry(typ, datum);
                                if (days < 0) {
                                  return Row(children: [
                                    Icon(Icons.all_inclusive, size: 14, color: Colors.green.shade600),
                                    const SizedBox(width: 6),
                                    Text('Keine Ablaufzeit (OTC-Empfehlung)', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                                  ]);
                                }
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: expired ? Colors.red.shade50 : Colors.grey.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: expired ? Colors.red.shade200 : Colors.grey.shade200),
                                  ),
                                  child: Row(children: [
                                    Icon(expired ? Icons.warning_amber_rounded : Icons.schedule, size: 14, color: expired ? Colors.red.shade600 : Colors.grey.shade600),
                                    const SizedBox(width: 6),
                                    Text('Gültig $days Tage', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const Spacer(),
                                    Text(expired ? 'Abgelaufen am $expiryStr' : 'Läuft ab: $expiryStr',
                                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: expired ? Colors.red.shade700 : Colors.grey.shade700)),
                                  ]),
                                );
                              }(),
                              const SizedBox(height: 12),
                              _rezeptDetailRow(Icons.person, 'Patient', r['patient']?.toString() ?? ''),
                              _rezeptDetailRow(Icons.cake, 'Geburtsdatum', r['geb_datum']?.toString() ?? ''),
                              _rezeptDetailRow(Icons.health_and_safety, 'Krankenkasse', r['krankenkasse']?.toString() ?? ''),
                              _rezeptDetailRow(Icons.badge, 'Versicherten-Nr.', r['versicherten_nr']?.toString() ?? ''),
                              _rezeptDetailRow(Icons.numbers, 'Kostenträger-IK', r['kostentraeger_kennung']?.toString() ?? ''),
                              _rezeptDetailRow(Icons.local_hospital, 'Ausgestellt von', r['ausgestellt_von']?.toString() ?? ''),
                              _rezeptDetailRow(Icons.numbers, 'BSNR / LANR', '${r['bsnr'] ?? ''} / ${r['lanr'] ?? ''}'),
                              const Divider(height: 20),
                              Text('Medikamente', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
                              const SizedBox(height: 8),
                              for (int i = 1; i <= 3; i++) ...[
                                if ((r['med$i']?.toString() ?? '').isNotEmpty)
                                  Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.pink.shade100)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text('Medikament $i', style: TextStyle(fontSize: 10, color: Colors.pink.shade600, fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 2),
                                      Text(r['med$i'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                      if ((r['med${i}_menge']?.toString() ?? '').isNotEmpty || (r['med${i}_dosis']?.toString() ?? '').isNotEmpty)
                                        Row(children: [
                                          if ((r['med${i}_menge']?.toString() ?? '').isNotEmpty) Text('Menge: ${r['med${i}_menge']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                          if ((r['med${i}_menge']?.toString() ?? '').isNotEmpty && (r['med${i}_dosis']?.toString() ?? '').isNotEmpty) const Text('  ·  ', style: TextStyle(fontSize: 11)),
                                          if ((r['med${i}_dosis']?.toString() ?? '').isNotEmpty) Text('Dosierung: ${r['med${i}_dosis']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                        ]),
                                    ]),
                                  ),
                              ],
                            ]),
                          ),

                          // ── TAB 2: Status (editable tracking) ──
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Rezept-Tracking', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
                              const SizedBox(height: 16),

                              // Abgeholt
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade100)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(Icons.assignment_turned_in, size: 18, color: Colors.orange.shade700),
                                    const SizedBox(width: 8),
                                    Text('Rezept abgeholt?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                                    const Spacer(),
                                    Switch(
                                      value: abgeholt,
                                      activeThumbColor: Colors.orange.shade600,
                                      onChanged: (v) => setDlgState2(() => abgeholt = v),
                                    ),
                                  ]),
                                  if (abgeholt) ...[
                                    const SizedBox(height: 8),
                                    TextFormField(
                                      controller: abgeholtDatumC,
                                      readOnly: true,
                                      decoration: InputDecoration(
                                        labelText: 'Abgeholt am (Datum & Uhrzeit)',
                                        prefixIcon: const Icon(Icons.event, size: 16),
                                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                          final date = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                                          if (date == null) return;
                                          if (!dlgCtx.mounted) return;
                                          final time = await showTimePicker(context: dlgCtx, initialTime: TimeOfDay.now());
                                          if (time == null) return;
                                          final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                                          setDlgState2(() => abgeholtDatumC.text = DateFormat('dd.MM.yyyy HH:mm').format(dt));
                                        }),
                                      ),
                                    ),
                                  ],
                                ]),
                              ),
                              const SizedBox(height: 12),

                              // Apotheke / Sanitätshaus
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: einloeseOrt == 'sanitaetshaus' ? Colors.indigo.shade50 : Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: einloeseOrt == 'sanitaetshaus' ? Colors.indigo.shade100 : Colors.green.shade100)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(einloeseOrt == 'sanitaetshaus' ? Icons.medical_services : Icons.local_pharmacy, size: 18, color: einloeseOrt == 'sanitaetshaus' ? Colors.indigo.shade700 : Colors.green.shade700),
                                    const SizedBox(width: 8),
                                    Text('Einlosen bei', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: einloeseOrt == 'sanitaetshaus' ? Colors.indigo.shade800 : Colors.green.shade800)),
                                    const SizedBox(width: 12),
                                    ChoiceChip(label: const Text('Apotheke', style: TextStyle(fontSize: 11)), selected: einloeseOrt == 'apotheke', selectedColor: Colors.green.shade600, labelStyle: TextStyle(color: einloeseOrt == 'apotheke' ? Colors.white : Colors.green.shade700), onSelected: (_) => setDlgState2(() => einloeseOrt = 'apotheke')),
                                    const SizedBox(width: 6),
                                    ChoiceChip(label: const Text('Sanitatshaus', style: TextStyle(fontSize: 11)), selected: einloeseOrt == 'sanitaetshaus', selectedColor: Colors.indigo.shade600, labelStyle: TextStyle(color: einloeseOrt == 'sanitaetshaus' ? Colors.white : Colors.indigo.shade700), onSelected: (_) => setDlgState2(() => einloeseOrt = 'sanitaetshaus')),
                                  ]),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: apothekenNameC,
                                    decoration: InputDecoration(labelText: einloeseOrt == 'sanitaetshaus' ? 'Sanitatshaus Name' : 'Apotheke Name (optional)', prefixIcon: Icon(einloeseOrt == 'sanitaetshaus' ? Icons.medical_services : Icons.store, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                  ),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: apothekeDatumC,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Eingelöst am (Datum & Uhrzeit)',
                                      prefixIcon: const Icon(Icons.event, size: 16),
                                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                        final date = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                                        if (date == null) return;
                                        if (!dlgCtx.mounted) return;
                                        final time = await showTimePicker(context: dlgCtx, initialTime: TimeOfDay.now());
                                        if (time == null) return;
                                        final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
                                        setDlgState2(() => apothekeDatumC.text = DateFormat('dd.MM.yyyy HH:mm').format(dt));
                                      }),
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 12),

                              // Kosten
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade100)),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(Icons.euro, size: 18, color: Colors.blue.shade700),
                                    const SizedBox(width: 8),
                                    Text('Kosten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                  ]),
                                  const SizedBox(height: 8),
                                  TextFormField(
                                    controller: kostenC,
                                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      labelText: 'Zuzahlung / Kosten (€)',
                                      prefixIcon: const Icon(Icons.euro, size: 16),
                                      suffixText: '€',
                                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ]),
                              ),
                              const SizedBox(height: 20),

                              // Save status button
                              SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  icon: const Icon(Icons.save, size: 16),
                                  label: const Text('Status speichern'),
                                  style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600),
                                  onPressed: () {
                                    doSave({
                                      'abgeholt': abgeholt,
                                      'abgeholt_datum': abgeholtDatumC.text.trim(),
                                      'einloese_ort': einloeseOrt,
                                      'apotheke_name': apothekenNameC.text.trim(),
                                      'apotheke_datum': apothekeDatumC.text.trim(),
                                      'kosten': kostenC.text.trim(),
                                      'status': abgeholt && apothekeDatumC.text.isNotEmpty ? 'eingeloest' : abgeholt ? 'abgeholt' : r['status']?.toString() ?? 'ausgestellt',
                                    }, fromStatus: true, setS: setDlgState2);
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Status gespeichert'), backgroundColor: Colors.pink.shade600, duration: const Duration(seconds: 2)));
                                  },
                                ),
                              ),
                            ]),
                          ),

                        ])),
                      ]),
                    ),
              ),
            ));
          },
        ),
      );
    }

    // ── load KK data for auto-fill when opening new rezept ──
    void openNewRezept() async {
      final arztData = data['selected_arzt'] is Map ? data['selected_arzt'] as Map : {};
      Map<String, dynamic>? kkData;
      try {
        final res = await widget.apiService.getBehoerdeData(widget.user.id, 'krankenkasse');
        if (res['data'] != null) kkData = Map<String, dynamic>.from(res['data']);
      } catch (_) {}
      // pre-fill KK into a temp existing map
      final prefilled = <String, dynamic>{
        'krankenkasse': kkData?['name']?.toString() ?? '',
        'versicherten_nr': kkData?['versichertennummer']?.toString() ?? '',
        'kostentraeger_kennung': kkData?['ehic_institutionskennzeichen']?.toString() ?? '',
        'bsnr': arztData['bsnr']?.toString() ?? '',
        'lanr': arztData['lanr']?.toString() ?? '',
      };
      if (context.mounted) showRezeptDialog(existing: prefilled);
    }

    return StatefulBuilder(
      builder: (context, setRezeptState) {
        final rezeptList = data['rezepte'] is List ? data['rezepte'] as List : [];

        final statusColors = {
          'ausgestellt': Colors.blue.shade600,
          'abgeholt': Colors.orange.shade600,
          'eingeloest': Colors.green.shade600,
          'abgelaufen': Colors.grey.shade500,
        };
        final statusLabels = {
          'ausgestellt': 'Ausgestellt',
          'abgeholt': 'Abgeholt',
          'eingeloest': 'Eingelöst',
          'abgelaufen': 'Abgelaufen',
        };

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Rezepte (${rezeptList.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.pink.shade700))),
              FilledButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Neues Rezept', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: Colors.pink.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
                onPressed: openNewRezept,
              ),
            ]),
            const SizedBox(height: 12),
            if (rezeptList.isEmpty)
              Center(child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(children: [
                  Icon(Icons.receipt_long, size: 40, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Keine Rezepte vorhanden', style: TextStyle(color: Colors.grey.shade400)),
                ]),
              ))
            else
              ...rezeptList.asMap().entries.map((e) {
                final idx = e.key;
                final r = Map<String, dynamic>.from(e.value as Map);
                final st = r['status']?.toString() ?? 'ausgestellt';
                final rTyp = r['rezept_typ']?.toString() ?? 'rosa';
                final rTypC = rTypColor(rTyp);
                final rTypLabel = rTypShort(rTyp);
                final cardExpired = rTypIsExpired(rTyp, r['datum']?.toString() ?? '');
                final cardExpiryStr = rTypExpiry(rTyp, r['datum']?.toString() ?? '');
                final meds = [r['med1'], r['med2'], r['med3']].where((m) => (m?.toString() ?? '').isNotEmpty).toList();
                final datumStr = r['datum']?.toString() ?? '';
                final datumFormatted = datumStr.isNotEmpty
                    ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(datumStr)); } catch (_) { return datumStr; } })()
                    : '';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  child: InkWell(
                    onTap: () => showRezeptDialog(existing: r, editIndex: idx),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(color: cardExpired ? Colors.red.shade50 : rTypC.shade50, borderRadius: BorderRadius.circular(8)),
                          child: Icon(Icons.receipt_long, size: 20, color: cardExpired ? Colors.red.shade400 : rTypC.shade600),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(color: rTypC.shade100, borderRadius: BorderRadius.circular(4), border: Border.all(color: rTypC.shade300)),
                              child: Text(rTypLabel, style: TextStyle(fontSize: 9, color: rTypC.shade800, fontWeight: FontWeight.bold)),
                            ),
                            const SizedBox(width: 6),
                            if (datumFormatted.isNotEmpty)
                              Text(datumFormatted, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(color: (cardExpired ? Colors.red : (statusColors[st] ?? Colors.grey)).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                              child: Text(cardExpired ? 'Abgelaufen' : (statusLabels[st] ?? st), style: TextStyle(fontSize: 10, color: cardExpired ? Colors.red.shade700 : (statusColors[st] ?? Colors.grey), fontWeight: FontWeight.bold)),
                            ),
                            if (r['noctu'] == true) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(4)), child: Text('Noctu', style: TextStyle(fontSize: 9, color: Colors.orange.shade700, fontWeight: FontWeight.bold)))],
                            if (r['aut_idem'] == true) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)), child: Text('Aut-idem ✗', style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.bold)))],
                          ]),
                          const SizedBox(height: 4),
                          Text(meds.join(' · '), style: TextStyle(fontSize: 12, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
                          if (cardExpiryStr != null)
                            Text(cardExpired ? '⚠ Abgelaufen am $cardExpiryStr' : 'Läuft ab: $cardExpiryStr',
                              style: TextStyle(fontSize: 10, color: cardExpired ? Colors.red.shade600 : Colors.grey.shade500)),
                          if ((r['krankenkasse']?.toString() ?? '').isNotEmpty)
                            Text(r['krankenkasse'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ])),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                          onPressed: () {
                            final list = List<dynamic>.from(rezeptList)..removeAt(idx);
                            data['rezepte'] = list;
                            saveAll();
                            setLocalState(() {});
                          },
                          tooltip: 'Löschen',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
          ]),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════
  // NOTIFY MEMBER VIA CHAT ON SITZUNG STATUS CHANGE
  // ═══════════════════════════════════════════════════════
  Future<void> _notifySitzungStatusChange({
    required String sitzungNr,
    required String datum,
    required String zeit,
    required String newStatus,
    required String bereich,
  }) async {
    try {
      // Start or get existing conversation with member
      final chatResult = await widget.apiService.adminStartChat(
        widget.adminMitgliedernummer,
        widget.user.mitgliedernummer,
      );
      final convId = chatResult['conversation_id'] ?? chatResult['conversation']?['id'];
      if (convId == null) return;

      final message = '📋 Behandlungstermin-Update\n\n'
          'Bereich: $bereich\n'
          'Sitzung Nr. $sitzungNr\n'
          'Datum: $datum${zeit.isNotEmpty ? ' um $zeit' : ''}\n'
          'Neuer Status: $newStatus\n\n'
          'Bei Fragen melden Sie sich bitte.';

      await widget.apiService.sendChatMessage(
        convId is int ? convId : int.parse(convId.toString()),
        widget.adminMitgliedernummer,
        message,
      );
    } catch (e) {
      debugPrint('[SITZUNG-NOTIFY] Chat error: $e');
    }
  }

  // ═══════════════════════════════════════════════════════
  // HEILMITTELVERORDNUNG TAB (Muster 13)
  // ═══════════════════════════════════════════════════════
  Widget _buildHeilmittelTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    final List<dynamic> heilmittelList = data['heilmittel'] is List ? data['heilmittel'] as List : [];

    // Helpers
    int hmDays(bool dringend) => dringend ? 14 : 28;
    bool hmIsExpired(bool dringend, String datum) {
      final d = DateTime.tryParse(datum); if (d == null) return false;
      return DateTime.now().isAfter(d.add(Duration(days: hmDays(dringend))));
    }
    String? hmExpiry(bool dringend, String datum) {
      final d = DateTime.tryParse(datum); if (d == null) return null;
      return DateFormat('dd.MM.yyyy').format(d.add(Duration(days: hmDays(dringend))));
    }

    const bereichItems = ['Physiotherapie', 'Ergotherapie', 'Logopädie / Sprachtherapie', 'Podologische Therapie', 'Ernährungstherapie'];
    const zuzahlungItems = ['Zuzahlungspflicht', 'Zuzahlungsfrei'];
    const heilmittelItems = [
      // Physiotherapie
      'KG – Krankengymnastik', 'MT – Manuelle Therapie', 'KMT – Klassische Massagetherapie',
      'MLD 30 – Lymphdrainage 30 min', 'MLD 45 – Lymphdrainage 45 min', 'MLD 60 – Lymphdrainage 60 min',
      'KPE – Komplexe Entstauungstherapie', 'KG-ZNS – KG bei ZNS-Erkrankung', 'KG-Gerät – Gerätegest. KG',
      'ET – Elektrotherapie', 'US – Ultraschall', 'FP – Fangopackung',
      'Ionto – Iontophorese', 'BGM – Bindegewebsmassage', 'UWM – Unterwasserdruckmassage',
      // Logopädie
      'Stimmtherapie – 30', 'Stimmtherapie – 45', 'Stimmtherapie – 60',
      'Sprechtherapie – 30', 'Sprechtherapie – 45', 'Sprechtherapie – 60',
      'Sprachtherapie – 30', 'Sprachtherapie – 45', 'Sprachtherapie – 60',
      'Schlucktherapie – 45', 'Schlucktherapie – 60',
      // Ergotherapie
      'Sensomotorisch-perzeptive Behandlung', 'Motorisch-funktionelle Behandlung',
      'Psychisch-funktionelle Behandlung', 'Hirnleistungstraining',
      // Podologie
      'Podologische Komplexbehandlung', 'Nagelkorrekturspange',
      // Ernährungstherapie
      'Ernährungstherapie – Einzelbehandlung', 'Ernährungstherapie – Gruppenbehandlung',
    ];
    const statusColors = {'ausgestellt': Colors.blue, 'begonnen': Colors.orange, 'abgeschlossen': Colors.green, 'abgelaufen': Colors.grey};
    const statusLabels = {'ausgestellt': 'Ausgestellt', 'begonnen': 'Begonnen', 'abgeschlossen': 'Abgeschlossen', 'abgelaufen': 'Abgelaufen'};
    const bereichColors = {'Physiotherapie': Colors.teal, 'Ergotherapie': Colors.purple, 'Logopädie / Sprachtherapie': Colors.indigo, 'Podologische Therapie': Colors.brown, 'Ernährungstherapie': Colors.green};
    const bereichShort = {'Physiotherapie': 'Physio', 'Ergotherapie': 'Ergo', 'Logopädie / Sprachtherapie': 'Logo', 'Podologische Therapie': 'Podo', 'Ernährungstherapie': 'Ernähr.'};

    void showHeilmittelDialog({Map<String, dynamic>? existing, int? editIndex}) async {
      final arztData = data['selected_arzt'] is Map ? data['selected_arzt'] as Map : {};

      // Auto-fill from Behörde Krankenkasse + Verifizierung (user data) for NEW entries
      Map<String, dynamic>? kkData;
      if (existing == null || editIndex == null) {
        try {
          final res = await widget.apiService.getBehoerdeData(widget.user.id, 'krankenkasse');
          if (res['data'] != null) kkData = Map<String, dynamic>.from(res['data']);
        } catch (_) {}
      }

      final datumC = TextEditingController(text: existing?['datum']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
      // Patient / Versicherung — auto-fill from Behörde Krankenkasse + User Verifizierung Stufe 1
      final krankenkasseC = TextEditingController(text: existing?['krankenkasse']?.toString() ?? kkData?['name']?.toString() ?? '');
      final patientNameC = TextEditingController(text: existing?['patient_name']?.toString() ?? widget.user.nachname ?? '');
      final patientVornameC = TextEditingController(text: existing?['patient_vorname']?.toString() ?? widget.user.vorname ?? '');
      final strasseNrC = TextEditingController(text: existing?['strasse_nr']?.toString() ?? '${widget.user.strasse ?? ''} ${widget.user.hausnummer ?? ''}'.trim());
      final plzC = TextEditingController(text: existing?['plz']?.toString() ?? widget.user.plz ?? '');
      final stadtC = TextEditingController(text: existing?['stadt']?.toString() ?? widget.user.ort ?? '');
      final kostentraegerkennungC = TextEditingController(text: existing?['kostentraegerkennung']?.toString() ?? kkData?['ehic_institutionskennzeichen']?.toString() ?? '');
      final versichertenNrC = TextEditingController(text: existing?['versicherten_nr']?.toString() ?? kkData?['versichertennummer']?.toString() ?? '');
      // Diagnosen
      final diagnose1Icd10C = TextEditingController(text: existing?['diagnose1_icd10']?.toString() ?? existing?['icd10']?.toString() ?? '');
      final diagnose1C = TextEditingController(text: existing?['diagnose1']?.toString() ?? existing?['diagnose']?.toString() ?? '');
      final diagnose2Icd10C = TextEditingController(text: existing?['diagnose2_icd10']?.toString() ?? '');
      final diagnose2C = TextEditingController(text: existing?['diagnose2']?.toString() ?? '');
      final diagnosegruppeC = TextEditingController(text: existing?['diagnosegruppe']?.toString() ?? existing?['indikation']?.toString() ?? '');
      final leitsymptomatikC = TextEditingController(text: existing?['leitsymptomatik']?.toString() ?? '');
      // Heilmittel
      final hm1C = TextEditingController(text: existing?['hm1']?.toString() ?? '');
      final hm1AnzahlC = TextEditingController(text: existing?['hm1_anzahl']?.toString() ?? '');
      final hm2C = TextEditingController(text: existing?['hm2']?.toString() ?? '');
      final hm2AnzahlC = TextEditingController(text: existing?['hm2_anzahl']?.toString() ?? '');
      final hm3C = TextEditingController(text: existing?['hm3']?.toString() ?? '');
      final hm3AnzahlC = TextEditingController(text: existing?['hm3_anzahl']?.toString() ?? '');
      final hmErgC = TextEditingController(text: existing?['hm_ergaenzend']?.toString() ?? '');
      final hmErgAnzahlC = TextEditingController(text: existing?['hm_erg_anzahl']?.toString() ?? '');
      final behandlungseinheitenC = TextEditingController(text: existing?['behandlungseinheiten']?.toString() ?? '');
      final frequenzC = TextEditingController(text: existing?['frequenz']?.toString() ?? '');
      // Arzt
      final bsnrC = TextEditingController(text: existing?['bsnr']?.toString() ?? arztData['bsnr']?.toString() ?? '');
      final lanrC = TextEditingController(text: existing?['lanr']?.toString() ?? arztData['lanr']?.toString() ?? '');
      final notizenC = TextEditingController(text: existing?['notizen']?.toString() ?? '');
      final begonnenDatumC = TextEditingController(text: existing?['begonnen_datum']?.toString() ?? '');
      final abgeschlossenDatumC = TextEditingController(text: existing?['abgeschlossen_datum']?.toString() ?? '');

      String bereich = existing?['bereich']?.toString() ?? bereichItems[0];
      String zuzahlungStatus = existing?['zuzahlung_status']?.toString() ?? 'Zuzahlungspflicht';
      String leitsymptomatikAbc = existing?['leitsymptomatik_abc']?.toString() ?? '';
      String status = existing?['status']?.toString() ?? 'ausgestellt';
      bool dringend = existing?['dringend'] == true || existing?['dringend'] == 'true';
      bool hausbesuch = existing?['hausbesuch'] == true || existing?['hausbesuch'] == 'true';
      bool therapiebericht = existing?['therapiebericht'] == true || existing?['therapiebericht'] == 'true';
      bool rezeptInPraxis = existing?['rezept_in_praxis'] == true || existing?['rezept_in_praxis'] == 'true';
      String rezeptInPraxisDatum = existing?['rezept_in_praxis_datum']?.toString() ?? '';
      bool terminPerEmail = existing?['termin_per_email'] == true || existing?['termin_per_email'] == 'true';

      void doSave(Map<String, dynamic> entry, {bool fromStatus = false, StateSetter? setS}) {
        final base = existing != null ? Map<String, dynamic>.from(existing) : <String, dynamic>{};
        base.addAll(entry);
        final list = List<dynamic>.from(heilmittelList);
        if (editIndex != null && editIndex < list.length) { list[editIndex] = base; } else { list.insert(0, base); }
        data['heilmittel'] = list;
        saveAll();
        setLocalState(() {});
        if (!fromStatus) Navigator.pop(context);
        if (setS != null) setS(() {});
      }

      Widget buildForm(StateSetter setS, void Function(Map<String, dynamic>) onSave) {
        Widget dropdown<T>(String label, T val, List<T> items, void Function(T) onChange, {IconData? icon}) => InputDecorator(
          decoration: InputDecoration(labelText: label, prefixIcon: icon != null ? Icon(icon, size: 16) : null, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          child: DropdownButton<T>(value: val, isExpanded: true, isDense: true, underline: const SizedBox.shrink(),
            items: items.map((e) => DropdownMenuItem(value: e, child: Text(e.toString(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
            onChanged: (v) { if (v != null) setS(() => onChange(v)); }),
        );
        Widget hmRow(String nr, TextEditingController nameC, TextEditingController anzahlC) => Row(children: [
          Expanded(flex: 4, child: InputDecorator(
            decoration: InputDecoration(labelText: 'Heilmittel $nr', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
            child: DropdownButton<String>(value: heilmittelItems.contains(nameC.text) ? nameC.text : null, hint: const Text('– auswählen –', style: TextStyle(fontSize: 12)), isExpanded: true, isDense: true, underline: const SizedBox.shrink(),
              items: [const DropdownMenuItem(value: '', child: Text('– keine –', style: TextStyle(fontSize: 12))), ...heilmittelItems.map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)))],
              onChanged: (v) => setS(() => nameC.text = v ?? '')),
          )),
          const SizedBox(width: 8),
          SizedBox(width: 64, child: TextFormField(controller: anzahlC, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: 'Anz.', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        ]);
        Widget hmCheck(String label, bool val, void Function(bool) onChange, MaterialColor col) => InkWell(
          onTap: () => setS(() => onChange(!val)),
          borderRadius: BorderRadius.circular(6),
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: val ? col.shade100 : Colors.grey.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: val ? col.shade400 : Colors.grey.shade300)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(val ? Icons.check_box : Icons.check_box_outline_blank, size: 14, color: val ? col.shade700 : Colors.grey.shade500),
              const SizedBox(width: 4),
              Text(label, style: TextStyle(fontSize: 11, color: val ? col.shade800 : Colors.grey.shade600, fontWeight: val ? FontWeight.bold : FontWeight.normal)),
            ])),
        );

        Widget sectionHeader(String title, IconData icon, MaterialColor color) => Padding(
          padding: const EdgeInsets.only(bottom: 8, top: 4),
          child: Row(children: [
            Icon(icon, size: 15, color: color.shade700),
            const SizedBox(width: 6),
            Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade700)),
          ]),
        );
        Widget tf(TextEditingController c, String label, {String? hint, int flex = 1, int? maxLines, TextInputType? keyboardType, double? width}) {
          final field = TextFormField(controller: c, maxLines: maxLines ?? 1, keyboardType: keyboardType, decoration: InputDecoration(labelText: label, hintText: hint, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8)));
          return width != null ? SizedBox(width: width, child: field) : Expanded(flex: flex, child: field);
        }

        return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // ── Heilmittelbereich + Datum ──
          Row(children: [
            Expanded(child: dropdown('Heilmittelbereich', bereich, bereichItems, (v) => bereich = v, icon: Icons.healing)),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Ausstellungsdatum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                final p = await showDatePicker(context: context, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                if (p != null) setS(() => datumC.text = DateFormat('yyyy-MM-dd').format(p));
              })))),
          ]),
          const SizedBox(height: 12),

          // ── Krankenkasse / Kostenträger ──
          sectionHeader('Krankenkasse / Kostenträger', Icons.account_balance, Colors.blue),
          Row(children: [
            tf(krankenkasseC, 'Krankenkasse', hint: 'z.B. AOK, TK, Barmer'),
            const SizedBox(width: 8),
            tf(kostentraegerkennungC, 'Kostenträgerkennung', hint: '9-stellig'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            tf(versichertenNrC, 'Versicherten-Nr.', hint: 'z.B. A123456789'),
            const SizedBox(width: 8),
            Expanded(child: dropdown('Zuzahlungsstatus', zuzahlungStatus, zuzahlungItems, (v) => zuzahlungStatus = v)),
          ]),
          const SizedBox(height: 12),

          // ── Versichertendaten (Patient) ──
          sectionHeader('Versichertendaten', Icons.person, Colors.indigo),
          Row(children: [
            tf(patientNameC, 'Name'),
            const SizedBox(width: 8),
            tf(patientVornameC, 'Vorname'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            tf(strasseNrC, 'Straße / Nr.', flex: 3),
            const SizedBox(width: 8),
            tf(plzC, 'PLZ', hint: '12345', flex: 1),
            const SizedBox(width: 8),
            tf(stadtC, 'Stadt', flex: 2),
          ]),
          const SizedBox(height: 12),

          // ── Behandlungsrelevante Diagnose(n) ──
          sectionHeader('Behandlungsrelevante Diagnose(n) (mind. 2)', Icons.medical_information, Colors.red),
          Row(children: [
            tf(diagnose1Icd10C, 'ICD-10 (1)', hint: 'z.B. M54.5', width: 110),
            const SizedBox(width: 8),
            tf(diagnose1C, 'Diagnose 1'),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            tf(diagnose2Icd10C, 'ICD-10 (2)', hint: 'z.B. G47.3', width: 110),
            const SizedBox(width: 8),
            tf(diagnose2C, 'Diagnose 2'),
          ]),
          const SizedBox(height: 12),

          // ── Diagnosegruppe ──
          TextFormField(controller: diagnosegruppeC, decoration: InputDecoration(labelText: 'Diagnosegruppe', hintText: 'z.B. EX3, WS2, SP6, ST1', prefixIcon: const Icon(Icons.category, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),

          // ── Leitsymptomatik ──
          sectionHeader('Leitsymptomatik', Icons.label_important, Colors.purple),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade100)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                for (final abc in ['a', 'b', 'c']) ...[
                  InkWell(
                    onTap: () => setS(() => leitsymptomatikAbc = leitsymptomatikAbc == abc ? '' : abc),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: leitsymptomatikAbc == abc ? Colors.purple.shade600 : Colors.white,
                        border: Border.all(color: leitsymptomatikAbc == abc ? Colors.purple.shade600 : Colors.purple.shade200, width: 2),
                      ),
                      child: Center(child: Text(abc, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: leitsymptomatikAbc == abc ? Colors.white : Colors.purple.shade400))),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                const SizedBox(width: 8),
                Expanded(child: Text('Patientenindividuelle Leitsymptomatik:', style: TextStyle(fontSize: 11, color: Colors.purple.shade600))),
              ]),
              const SizedBox(height: 8),
              TextFormField(controller: leitsymptomatikC, maxLines: 2, decoration: InputDecoration(hintText: 'Beschreibung der Leitsymptomatik...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
            ]),
          ),
          const SizedBox(height: 12),

          // ── Heilmittel nach Maßgabe des Katalogs ──
          sectionHeader('Heilmittel nach Maßgabe des Katalogs', Icons.healing, Colors.teal),
          hmRow('1', hm1C, hm1AnzahlC),
          const SizedBox(height: 6),
          hmRow('2', hm2C, hm2AnzahlC),
          const SizedBox(height: 6),
          hmRow('3', hm3C, hm3AnzahlC),
          const SizedBox(height: 8),
          Text('Ergänzendes Heilmittel', style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
          const SizedBox(height: 4),
          hmRow('Erg.', hmErgC, hmErgAnzahlC),
          const SizedBox(height: 10),

          // ── Behandlungseinheiten ──
          Row(children: [
            tf(behandlungseinheitenC, 'Behandlungseinheiten', hint: 'z.B. 10', keyboardType: TextInputType.number),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(controller: frequenzC, decoration: InputDecoration(labelText: 'Therapiefrequenz', hintText: 'z.B. 1-2x pro Woche', prefixIcon: const Icon(Icons.repeat, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 10),

          // ── Checkboxen: Therapiebericht, Hausbesuch, Dringlicher Behandlungsbedarf ──
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade100)),
            child: Wrap(spacing: 6, runSpacing: 6, children: [
              hmCheck('Therapiebericht', therapiebericht, (v) => therapiebericht = v, Colors.blue),
              hmCheck('Hausbesuch', hausbesuch, (v) => hausbesuch = v, Colors.orange),
              hmCheck('Dringlicher Behandlungsbedarf', dringend, (v) => dringend = v, Colors.red),
            ])),
          const SizedBox(height: 10),

          // ── Status + BSNR/LANR ──
          Row(children: [
            Expanded(child: dropdown('Status', status, statusLabels.keys.toList(), (v) => status = v, icon: Icons.flag)),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(controller: bsnrC, decoration: InputDecoration(labelText: 'BSNR', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextFormField(controller: lanrC, decoration: InputDecoration(labelText: 'LANR', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
          ]),
          const SizedBox(height: 10),
          TextFormField(controller: notizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Therapieziele / Notizen', prefixIcon: const Icon(Icons.notes, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),

          // ── Rezept in Praxis + Termin per E-Mail ──
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: rezeptInPraxis ? Colors.green.shade50 : Colors.orange.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: rezeptInPraxis ? Colors.green.shade200 : Colors.orange.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(rezeptInPraxis ? Icons.check_circle : Icons.pending, size: 16, color: rezeptInPraxis ? Colors.green.shade700 : Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text('Rezept in Praxis angekommen?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: rezeptInPraxis ? Colors.green.shade700 : Colors.orange.shade700)),
                  const Spacer(),
                  Switch(value: rezeptInPraxis, activeThumbColor: Colors.green.shade600, onChanged: (v) => setS(() { rezeptInPraxis = v; if (!v) rezeptInPraxisDatum = ''; })),
                ]),
                if (rezeptInPraxis) ...[
                  const SizedBox(height: 6),
                  Row(children: [
                    Icon(Icons.event, size: 14, color: Colors.green.shade600),
                    const SizedBox(width: 6),
                    Text('Angekommen am:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(rezeptInPraxisDatum) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                        if (picked != null) setS(() => rezeptInPraxisDatum = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}');
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
                        child: Text(rezeptInPraxisDatum.isNotEmpty ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(rezeptInPraxisDatum)); } catch (_) { return rezeptInPraxisDatum; } })() : 'Datum wahlen', style: TextStyle(fontSize: 12, color: rezeptInPraxisDatum.isNotEmpty ? Colors.black87 : Colors.grey.shade400)),
                      ),
                    ),
                  ]),
                ],
                const SizedBox(height: 8),
                Row(children: [
                  Icon(terminPerEmail ? Icons.mark_email_read : Icons.email_outlined, size: 16, color: terminPerEmail ? Colors.blue.shade700 : Colors.grey.shade500),
                  const SizedBox(width: 6),
                  Text('Terminbestatigung per E-Mail abwarten', style: TextStyle(fontSize: 12, color: terminPerEmail ? Colors.blue.shade700 : Colors.grey.shade600)),
                  const Spacer(),
                  Switch(value: terminPerEmail, activeThumbColor: Colors.blue.shade600, onChanged: (v) => setS(() => terminPerEmail = v)),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Verordnung speichern'),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
            onPressed: () {
              if (diagnose1C.text.trim().isEmpty || diagnose2C.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens 2 Diagnosen angeben'), backgroundColor: Colors.red));
                return;
              }
              if (hm1C.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte mindestens ein Heilmittel auswählen'), backgroundColor: Colors.red));
                return;
              }
              onSave({
                'datum': datumC.text, 'bereich': bereich,
                'krankenkasse': krankenkasseC.text.trim(), 'kostentraegerkennung': kostentraegerkennungC.text.trim(),
                'versicherten_nr': versichertenNrC.text.trim(), 'zuzahlung_status': zuzahlungStatus,
                'patient_name': patientNameC.text.trim(), 'patient_vorname': patientVornameC.text.trim(),
                'strasse_nr': strasseNrC.text.trim(), 'plz': plzC.text.trim(), 'stadt': stadtC.text.trim(),
                'diagnose1_icd10': diagnose1Icd10C.text.trim(), 'diagnose1': diagnose1C.text.trim(),
                'diagnose2_icd10': diagnose2Icd10C.text.trim(), 'diagnose2': diagnose2C.text.trim(),
                'diagnosegruppe': diagnosegruppeC.text.trim(),
                'leitsymptomatik_abc': leitsymptomatikAbc, 'leitsymptomatik': leitsymptomatikC.text.trim(),
                'hm1': hm1C.text.trim(), 'hm1_anzahl': hm1AnzahlC.text.trim(),
                'hm2': hm2C.text.trim(), 'hm2_anzahl': hm2AnzahlC.text.trim(),
                'hm3': hm3C.text.trim(), 'hm3_anzahl': hm3AnzahlC.text.trim(),
                'hm_ergaenzend': hmErgC.text.trim(), 'hm_erg_anzahl': hmErgAnzahlC.text.trim(),
                'behandlungseinheiten': behandlungseinheitenC.text.trim(),
                'frequenz': frequenzC.text.trim(), 'dringend': dringend,
                'hausbesuch': hausbesuch, 'therapiebericht': therapiebericht,
                'status': status, 'bsnr': bsnrC.text.trim(), 'lanr': lanrC.text.trim(),
                'notizen': notizenC.text.trim(),
                'rezept_in_praxis': rezeptInPraxis,
                'rezept_in_praxis_datum': rezeptInPraxisDatum,
                'termin_per_email': terminPerEmail,
                'ausgestellt_von': () { final n = arztData['arzt_name']?.toString() ?? ''; final p = arztData['praxis_name']?.toString() ?? ''; return n.isNotEmpty && p.isNotEmpty ? '$n – $p' : n.isNotEmpty ? n : p.isNotEmpty ? p : arztTitle; }(),
              });
            },
          )),
        ]));
      }

      // ── Auto-expire ──
      final exDatum = existing?['datum']?.toString() ?? '';
      final exDringend = existing?['dringend'] == true || existing?['dringend'] == 'true';
      if (hmIsExpired(exDringend, exDatum) && status != 'abgelaufen') {
        status = 'abgelaufen';
        doSave({'status': 'abgelaufen'}, fromStatus: true);
      }

      if (!mounted) return;
      if (editIndex == null) {
        showDialog(context: context, builder: (dlgCtx) => StatefulBuilder(
          builder: (dlgCtx, setS) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            title: Row(children: [
              Icon(Icons.healing, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              const Expanded(child: Text('Neue Heilmittelverordnung (Muster 13)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
            ]),
            content: SizedBox(width: 620, height: 700, child: buildForm(setS, doSave)),
          ),
        ));
        return;
      }

      // Existing: tabbed view
      final r = existing ?? <String, dynamic>{};
      showDialog(context: context, builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setS) {
          bool editMode = false;
          return StatefulBuilder(builder: (dlgCtx2, setS2) => AlertDialog(
            contentPadding: EdgeInsets.zero,
            titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            title: Row(children: [
              Icon(Icons.healing, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r['bereich']?.toString() ?? 'Heilmittelverordnung', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                if ((r['datum']?.toString() ?? '').isNotEmpty)
                  Text(() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(r['datum'].toString())); } catch (_) { return r['datum'].toString(); } }(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ])),
              if (!editMode) IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.teal.shade600), tooltip: 'Bearbeiten', onPressed: () => setS2(() => editMode = true), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
            ]),
            content: SizedBox(
              width: 620, height: 700,
              child: editMode
                ? buildForm(setS2, (entry) { doSave(entry); Navigator.pop(dlgCtx); })
                : DefaultTabController(length: 3, child: Column(children: [
                    TabBar(labelColor: Colors.teal.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.teal.shade700, tabs: const [
                      Tab(icon: Icon(Icons.healing, size: 16), text: 'Details'),
                      Tab(icon: Icon(Icons.track_changes, size: 16), text: 'Verlauf'),
                      Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
                    ]),
                    Expanded(child: TabBarView(children: [
                      // ── Details (read-only) ──
                      SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Badges row
                        Row(children: [
                          () {
                            final b = r['bereich']?.toString() ?? 'Physiotherapie';
                            final c = (bereichColors[b] ?? Colors.teal);
                            return Container(margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.shade300)),
                              child: Text(bereichShort[b] ?? b, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.shade800)));
                          }(),
                          () {
                            final st = r['status']?.toString() ?? 'ausgestellt';
                            final c = (statusColors[st] ?? Colors.grey);
                            return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: c.shade100, borderRadius: BorderRadius.circular(20)),
                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.flag, size: 11, color: c.shade600),
                                const SizedBox(width: 4),
                                Text(statusLabels[st] ?? st, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: c.shade700)),
                              ]));
                          }(),
                          const Spacer(),
                          if (r['dringend'] == true) Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(12)), child: Text('Dringend', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
                          if (r['hausbesuch'] == true) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)), child: Text('Hausbesuch', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800)))],
                          if (r['therapiebericht'] == true) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)), child: Text('Bericht', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.blue.shade800)))],
                        ]),
                        const SizedBox(height: 8),
                        // Gültigkeit
                        () {
                          final d = r['dringend'] == true;
                          final expired = hmIsExpired(d, r['datum']?.toString() ?? '');
                          final expStr = hmExpiry(d, r['datum']?.toString() ?? '');
                          if (expStr == null) return const SizedBox.shrink();
                          return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(color: expired ? Colors.red.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: expired ? Colors.red.shade200 : Colors.grey.shade200)),
                            child: Row(children: [
                              Icon(expired ? Icons.warning_amber_rounded : Icons.schedule, size: 14, color: expired ? Colors.red.shade600 : Colors.grey.shade600),
                              const SizedBox(width: 6),
                              Text('Gültig ${d ? 14 : 28} Tage', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              const Spacer(),
                              Text(expired ? 'Abgelaufen am $expStr' : 'Läuft ab: $expStr', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: expired ? Colors.red.shade700 : Colors.grey.shade700)),
                            ]));
                        }(),
                        // Krankenkasse / Versicherung
                        if ((r['krankenkasse']?.toString() ?? '').isNotEmpty) _rezeptDetailRow(Icons.account_balance, 'Krankenkasse', '${r['krankenkasse']}${(r['kostentraegerkennung']?.toString() ?? '').isNotEmpty ? ' (${r['kostentraegerkennung']})' : ''}'),
                        if ((r['versicherten_nr']?.toString() ?? '').isNotEmpty) _rezeptDetailRow(Icons.badge, 'Versicherten-Nr.', r['versicherten_nr'].toString()),
                        if ((r['zuzahlung_status']?.toString() ?? '').isNotEmpty) _rezeptDetailRow(Icons.euro, 'Zuzahlung', r['zuzahlung_status'].toString()),
                        // Patient
                        if ((r['patient_name']?.toString() ?? '').isNotEmpty || (r['patient_vorname']?.toString() ?? '').isNotEmpty)
                          _rezeptDetailRow(Icons.person, 'Patient', '${r['patient_vorname'] ?? ''} ${r['patient_name'] ?? ''}'.trim()),
                        if ((r['strasse_nr']?.toString() ?? '').isNotEmpty)
                          _rezeptDetailRow(Icons.home, 'Adresse', '${r['strasse_nr']}, ${r['plz'] ?? ''} ${r['stadt'] ?? ''}'.trim()),
                        const Divider(height: 12),
                        // Diagnosen
                        if ((r['diagnose1_icd10']?.toString() ?? '').isNotEmpty || (r['diagnose1']?.toString() ?? '').isNotEmpty)
                          _rezeptDetailRow(Icons.medical_information, 'Diagnose 1', '${r['diagnose1_icd10'] ?? ''} – ${r['diagnose1'] ?? ''}'.trim()),
                        if ((r['diagnose2_icd10']?.toString() ?? '').isNotEmpty || (r['diagnose2']?.toString() ?? '').isNotEmpty)
                          _rezeptDetailRow(Icons.medical_information, 'Diagnose 2', '${r['diagnose2_icd10'] ?? ''} – ${r['diagnose2'] ?? ''}'.trim()),
                        // Legacy support
                        if ((r['icd10']?.toString() ?? '').isNotEmpty && (r['diagnose1_icd10']?.toString() ?? '').isEmpty)
                          _rezeptDetailRow(Icons.code, 'ICD-10', '${r['icd10']} – ${r['diagnose'] ?? ''}'),
                        if ((r['diagnosegruppe']?.toString() ?? '').isNotEmpty) _rezeptDetailRow(Icons.category, 'Diagnosegruppe', r['diagnosegruppe'].toString()),
                        // Legacy indikation
                        if ((r['indikation']?.toString() ?? '').isNotEmpty && (r['diagnosegruppe']?.toString() ?? '').isEmpty) _rezeptDetailRow(Icons.category, 'Indikationsschlüssel', r['indikation'].toString()),
                        if ((r['leitsymptomatik_abc']?.toString() ?? '').isNotEmpty || (r['leitsymptomatik']?.toString() ?? '').isNotEmpty)
                          _rezeptDetailRow(Icons.label_important, 'Leitsymptomatik', '${(r['leitsymptomatik_abc']?.toString() ?? '').isNotEmpty ? '(${r['leitsymptomatik_abc']}) ' : ''}${r['leitsymptomatik'] ?? ''}'.trim()),
                        const Divider(height: 16),
                        Text('Heilmittel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                        const SizedBox(height: 6),
                        for (final entry in [('hm1', 'hm1_anzahl', 'Vorrangig 1'), ('hm2', 'hm2_anzahl', 'Vorrangig 2'), ('hm3', 'hm3_anzahl', 'Vorrangig 3'), ('hm_ergaenzend', 'hm_erg_anzahl', 'Ergänzend')])
                          if ((r[entry.$1]?.toString() ?? '').isNotEmpty)
                            Container(margin: const EdgeInsets.only(bottom: 4), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade100)),
                              child: Row(children: [
                                Text(entry.$3, style: TextStyle(fontSize: 10, color: Colors.teal.shade600, fontWeight: FontWeight.bold)),
                                const SizedBox(width: 8),
                                Expanded(child: Text(r[entry.$1].toString(), style: const TextStyle(fontSize: 12))),
                                if ((r[entry.$2]?.toString() ?? '').isNotEmpty) Text('× ${r[entry.$2]}', style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                              ])),
                        if ((r['behandlungseinheiten']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), _rezeptDetailRow(Icons.numbers, 'Behandlungseinheiten', r['behandlungseinheiten'].toString())],
                        if ((r['frequenz']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), _rezeptDetailRow(Icons.repeat, 'Therapiefrequenz', r['frequenz'].toString())],
                        if ((r['notizen']?.toString() ?? '').isNotEmpty) ...[const Divider(height: 16), _rezeptDetailRow(Icons.notes, 'Notizen', r['notizen'].toString())],

                        // ── Rezept in Praxis + Termin per E-Mail ──
                        const Divider(height: 16),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: (r['rezept_in_praxis'] == true) ? Colors.green.shade50 : Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: (r['rezept_in_praxis'] == true) ? Colors.green.shade200 : Colors.orange.shade200),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Icon((r['rezept_in_praxis'] == true) ? Icons.check_circle : Icons.pending, size: 16, color: (r['rezept_in_praxis'] == true) ? Colors.green.shade700 : Colors.orange.shade700),
                                const SizedBox(width: 6),
                                Text('Rezept in Praxis angekommen?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: (r['rezept_in_praxis'] == true) ? Colors.green.shade700 : Colors.orange.shade700)),
                                const Spacer(),
                                Switch(value: r['rezept_in_praxis'] == true, activeThumbColor: Colors.green.shade600, onChanged: (v) {
                                  setS2(() {
                                    r['rezept_in_praxis'] = v;
                                    if (!v) r.remove('rezept_in_praxis_datum');
                                  });
                                  doSave({'rezept_in_praxis': v, if (!v) 'rezept_in_praxis_datum': ''});
                                }),
                              ]),
                              if (r['rezept_in_praxis'] == true) ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  Icon(Icons.event, size: 14, color: Colors.green.shade600),
                                  const SizedBox(width: 6),
                                  Text('Angekommen am:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  const SizedBox(width: 8),
                                  InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(context: context, initialDate: DateTime.tryParse(r['rezept_in_praxis_datum']?.toString() ?? '') ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                      if (picked != null) {
                                        final fmt = '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
                                        setS2(() => r['rezept_in_praxis_datum'] = fmt);
                                        doSave({'rezept_in_praxis_datum': fmt});
                                      }
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
                                      child: Text(
                                        (r['rezept_in_praxis_datum']?.toString() ?? '').isNotEmpty ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(r['rezept_in_praxis_datum'].toString())); } catch (_) { return r['rezept_in_praxis_datum'].toString(); } })() : 'Datum wahlen',
                                        style: TextStyle(fontSize: 12, color: (r['rezept_in_praxis_datum']?.toString() ?? '').isNotEmpty ? Colors.black87 : Colors.grey.shade400),
                                      ),
                                    ),
                                  ),
                                ]),
                              ],
                              const SizedBox(height: 8),
                              Row(children: [
                                Icon((r['termin_per_email'] == true) ? Icons.mark_email_read : Icons.email_outlined, size: 16, color: (r['termin_per_email'] == true) ? Colors.blue.shade700 : Colors.grey.shade500),
                                const SizedBox(width: 6),
                                Text('Terminbestatigung per E-Mail abwarten', style: TextStyle(fontSize: 12, color: (r['termin_per_email'] == true) ? Colors.blue.shade700 : Colors.grey.shade600)),
                                const Spacer(),
                                Switch(value: r['termin_per_email'] == true, activeThumbColor: Colors.blue.shade600, onChanged: (v) {
                                  setS2(() => r['termin_per_email'] = v);
                                  doSave({'termin_per_email': v});
                                }),
                              ]),
                            ],
                          ),
                        ),

                        // ── Termin planen + Ticket ──
                        const Divider(height: 20),
                        if ((r['termin_ticket_id']?.toString() ?? '').isNotEmpty) ...[
                          // Ticket already created
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade200)),
                            child: Row(children: [
                              Icon(Icons.check_circle, size: 20, color: Colors.green.shade600),
                              const SizedBox(width: 10),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('Termin-Ticket erstellt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                                const SizedBox(height: 2),
                                Text('Ticket #${r['termin_ticket_id']} – ${r['termin_datum'] ?? 'Datum ausstehend'}', style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                                if ((r['termin_ort']?.toString() ?? '').isNotEmpty)
                                  Text('Ort: ${r['termin_ort']}', style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                              ])),
                            ]),
                          ),
                        ] else ...[
                          // Termin planen button
                          SizedBox(width: double.infinity, child: OutlinedButton.icon(
                            icon: Icon(Icons.calendar_month, size: 16, color: Colors.purple.shade600),
                            label: Text('Termin planen', style: TextStyle(color: Colors.purple.shade600, fontWeight: FontWeight.bold)),
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.purple.shade300),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            onPressed: () async {
                              // Show date/time/location picker
                              final terminDatumC = TextEditingController();
                              final terminZeitC = TextEditingController(text: '14:00');
                              final terminOrtC = TextEditingController();
                              final terminNotizenC = TextEditingController();
                              final bereichText = r['bereich']?.toString() ?? 'Heilmittel';
                              final patientText = '${r['patient_vorname'] ?? ''} ${r['patient_name'] ?? ''}'.trim();
                              final hms = [r['hm1'], r['hm2'], r['hm3']].where((h) => (h?.toString() ?? '').isNotEmpty).map((h) => h.toString()).toList();

                              final confirmed = await showDialog<bool>(context: context, builder: (tCtx) => StatefulBuilder(
                                builder: (tCtx, tSetS) => AlertDialog(
                                  title: Row(children: [
                                    Icon(Icons.calendar_month, size: 20, color: Colors.purple.shade600),
                                    const SizedBox(width: 8),
                                    const Expanded(child: Text('Termin planen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                    IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(tCtx, false), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                                  ]),
                                  content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
                                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                        Text('$bereichText${patientText.isNotEmpty ? ' – $patientText' : ''}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                                        if (hms.isNotEmpty) Text(hms.join(', '), style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                                      ]),
                                    ),
                                    const SizedBox(height: 12),
                                    Row(children: [
                                      Expanded(child: TextFormField(controller: terminDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.event, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                          final p = await showDatePicker(context: tCtx, initialDate: DateTime.now().add(const Duration(days: 1)), firstDate: DateTime.now(), lastDate: DateTime(2099), locale: const Locale('de'));
                                          if (p != null) tSetS(() => terminDatumC.text = DateFormat('yyyy-MM-dd').format(p));
                                        })))),
                                      const SizedBox(width: 8),
                                      SizedBox(width: 100, child: TextFormField(controller: terminZeitC, decoration: InputDecoration(labelText: 'Uhrzeit', hintText: '14:00', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                    ]),
                                    const SizedBox(height: 10),
                                    Row(children: [
                                      Expanded(child: TextFormField(controller: terminOrtC, decoration: InputDecoration(labelText: 'Ort / Praxis', hintText: 'z.B. Praxis Dr. Müller, Hauptstr. 5', prefixIcon: const Icon(Icons.place, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                      const SizedBox(width: 4),
                                      PopupMenuButton<Map<String, String>>(
                                        icon: Icon(Icons.list_alt, size: 20, color: Colors.purple.shade600),
                                        tooltip: 'Aus Praxis-Datenbank',
                                        onSelected: (praxis) => tSetS(() {
                                          terminOrtC.text = '${praxis['name']}, ${praxis['strasse']}, ${praxis['plz']} ${praxis['ort']}';
                                        }),
                                        itemBuilder: (_) => _physioPraxenDB.map((p) => PopupMenuItem(
                                          value: p,
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text(p['name']!, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            Text('${p['strasse']}, ${p['plz']} ${p['ort']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                            Text('Tel: ${p['telefon']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                          ]),
                                        )).toList(),
                                      ),
                                    ]),
                                    const SizedBox(height: 10),
                                    TextFormField(controller: terminNotizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen für das Ticket', hintText: 'Zusätzliche Hinweise...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                  ])),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(tCtx, false), child: const Text('Abbrechen')),
                                    FilledButton.icon(
                                      icon: const Icon(Icons.send, size: 16),
                                      label: const Text('Termin erstellen & Ticket senden'),
                                      style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600),
                                      onPressed: () {
                                        if (terminDatumC.text.isEmpty) {
                                          ScaffoldMessenger.of(tCtx).showSnackBar(const SnackBar(content: Text('Bitte Datum auswählen'), backgroundColor: Colors.red));
                                          return;
                                        }
                                        Navigator.pop(tCtx, true);
                                      },
                                    ),
                                  ],
                                ),
                              ));

                              if (confirmed != true || !mounted) return;

                              // Create ticket for the member
                              try {
                                final diagnoseText = [
                                  if ((r['diagnose1_icd10']?.toString() ?? '').isNotEmpty) '${r['diagnose1_icd10']} – ${r['diagnose1'] ?? ''}',
                                  if ((r['diagnose2_icd10']?.toString() ?? '').isNotEmpty) '${r['diagnose2_icd10']} – ${r['diagnose2'] ?? ''}',
                                ].join('\n');
                                final terminDatumFmt = () { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(terminDatumC.text)); } catch (_) { return terminDatumC.text; } }();

                                final ticketResult = await widget.ticketService.createTicketForMember(
                                  adminMitgliedernummer: widget.adminMitgliedernummer,
                                  memberMitgliedernummer: widget.user.mitgliedernummer,
                                  subject: 'Heilmittel-Termin: $bereichText – $terminDatumFmt ${terminZeitC.text}',
                                  message: 'Sehr geehrtes Mitglied,\n\n'
                                      'Für Ihre Heilmittelverordnung ($bereichText) wurde ein Termin geplant:\n\n'
                                      'Datum: $terminDatumFmt\n'
                                      'Uhrzeit: ${terminZeitC.text}\n'
                                      '${terminOrtC.text.isNotEmpty ? 'Ort: ${terminOrtC.text}\n' : ''}'
                                      '\nHeilmittel: ${hms.join(', ')}\n'
                                      '${(r['behandlungseinheiten']?.toString() ?? '').isNotEmpty ? 'Behandlungseinheiten: ${r['behandlungseinheiten']}\n' : ''}'
                                      '${diagnoseText.isNotEmpty ? '\nDiagnosen:\n$diagnoseText\n' : ''}'
                                      '${terminNotizenC.text.isNotEmpty ? '\nHinweise: ${terminNotizenC.text}\n' : ''}'
                                      '\nBitte bestätigen Sie den Termin.',
                                  priority: r['dringend'] == true ? 'high' : 'medium',
                                  scheduledDate: terminDatumC.text,
                                );

                                if (!mounted) return;

                                if (ticketResult.containsKey('ticket')) {
                                  // Save ticket info to heilmittel entry
                                  final ticketId = (ticketResult['ticket'] as dynamic).id?.toString() ?? '';
                                  r['termin_ticket_id'] = ticketId;
                                  r['termin_datum'] = '$terminDatumFmt ${terminZeitC.text}';
                                  r['termin_ort'] = terminOrtC.text.trim();
                                  doSave(r, fromStatus: true, setS: setS2);

                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Termin geplant & Ticket #$ticketId erstellt'),
                                    backgroundColor: Colors.green,
                                  ));
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Fehler: ${ticketResult['error'] ?? 'Unbekannt'}'),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                    content: Text('Fehler: $e'),
                                    backgroundColor: Colors.red,
                                  ));
                                }
                              }
                            },
                          )),
                        ],
                      ])),

                      // ── Verlauf (tracking) ──
                      StatefulBuilder(builder: (verlaufCtx, setVerlauf) {
                        final therapeutC = TextEditingController(text: r['therapeut']?.toString() ?? '');
                        final therapeutPraxisC = TextEditingController(text: r['therapeut_praxis']?.toString() ?? '');
                        // Use r['sitzungen'] directly, not a copy, so changes persist across rebuilds
                        if (r['sitzungen'] is! List) r['sitzungen'] = [];
                        final List<dynamic> sitzungen = r['sitzungen'] as List;
                        const sitzungStatusList = ['ausstehend', 'wahrgenommen', 'nicht_wahrgenommen', 'verschoben_kunde', 'verschoben_praxis'];
                        const sitzungStatusLabels = {
                          'ausstehend': 'Ausstehend',
                          'wahrgenommen': 'Wahrgenommen',
                          'nicht_wahrgenommen': 'Nicht wahrgenommen',
                          'verschoben_kunde': 'Verschoben (Kunde)',
                          'verschoben_praxis': 'Verschoben (Praxis)',
                        };
                        final sitzungStatusColors = {
                          'ausstehend': Colors.orange,
                          'wahrgenommen': Colors.green,
                          'nicht_wahrgenommen': Colors.red,
                          'verschoben_kunde': Colors.amber,
                          'verschoben_praxis': Colors.blue,
                        };
                        final sitzungStatusIcons = {
                          'ausstehend': Icons.schedule,
                          'wahrgenommen': Icons.check_circle,
                          'nicht_wahrgenommen': Icons.cancel,
                          'verschoben_kunde': Icons.person_off,
                          'verschoben_praxis': Icons.store,
                        };
                        String getSitzungStatus(Map<String, dynamic> s) {
                          // backward compat: old entries have 'onorat' bool
                          if ((s['sitzung_status']?.toString() ?? '').isNotEmpty) return s['sitzung_status'].toString();
                          if (s['onorat'] == true || s['onorat'] == 'true') return 'wahrgenommen';
                          return 'ausstehend';
                        }

                        return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Therapie-Verlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                          const SizedBox(height: 12),

                          // ── Physiotherapie Praxis ──
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade100)),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Icon(Icons.local_hospital, size: 16, color: Colors.indigo.shade700),
                                const SizedBox(width: 6),
                                Text('Physiotherapie Praxis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                                const Spacer(),
                                TextButton.icon(
                                  icon: Icon(Icons.search, size: 14, color: Colors.indigo.shade600),
                                  label: Text(r['physio_praxis_name'] != null ? 'Andern' : 'Auswahlen', style: TextStyle(fontSize: 10, color: Colors.indigo.shade600)),
                                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                                  onPressed: () {
                                    _showArztSucheDialog(context, 'Physiotherapie', (praxis) {
                                      r['physio_praxis_name'] = praxis['praxis_name']?.toString() ?? '';
                                      r['physio_praxis_strasse'] = praxis['strasse']?.toString() ?? '';
                                      r['physio_praxis_plz_ort'] = praxis['plz_ort']?.toString() ?? '';
                                      r['physio_praxis_telefon'] = praxis['telefon']?.toString() ?? '';
                                      r['physio_praxis_email'] = praxis['email']?.toString() ?? '';
                                      doSave(r, fromStatus: true);
                                      setVerlauf(() {});
                                    });
                                  },
                                ),
                              ]),
                              if ((r['physio_praxis_name']?.toString() ?? '').isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(r['physio_praxis_name'].toString(), style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                                if ((r['physio_praxis_strasse']?.toString() ?? '').isNotEmpty || (r['physio_praxis_plz_ort']?.toString() ?? '').isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                                    Icon(Icons.place, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text('${r['physio_praxis_strasse'] ?? ''}, ${r['physio_praxis_plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ])),
                                if ((r['physio_praxis_telefon']?.toString() ?? '').isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                                    Icon(Icons.phone, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(r['physio_praxis_telefon'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ])),
                                if ((r['physio_praxis_email']?.toString() ?? '').isNotEmpty)
                                  Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                                    Icon(Icons.email, size: 12, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(r['physio_praxis_email'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ])),
                              ],
                            ]),
                          ),
                          const SizedBox(height: 12),

                          // ── Sitzungen / Behandlungstermine ──
                          Row(children: [
                            Icon(Icons.event_note, size: 16, color: Colors.purple.shade700),
                            const SizedBox(width: 6),
                            Text('Behandlungstermine (Sitzungen)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                            const Spacer(),
                            FilledButton.icon(
                              icon: const Icon(Icons.add, size: 14),
                              label: const Text('Sitzung', style: TextStyle(fontSize: 11)),
                              style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                              onPressed: () {
                                final sDatumC = TextEditingController();
                                final sZeitC = TextEditingController(text: '14:00');
                                final sNotizenC = TextEditingController();
                                final sAnzahlC = TextEditingController(text: '1');
                                final sIntervalC = TextEditingController(text: '7');
                                showDialog(context: context, builder: (sCtx) => StatefulBuilder(
                                  builder: (sCtx, setSitzState) {
                                    final anzahl = int.tryParse(sAnzahlC.text) ?? 1;
                                    final interval = int.tryParse(sIntervalC.text) ?? 7;
                                    return AlertDialog(
                                      title: Row(children: [
                                        Icon(Icons.add_circle, size: 18, color: Colors.purple.shade600),
                                        const SizedBox(width: 8),
                                        const Expanded(child: Text('Sitzungen hinzufugen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                                      ]),
                                      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                        Row(children: [
                                          Expanded(child: TextFormField(controller: sDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Erste Sitzung am *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                              final p = await showDatePicker(context: sCtx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                                              if (p != null) setSitzState(() => sDatumC.text = DateFormat('yyyy-MM-dd').format(p));
                                            })))),
                                          const SizedBox(width: 8),
                                          SizedBox(width: 80, child: TextFormField(controller: sZeitC, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                        ]),
                                        const SizedBox(height: 10),
                                        TextFormField(controller: sNotizenC, decoration: InputDecoration(labelText: 'Therapeut/in Name', hintText: 'z.B. Frau Muller', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                        const SizedBox(height: 12),
                                        // Batch: Anzahl + Interval
                                        Container(
                                          padding: const EdgeInsets.all(10),
                                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
                                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                            Text('Mehrere Sitzungen auf einmal', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                                            const SizedBox(height: 8),
                                            Row(children: [
                                              SizedBox(width: 80, child: TextFormField(controller: sAnzahlC, keyboardType: TextInputType.number, onChanged: (_) => setSitzState(() {}), decoration: InputDecoration(labelText: 'Anzahl', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                              const SizedBox(width: 8),
                                              Text('Sitzungen alle', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                              const SizedBox(width: 8),
                                              SizedBox(width: 60, child: TextFormField(controller: sIntervalC, keyboardType: TextInputType.number, onChanged: (_) => setSitzState(() {}), decoration: InputDecoration(labelText: 'Tage', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
                                            ]),
                                            if (anzahl > 1 && sDatumC.text.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Text('Vorschau: ${sitzungen.length + 1} bis ${sitzungen.length + anzahl}', style: TextStyle(fontSize: 11, color: Colors.purple.shade600)),
                                              const SizedBox(height: 4),
                                              ...List.generate(anzahl > 15 ? 15 : anzahl, (i) {
                                                final d = DateTime.parse(sDatumC.text).add(Duration(days: i * interval));
                                                return Text('  ${sitzungen.length + i + 1}. ${DateFormat('dd.MM.yyyy (EEEE)', 'de').format(d)} um ${sZeitC.text}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600));
                                              }),
                                              if (anzahl > 15) Text('  ... und ${anzahl - 15} weitere', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                            ],
                                          ]),
                                        ),
                                      ]))),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(sCtx), child: const Text('Abbrechen')),
                                        FilledButton(
                                          style: FilledButton.styleFrom(backgroundColor: Colors.purple.shade600),
                                          onPressed: () {
                                            if (sDatumC.text.isEmpty) {
                                              ScaffoldMessenger.of(sCtx).showSnackBar(const SnackBar(content: Text('Bitte Datum wahlen'), backgroundColor: Colors.red));
                                              return;
                                            }
                                            // Close dialog FIRST to prevent double-tap
                                            Navigator.pop(sCtx);
                                            final startDate = DateTime.parse(sDatumC.text);
                                            final praxisName = r['physio_praxis_name']?.toString() ?? '';
                                            final praxisOrt = [r['physio_praxis_strasse']?.toString() ?? '', r['physio_praxis_plz_ort']?.toString() ?? ''].where((s) => s.isNotEmpty).join(', ');
                                            final bereich = r['bereich']?.toString() ?? 'Physiotherapie';
                                            final timeParts = sZeitC.text.trim().split(':');
                                            final h = int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '14') ?? 14;
                                            final m = timeParts.length > 1 ? (int.tryParse(timeParts[1]) ?? 0) : 0;

                                            widget.terminService.setToken(widget.apiService.token ?? '');

                                            for (int i = 0; i < anzahl; i++) {
                                              final sDate = startDate.add(Duration(days: i * interval));
                                              final nr = sitzungen.length + 1;
                                              final sitzung = <String, dynamic>{
                                                'nr': '$nr',
                                                'datum': DateFormat('yyyy-MM-dd').format(sDate),
                                                'zeit': sZeitC.text.trim(),
                                                'notizen': sNotizenC.text.trim(),
                                                'onorat': false,
                                                'tv_created': true,
                                              };
                                              sitzungen.add(sitzung);
                                              // Auto-create in Terminverwaltung
                                              try {
                                                final terminDate = sDate.add(Duration(hours: h, minutes: m));
                                                final title = '$bereich Sitzung $nr${praxisName.isNotEmpty ? ' - $praxisName' : ''}';
                                                final loc = praxisOrt.isNotEmpty ? praxisOrt : praxisName;
                                                final desc = [
                                                  if (sNotizenC.text.trim().isNotEmpty) 'Therapeut/in: ${sNotizenC.text.trim()}',
                                                  if (loc.isNotEmpty) 'Ort: $loc',
                                                  'Mitglied: ${widget.user.vorname ?? ''} ${widget.user.nachname ?? ''} (${widget.user.mitgliedernummer})',
                                                ].join('\n');
                                                widget.terminService.createTermin(
                                                  title: title, category: 'sonstiges', description: desc,
                                                  terminDate: terminDate, durationMinutes: 30,
                                                  location: loc,
                                                  participantIds: [widget.user.id],
                                                ).then((result) {
                                                  // Save termin_id for later deletion
                                                  if (result.containsKey('termin')) {
                                                    sitzung['termin_id'] = result['termin']['id'];
                                                  }
                                                });
                                              } catch (_) {}
                                            }
                                            r['sitzungen'] = sitzungen;
                                            doSave(r, fromStatus: true);
                                            setVerlauf(() {});
                                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$anzahl Sitzung${anzahl > 1 ? 'en' : ''} erstellt'), backgroundColor: Colors.green));
                                          },
                                          child: Text(anzahl > 1 ? '$anzahl Sitzungen erstellen' : 'Hinzufugen'),
                                        ),
                                      ],
                                    );
                                  },
                                ));
                              },
                            ),
                          ]),
                          const SizedBox(height: 8),

                          if (sitzungen.isEmpty)
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                              child: Center(child: Text('Noch keine Sitzungen eingetragen', style: TextStyle(fontSize: 12, color: Colors.grey.shade400))),
                            )
                          else
                            ...sitzungen.asMap().entries.map((e) {
                              final idx = e.key;
                              final s = Map<String, dynamic>.from(e.value as Map);
                              final st = getSitzungStatus(s);
                              final stColor = sitzungStatusColors[st] ?? Colors.grey;
                              final stIcon = sitzungStatusIcons[st] ?? Icons.schedule;
                              final stLabel = sitzungStatusLabels[st] ?? st;
                              final datumFmt = () { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(s['datum'].toString())); } catch (_) { return s['datum']?.toString() ?? ''; } }();
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                decoration: BoxDecoration(
                                  color: stColor.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: stColor.shade200),
                                ),
                                child: Row(children: [
                                  // Nr circle
                                  Container(
                                    width: 28, height: 28,
                                    decoration: BoxDecoration(shape: BoxShape.circle, color: stColor.shade600),
                                    child: Center(child: Text(s['nr']?.toString() ?? '${idx + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))),
                                  ),
                                  const SizedBox(width: 10),
                                  // Info
                                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Row(children: [
                                      Text('$datumFmt  ${s['zeit'] ?? ''}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(color: stColor.shade100, borderRadius: BorderRadius.circular(4)),
                                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                                          Icon(stIcon, size: 10, color: stColor.shade800),
                                          const SizedBox(width: 3),
                                          Text(stLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: stColor.shade800)),
                                        ]),
                                      ),
                                    ]),
                                    if ((s['notizen']?.toString() ?? '').isNotEmpty)
                                      Text(s['notizen'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                                  ])),
                                  // Status change button
                                  OutlinedButton.icon(
                                    icon: Icon(stIcon, size: 16, color: stColor.shade600),
                                    label: Text('Status', style: TextStyle(fontSize: 10, color: stColor.shade700)),
                                    style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), minimumSize: Size.zero, side: BorderSide(color: stColor.shade300)),
                                    onPressed: () {
                                      showDialog(context: context, builder: (stCtx) => SimpleDialog(
                                        title: Text('Status ändern – Sitzung ${idx + 1}', style: const TextStyle(fontSize: 14)),
                                        children: sitzungStatusList.map((key) => SimpleDialogOption(
                                          onPressed: () {
                                            Navigator.pop(stCtx);
                                            final m = Map<String, dynamic>.from(sitzungen[idx] as Map);
                                            m['sitzung_status'] = key;
                                            m['onorat'] = key == 'wahrgenommen';
                                            sitzungen[idx] = m;
                                            r['sitzungen'] = sitzungen;
                                            doSave(r, fromStatus: true);
                                            setVerlauf(() {});
                                            // Notify member via live chat
                                            _notifySitzungStatusChange(
                                              sitzungNr: s['nr']?.toString() ?? '${idx + 1}',
                                              datum: datumFmt,
                                              zeit: s['zeit']?.toString() ?? '',
                                              newStatus: sitzungStatusLabels[key] ?? key,
                                              bereich: r['bereich']?.toString() ?? 'Heilmittel',
                                            );
                                          },
                                          child: Row(children: [
                                            Icon(sitzungStatusIcons[key], size: 18, color: (sitzungStatusColors[key] ?? Colors.grey).shade600),
                                            const SizedBox(width: 10),
                                            Text(sitzungStatusLabels[key] ?? key, style: TextStyle(fontSize: 13, fontWeight: st == key ? FontWeight.bold : FontWeight.normal)),
                                            if (st == key) ...[const Spacer(), Icon(Icons.check, size: 16, color: Colors.teal.shade600)],
                                          ]),
                                        )).toList(),
                                      ));
                                    },
                                  ),
                                  // Delete
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                                    tooltip: 'Sitzung löschen',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                                    onPressed: () {
                                      // Delete from Terminverwaltung if termin_id exists
                                      final tvId = s['termin_id'];
                                      if (tvId != null) {
                                        try { widget.terminService.deleteTermin(tvId is int ? tvId : int.parse(tvId.toString())); } catch (_) {}
                                      }
                                      sitzungen.removeAt(idx); r['sitzungen'] = sitzungen; doSave(r, fromStatus: true); setVerlauf(() {});
                                    },
                                  ),
                                ]),
                              );
                            }),

                          // Sitzungen counter
                          if (sitzungen.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
                              child: Row(children: [
                                Icon(Icons.bar_chart, size: 16, color: Colors.grey.shade600),
                                const SizedBox(width: 8),
                                () {
                                  final wahr = sitzungen.where((s) => getSitzungStatus(Map<String, dynamic>.from(s as Map)) == 'wahrgenommen').length;
                                  final nichtW = sitzungen.where((s) => getSitzungStatus(Map<String, dynamic>.from(s as Map)) == 'nicht_wahrgenommen').length;
                                  final verschoben = sitzungen.where((s) { final st = getSitzungStatus(Map<String, dynamic>.from(s as Map)); return st == 'verschoben_kunde' || st == 'verschoben_praxis'; }).length;
                                  return Text.rich(TextSpan(children: [
                                    TextSpan(text: '$wahr', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                                    TextSpan(text: ' / ${sitzungen.length} wahrgenommen', style: TextStyle(color: Colors.grey.shade700)),
                                    if (nichtW > 0) TextSpan(text: '  ·  $nichtW nicht wahrg.', style: TextStyle(color: Colors.red.shade600)),
                                    if (verschoben > 0) TextSpan(text: '  ·  $verschoben verschoben', style: TextStyle(color: Colors.amber.shade700)),
                                  ]), style: const TextStyle(fontSize: 12));
                                }(),
                                if ((r['behandlungseinheiten']?.toString() ?? '').isNotEmpty) ...[
                                  const Spacer(),
                                  Text('von ${r['behandlungseinheiten']} verordnet', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                ],
                              ]),
                            ),
                          ],

                          const SizedBox(height: 16),
                          SizedBox(width: double.infinity, child: FilledButton.icon(
                            icon: const Icon(Icons.save, size: 16),
                            label: const Text('Verlauf speichern'),
                            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
                            onPressed: () {
                              String newStatus = status;
                              if (abgeschlossenDatumC.text.isNotEmpty) { newStatus = 'abgeschlossen'; }
                              else if (begonnenDatumC.text.isNotEmpty) { newStatus = 'begonnen'; }
                              doSave({
                                'begonnen_datum': begonnenDatumC.text,
                                'abgeschlossen_datum': abgeschlossenDatumC.text,
                                'therapeut': therapeutC.text.trim(),
                                'therapeut_praxis': therapeutPraxisC.text.trim(),
                                'sitzungen': sitzungen,
                                'status': newStatus,
                              }, fromStatus: true, setS: setS2);
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verlauf gespeichert'), backgroundColor: Colors.green));
                            },
                          )),
                        ]));
                      }),

                      // ── Korrespondenz tab ──
                      StatefulBuilder(builder: (kCtx, setKorrState) {
                        final korrespondenz = r['korrespondenz'] is List
                            ? List<Map<String, dynamic>>.from((r['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)))
                            : <Map<String, dynamic>>[];

                        return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 16),
                            label: const Text('Korrespondenz hinzufugen', style: TextStyle(fontSize: 12)),
                            style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), minimumSize: Size.zero),
                            onPressed: () {
                              String kRichtung = 'ausgang';
                              String kMethode = 'email';
                              final kDatumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
                              final kBetreffC = TextEditingController();
                              final kInhaltC = TextEditingController();
                              showDialog(context: kCtx, builder: (kDlg) => StatefulBuilder(
                                builder: (kDlg, setKDlg) => AlertDialog(
                                  title: const Text('Neue Korrespondenz', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                                  content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                    // Richtung
                                    Row(children: [
                                      ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_made, size: 13, color: kRichtung == 'ausgang' ? Colors.white : Colors.blue.shade700), const SizedBox(width: 4), Text('Ausgang', style: TextStyle(fontSize: 11, color: kRichtung == 'ausgang' ? Colors.white : Colors.blue.shade700))]), selected: kRichtung == 'ausgang', selectedColor: Colors.blue.shade600, onSelected: (_) => setKDlg(() => kRichtung = 'ausgang')),
                                      const SizedBox(width: 8),
                                      ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_received, size: 13, color: kRichtung == 'eingang' ? Colors.white : Colors.green.shade700), const SizedBox(width: 4), Text('Eingang', style: TextStyle(fontSize: 11, color: kRichtung == 'eingang' ? Colors.white : Colors.green.shade700))]), selected: kRichtung == 'eingang', selectedColor: Colors.green.shade600, onSelected: (_) => setKDlg(() => kRichtung = 'eingang')),
                                    ]),
                                    const SizedBox(height: 10),
                                    // Methode
                                    Wrap(spacing: 6, runSpacing: 4, children: [
                                      for (final m in [('email', 'E-Mail', Icons.email), ('telefon', 'Telefon', Icons.phone), ('post', 'Post', Icons.mail), ('fax', 'Fax', Icons.fax)])
                                        ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: kMethode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 11, color: kMethode == m.$1 ? Colors.white : Colors.grey.shade700))]), selected: kMethode == m.$1, selectedColor: Colors.indigo.shade600, onSelected: (_) => setKDlg(() => kMethode = m.$1)),
                                    ]),
                                    const SizedBox(height: 10),
                                    TextFormField(controller: kDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
                                      final p = await showDatePicker(context: kDlg, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2099), locale: const Locale('de'));
                                      if (p != null) kDatumC.text = DateFormat('dd.MM.yyyy').format(p);
                                    }))),
                                    const SizedBox(height: 10),
                                    TextFormField(controller: kBetreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                    const SizedBox(height: 10),
                                    TextFormField(controller: kInhaltC, maxLines: 3, decoration: InputDecoration(labelText: 'Inhalt / Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                  ]))),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(kDlg), child: const Text('Abbrechen')),
                                    FilledButton(onPressed: () {
                                      korrespondenz.insert(0, {
                                        'richtung': kRichtung,
                                        'methode': kMethode,
                                        'datum': kDatumC.text,
                                        'betreff': kBetreffC.text.trim(),
                                        'inhalt': kInhaltC.text.trim(),
                                        'erstellt_am': DateTime.now().toIso8601String(),
                                      });
                                      r['korrespondenz'] = korrespondenz;
                                      doSave(r, fromStatus: true);
                                      Navigator.pop(kDlg);
                                      setKorrState(() {});
                                    }, child: const Text('Speichern')),
                                  ],
                                ),
                              ));
                            },
                          ),
                          const SizedBox(height: 12),
                          if (korrespondenz.isEmpty)
                            Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
                              Icon(Icons.email, size: 36, color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text('Keine Korrespondenz', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                            ])))
                          else
                            ...korrespondenz.asMap().entries.map((entry) {
                              final idx = entry.key;
                              final k = entry.value;
                              final isEingang = k['richtung'] == 'eingang';
                              final methodeIcons = {'email': Icons.email, 'telefon': Icons.phone, 'post': Icons.mail, 'fax': Icons.fax};
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: isEingang ? Colors.green.shade50 : Colors.blue.shade50,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: isEingang ? Colors.green.shade200 : Colors.blue.shade200),
                                ),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Icon(isEingang ? Icons.call_received : Icons.call_made, size: 14, color: isEingang ? Colors.green.shade700 : Colors.blue.shade700),
                                    const SizedBox(width: 4),
                                    Text(isEingang ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: isEingang ? Colors.green.shade700 : Colors.blue.shade700)),
                                    const SizedBox(width: 8),
                                    Icon(methodeIcons[k['methode']] ?? Icons.email, size: 13, color: Colors.grey.shade500),
                                    const SizedBox(width: 4),
                                    Text(k['methode']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                    const Spacer(),
                                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                    const SizedBox(width: 4),
                                    InkWell(onTap: () { korrespondenz.removeAt(idx); r['korrespondenz'] = korrespondenz; doSave(r, fromStatus: true); setKorrState(() {}); },
                                      child: Icon(Icons.delete, size: 16, color: Colors.red.shade300)),
                                  ]),
                                  if ((k['betreff']?.toString() ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(k['betreff'].toString(), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                  ],
                                  if ((k['inhalt']?.toString() ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 2),
                                    Text(k['inhalt'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  ],
                                  // Doc upload per korrespondenz
                                  const SizedBox(height: 6),
                                  _buildBerichtDokumente(type, 'korr_${k['erstellt_am'] ?? idx}', setKorrState),
                                ]),
                              );
                            }),
                        ]));
                      }),
                    ])),
                  ])),
            ),
          ));
        },
      ));
    }

    // ── List view ──
    return StatefulBuilder(builder: (ctx, setLocalState2) {
      final statusColors2 = <String, MaterialColor>{'ausgestellt': Colors.blue, 'begonnen': Colors.orange, 'abgeschlossen': Colors.green, 'abgelaufen': Colors.grey};
      final statusLabels2 = const {'ausgestellt': 'Ausgestellt', 'begonnen': 'Begonnen', 'abgeschlossen': 'Abgeschlossen', 'abgelaufen': 'Abgelaufen'};
      final current = data['heilmittel'] is List ? data['heilmittel'] as List : [];
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.healing, size: 18, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text('Heilmittelverordnungen (Muster 13)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
          const Spacer(),
          FilledButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neue Verordnung', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
            onPressed: () => showHeilmittelDialog()),
        ]),
        const SizedBox(height: 12),
        if (current.isEmpty)
          Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(children: [
            Icon(Icons.healing, size: 40, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Heilmittelverordnungen vorhanden', style: TextStyle(color: Colors.grey.shade400)),
          ])))
        else
          ...current.asMap().entries.map((e) {
            final idx = e.key;
            final r = Map<String, dynamic>.from(e.value as Map);
            final bereich = r['bereich']?.toString() ?? 'Physiotherapie';
            final bColor = (bereichColors[bereich] ?? Colors.teal);
            final st = r['status']?.toString() ?? 'ausgestellt';
            final sColor = statusColors2[st] ?? Colors.grey;
            final dringend = r['dringend'] == true;
            final expired = hmIsExpired(dringend, r['datum']?.toString() ?? '');
            final expStr = hmExpiry(dringend, r['datum']?.toString() ?? '');
            final datumStr = r['datum']?.toString() ?? '';
            final datumFmt = datumStr.isNotEmpty ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(datumStr)); } catch (_) { return datumStr; } })() : '';
            final hms = [r['hm1'], r['hm2'], r['hm3']].where((h) => (h?.toString() ?? '').isNotEmpty).map((h) => h.toString().split(' – ').first).toList();
            return Card(
              margin: const EdgeInsets.only(bottom: 8), elevation: 1,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              child: InkWell(
                onTap: () => showHeilmittelDialog(existing: r, editIndex: idx),
                borderRadius: BorderRadius.circular(10),
                child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
                  Container(width: 38, height: 38, decoration: BoxDecoration(color: expired ? Colors.red.shade50 : bColor.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Icon(Icons.healing, size: 20, color: expired ? Colors.red.shade400 : bColor.shade600)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2), decoration: BoxDecoration(color: bColor.shade100, borderRadius: BorderRadius.circular(4), border: Border.all(color: bColor.shade300)),
                        child: Text(bereichShort[bereich] ?? bereich, style: TextStyle(fontSize: 9, color: bColor.shade800, fontWeight: FontWeight.bold))),
                      const SizedBox(width: 6),
                      if (datumFmt.isNotEmpty) Text(datumFmt, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: (expired ? Colors.red : sColor).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                        child: Text(expired ? 'Abgelaufen' : (statusLabels2[st] ?? st), style: TextStyle(fontSize: 10, color: expired ? Colors.red.shade700 : sColor, fontWeight: FontWeight.bold))),
                      if (dringend) ...[const SizedBox(width: 4), Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)), child: Text('Dringend', style: TextStyle(fontSize: 9, color: Colors.red.shade700, fontWeight: FontWeight.bold)))],
                    ]),
                    const SizedBox(height: 4),
                    if (hms.isNotEmpty) Text(hms.join(' · '), style: TextStyle(fontSize: 12, color: Colors.grey.shade700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if ((r['diagnose1_icd10']?.toString() ?? '').isNotEmpty) Text('${r['diagnose1_icd10']} ${r['diagnose1'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis)
                    else if ((r['icd10']?.toString() ?? '').isNotEmpty) Text('ICD-10: ${r['icd10']} ${r['diagnose'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500), maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (expStr != null) Text(expired ? '⚠ Abgelaufen am $expStr' : 'Läuft ab: $expStr', style: TextStyle(fontSize: 10, color: expired ? Colors.red.shade600 : Colors.grey.shade500)),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300),
                    onPressed: () { final list = List<dynamic>.from(current)..removeAt(idx); data['heilmittel'] = list; saveAll(); setLocalState(() {}); },
                    tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                ])),
              ),
            );
          }),
      ]));
    });
  }

  Widget _rezeptCheckbox(String label, bool value, ValueChanged<bool> onChanged, MaterialColor color) {
    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: value ? color.shade100 : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: value ? color.shade400 : Colors.grey.shade300),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(value ? Icons.check_box : Icons.check_box_outline_blank, size: 16, color: value ? color.shade700 : Colors.grey.shade400),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, fontWeight: value ? FontWeight.bold : FontWeight.normal, color: value ? color.shade700 : Colors.grey.shade600)),
        ]),
      ),
    );
  }

  Widget _rezeptBadge(String label, MaterialColor color) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(4)),
      child: Text(label, style: TextStyle(fontSize: 10, color: color.shade700, fontWeight: FontWeight.bold)),
    );
  }

  Widget _rezeptDetailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade500),
        const SizedBox(width: 6),
        SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  Widget _medikamentRow(int nr, TextEditingController nameC, TextEditingController mengeC, TextEditingController dosisC) {
    Future<void> openSearch(BuildContext ctx) async {
      final searchC = TextEditingController();
      List<Map<String, dynamic>> results = [];
      await showDialog(
        context: ctx,
        builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
          Future<void> doSearch(String q) async {
            if (q.trim().length < 2) { setS(() => results = []); return; }
            try {
              final res = await widget.apiService.searchMedikamente(q.trim());
              if (res['success'] == true && res['data'] is List) {
                setS(() => results = (res['data'] as List).cast<Map<String, dynamic>>());
              }
            } catch (_) { setS(() => results = []); }
          }
          return AlertDialog(
            title: Text('Medikament $nr suchen', style: TextStyle(fontSize: 14, color: Colors.pink.shade700)),
            content: SizedBox(width: 480, child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: searchC,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: 'Name / Wirkstoff / PZN...',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: doSearch,
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: results.isEmpty
                  ? Center(child: Text('Mindestens 2 Zeichen eingeben', style: TextStyle(color: Colors.grey.shade500, fontSize: 12)))
                  : ListView.builder(
                    shrinkWrap: true,
                    itemCount: results.length,
                    itemBuilder: (_, i) {
                      final m = results[i];
                      final title = [m['name'], m['staerke'], m['darreichungsform']].where((s) => (s?.toString() ?? '').isNotEmpty).map((s) => s.toString()).join(' ');
                      final subtitle = [
                        if ((m['normgroesse']?.toString() ?? '').isNotEmpty) m['normgroesse'],
                        if ((m['packungsgroesse']?.toString() ?? '').isNotEmpty) m['packungsgroesse'],
                        if ((m['pzn']?.toString() ?? '').isNotEmpty) 'PZN ${m['pzn']}',
                      ].join(' · ');
                      final wirkstoff = m['wirkstoff']?.toString() ?? '';
                      final anwendung = m['anwendungsgebiet']?.toString() ?? '';
                      return ListTile(
                        dense: true,
                        leading: Icon(Icons.medication, size: 18, color: Colors.pink.shade400),
                        title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          if (wirkstoff.isNotEmpty) Text('Wirkstoff: $wirkstoff', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          if (subtitle.isNotEmpty) Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          if (anwendung.isNotEmpty) Text(anwendung, style: TextStyle(fontSize: 10, color: Colors.teal.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
                        ]),
                        onTap: () {
                          nameC.text = title;
                          if (mengeC.text.isEmpty) {
                            final menge = [m['normgroesse'], m['packungsgroesse']].where((s) => (s?.toString() ?? '').isNotEmpty).map((s) => s.toString()).join(' ');
                            if (menge.isNotEmpty) mengeC.text = menge;
                          }
                          Navigator.pop(dCtx);
                        },
                      );
                    },
                  ),
              ),
            ])),
            actions: [TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Abbrechen'))],
          );
        }),
      );
      searchC.dispose();
    }

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.pink.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.pink.shade100)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Medikament $nr', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.pink.shade700)),
        const SizedBox(height: 6),
        Builder(builder: (ctx) => TextFormField(
          controller: nameC,
          decoration: InputDecoration(
            labelText: 'Name / Wirkstoff / PZN...',
            prefixIcon: const Icon(Icons.medication, size: 16),
            suffixIcon: IconButton(
              icon: Icon(Icons.search, size: 18, color: Colors.pink.shade400),
              tooltip: 'In Datenbank suchen',
              onPressed: () => openSearch(ctx),
            ),
            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
        )),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: TextFormField(
              controller: mengeC,
              decoration: InputDecoration(labelText: 'Menge (z.B. N2, 50 Stk.)', prefixIcon: const Icon(Icons.numbers, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              controller: dosisC,
              decoration: InputDecoration(labelText: 'Dosierung (z.B. 1-0-1)', prefixIcon: const Icon(Icons.schedule, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ),
        ]),
      ]),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // TAB 10: BERICHTE (medical reports per doctor, with file upload)
  // Uses the existing gesundheit_dokumente table via gesundheit_doc_* APIs
  // with gesundheit_type = "berichte_<arzt_type>" and analyse_id = report ID.
  // ═══════════════════════════════════════════════════════════════
  Widget _buildBerichteTab(String type, String arztTitle, Map<String, dynamic> data, VoidCallback saveAll, StateSetter setLocalState) {
    // Read directly from the live data source — the `data` parameter may be a
    // stale closure captured before the server round-trip completed.
    final liveData = _gesundheitData[type] ?? data;
    final List<dynamic> berichteList = liveData['berichte'] is List ? liveData['berichte'] as List : [];
    final userId = widget.user.id;

    void showBerichtDialog({Map<String, dynamic>? existing, int? editIndex}) {
      final titelC = TextEditingController(text: existing?['titel'] ?? '');
      final datumC = TextEditingController(text: existing?['datum'] ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
      final beschreibungC = TextEditingController(text: existing?['beschreibung'] ?? '');
      final kategorie = ValueNotifier<String>(existing?['kategorie'] ?? 'Befundbericht');

      const kategorien = [
        'Befundbericht', 'Arztbrief', 'OP-Bericht', 'Entlassungsbericht',
        'Laborbericht', 'Radiologie / Bildgebung', 'Pathologie',
        'Gutachten', 'Rehabilitationsbericht',
        'Zervixkarzinom-Screening (HPV/Pap)',
        'Sonstiges',
      ];

      showDialog(
        context: context,
        builder: (dctx) => AlertDialog(
          title: Text(existing != null ? 'Bericht bearbeiten' : 'Neuer Bericht'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Datum
                  TextFormField(
                    controller: datumC,
                    decoration: InputDecoration(
                      labelText: 'Datum',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.today),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dctx,
                            initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime.now().add(const Duration(days: 30)),
                          );
                          if (picked != null) datumC.text = DateFormat('yyyy-MM-dd').format(picked);
                        },
                      ),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: dctx,
                        initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 30)),
                      );
                      if (picked != null) datumC.text = DateFormat('yyyy-MM-dd').format(picked);
                    },
                  ),
                  const SizedBox(height: 12),
                  // Kategorie
                  ValueListenableBuilder<String>(
                    valueListenable: kategorie,
                    builder: (_, kat, __) => DropdownButtonFormField<String>(
                      value: kategorien.contains(kat) ? kat : 'Befundbericht',
                      decoration: InputDecoration(
                        labelText: 'Kategorie',
                        prefixIcon: const Icon(Icons.category),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      items: kategorien.map((k) => DropdownMenuItem(value: k, child: Text(k, style: const TextStyle(fontSize: 13)))).toList(),
                      onChanged: (v) { if (v != null) kategorie.value = v; },
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Titel
                  TextFormField(
                    controller: titelC,
                    decoration: InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'z.B. MRT Knie rechts',
                      prefixIcon: const Icon(Icons.title),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Beschreibung
                  TextFormField(
                    controller: beschreibungC,
                    decoration: InputDecoration(
                      labelText: 'Beschreibung / Befund',
                      hintText: 'Zusammenfassung des Berichts',
                      prefixIcon: const Icon(Icons.notes),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      alignLabelWithHint: true,
                      isDense: true,
                    ),
                    maxLines: 5,
                    minLines: 3,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dctx), child: const Text('Abbrechen')),
            ElevatedButton.icon(
              icon: const Icon(Icons.save),
              label: Text(existing != null ? 'Aktualisieren' : 'Hinzufuegen'),
              onPressed: () {
                if (titelC.text.trim().isEmpty) return;
                final entry = {
                  'titel': titelC.text.trim(),
                  'datum': datumC.text.trim(),
                  'kategorie': kategorie.value,
                  'beschreibung': beschreibungC.text.trim(),
                  'id': existing?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
                };
                final list = List<dynamic>.from(berichteList);
                if (editIndex != null) {
                  list[editIndex] = entry;
                } else {
                  list.insert(0, entry);
                }
                // Write to BOTH data references to cover stale-closure edge case
                data['berichte'] = list;
                liveData['berichte'] = list;
                saveAll();
                setLocalState(() {});
                // Also trigger widget-level rebuild so the tab reflects new data
                if (mounted) setState(() {});
                Navigator.pop(dctx);
              },
            ),
          ],
        ),
      );
    }

    // Format date for display
    String fmtDate(String d) {
      final dt = DateTime.tryParse(d);
      return dt != null ? DateFormat('dd.MM.yyyy').format(dt) : d;
    }

    // Icon per kategorie
    IconData katIcon(String k) {
      switch (k) {
        case 'Arztbrief': return Icons.mail;
        case 'OP-Bericht': return Icons.medical_services;
        case 'Entlassungsbericht': return Icons.exit_to_app;
        case 'Laborbericht': return Icons.science;
        case 'Radiologie / Bildgebung': return Icons.image;
        case 'Pathologie': return Icons.biotech;
        case 'Gutachten': return Icons.gavel;
        case 'Rehabilitationsbericht': return Icons.accessibility_new;
        default: return Icons.description;
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.description, color: Colors.indigo.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text('Berichte — $arztTitle', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
              ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neuer Bericht'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                onPressed: () => showBerichtDialog(),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Befundberichte, Arztbriefe, OP-Berichte, Laborergebnisse',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 16),

          if (berichteList.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Column(
                children: [
                  Icon(Icons.description, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Keine Berichte vorhanden', style: TextStyle(color: Colors.grey.shade600)),
                  const SizedBox(height: 4),
                  Text('Klicken Sie auf "Neuer Bericht" um einen hinzuzufuegen', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ],
              ),
            )
          else
            ...berichteList.asMap().entries.map((entry) {
              final idx = entry.key;
              final b = entry.value as Map<String, dynamic>;
              final berichtId = (b['id'] ?? idx).toString();
              final titel = b['titel'] ?? '(kein Titel)';
              final datum = b['datum'] ?? '';
              final kategorie = b['kategorie'] ?? 'Befundbericht';
              final beschreibung = b['beschreibung'] ?? '';
              final docType = 'berichte_$type';

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: Colors.indigo.shade200),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ExpansionTile(
                  leading: Icon(katIcon(kategorie), color: Colors.indigo.shade600),
                  title: Text(titel, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  subtitle: Text('$kategorie — ${fmtDate(datum)}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Beschreibung
                          if (beschreibung.isNotEmpty) ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: SelectableText(beschreibung, style: const TextStyle(fontSize: 13)),
                            ),
                            const SizedBox(height: 12),
                          ],

                          // Dokumente section — uses existing gesundheit_doc_* API
                          _buildBerichteDokumente(docType, berichtId, userId),

                          // Action buttons
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton.icon(
                                icon: const Icon(Icons.edit, size: 16),
                                label: const Text('Bearbeiten'),
                                onPressed: () => showBerichtDialog(existing: b, editIndex: idx),
                              ),
                              const SizedBox(width: 8),
                              TextButton.icon(
                                icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
                                label: Text('Loeschen', style: TextStyle(color: Colors.red.shade400)),
                                onPressed: () {
                                  final list = List<dynamic>.from(berichteList)..removeAt(idx);
                                  data['berichte'] = list;
                                  liveData['berichte'] = list;
                                  saveAll();
                                  setLocalState(() {});
                                  if (mounted) setState(() {});
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  /// Inline document list + upload for a single Bericht entry.
  /// Re-uses the existing gesundheit_doc_* API system.
  Widget _buildBerichteDokumente(String docType, String berichtId, int userId) {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.apiService.listGesundheitDocs(
        userId: userId,
        gesundheitType: docType,
        analyseId: berichtId,
      ),
      builder: (context, snapshot) {
        final docs = <Map<String, dynamic>>[];
        if (snapshot.hasData && snapshot.data!['success'] == true && snapshot.data!['documents'] != null) {
          docs.addAll(List<Map<String, dynamic>>.from(snapshot.data!['documents']));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.attach_file, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text('Dokumente (${docs.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const Spacer(),
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 16),
                  label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    visualDensity: VisualDensity.compact,
                  ),
                  onPressed: () async {
                    final files = await FilePickerHelper.pickFiles(allowMultiple: true);
                    if (files == null || files.files.isEmpty) return;
                    if (!context.mounted) return;
                    // Show loading
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(children: [
                          const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
                          const SizedBox(width: 12),
                          Text('${files.files.length} Datei(en) werden hochgeladen...'),
                        ]),
                        duration: const Duration(seconds: 30),
                      ),
                    );
                    int uploaded = 0;
                    for (final f in files.files) {
                      if (f.path == null) continue;
                      try {
                        await widget.apiService.uploadGesundheitDoc(
                          userId: userId,
                          gesundheitType: docType,
                          analyseId: berichtId,
                          filePath: f.path!,
                          fileName: f.name,
                        );
                        uploaded++;
                      } catch (_) {}
                    }
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).hideCurrentSnackBar();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$uploaded Datei(en) hochgeladen'),
                        backgroundColor: uploaded > 0 ? Colors.green : Colors.red,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    // Force rebuild to show newly uploaded docs
                    if (mounted) setState(() {});
                  },
                ),
              ],
            ),
            if (docs.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...docs.map((doc) {
                final docId = doc['id'] as int;
                final name = doc['filename'] ?? 'datei';
                final size = doc['file_size'] ?? 0;
                final sizeKb = size > 0 ? '${(size / 1024).toStringAsFixed(0)} KB' : '';

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file, size: 16, color: Colors.indigo.shade400),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '$name${sizeKb.isNotEmpty ? " · $sizeKb" : ""}',
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.visibility, size: 16),
                        tooltip: 'Anzeigen',
                        onPressed: () async {
                          final bytes = await widget.apiService.downloadGesundheitDoc(docId);
                          if (!context.mounted || bytes == null) return;
                          showDialog(
                            context: context,
                            builder: (_) => FileViewerDialog(
                              fileBytes: Uint8List.fromList(bytes),
                              fileName: name,
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
                        tooltip: 'Loeschen',
                        onPressed: () async {
                          await widget.apiService.deleteGesundheitDoc(docId);
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                );
              }),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Keine Dokumente', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
              ),
          ],
        );
      },
    );
  }
}
