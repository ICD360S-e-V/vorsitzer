import 'dart:io' as io;
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../services/termin_service.dart';
import '../models/user.dart';
import 'arbeitgeber_behorde_content.dart';
import 'behorde_auslaenderbehoerde.dart';
import 'behorde_arbeitsagentur.dart';
import 'behorde_bamf.dart';
import 'behorde_einwohnermeldeamt.dart';
import 'behorde_familienkasse.dart';
import 'behorde_finanzamt.dart';
import 'behorde_gericht.dart';
import 'behorde_kindergarten.dart';
import 'behorde_krankenkasse.dart';
import 'behorde_rentenversicherung.dart';
import 'behorde_jobcenter.dart';
import 'behorde_jugendamt.dart';
import 'behorde_wohngeldstelle.dart';
import 'behorde_deutschlandticket.dart';
import 'behorde_vermieter.dart';
import 'behorde_schule.dart';
import 'behorde_konsulat.dart';
import 'behorde_polizei.dart';
import 'behorde_sozialamt.dart';
import 'behorde_versorgungsamt.dart';
import 'behorde_landratsamt.dart';
import 'behorde_rundfunkbeitrag.dart';
import 'file_viewer_dialog.dart';
import '../screens/webview_screen.dart';
import '../utils/file_picker_helper.dart';

class BehoerdeTabContent extends StatefulWidget {
  final User user;
  final ApiService apiService;
  final TicketService ticketService;
  final TerminService terminService;
  final String adminMitgliedernummer;

  const BehoerdeTabContent({
    super.key,
    required this.user,
    required this.apiService,
    required this.ticketService,
    required this.terminService,
    required this.adminMitgliedernummer,
  });

  @override
  State<BehoerdeTabContent> createState() => _BehoerdeTabContentState();
}

class _BehoerdeTabContentState extends State<BehoerdeTabContent> {
  // ============= BEHÖRDE TAB =============

  // Behörde data state
  final Map<String, Map<String, dynamic>> _behoerdeData = {};
  final Map<String, bool> _behoerdeLoading = {};
  final Map<String, bool> _behoerdeSaving = {};

  // Tab config: which tabs are enabled for this member
  Set<String> _enabledTabs = {};

  // ── Finanzämter & Stammdaten aus Server-DB (Cache) ──
  // Finanzämter: {name: {adresse, telefon, fax, email, website, oeffnungszeiten}}
  // Arbeitgeber-Datenbank (zentrale Firmenliste)
  List<Map<String, dynamic>> _dbArbeitgeberListe = [];
  // Behörden-Standorte Cache: {typ: [standorte]}
  final Map<String, List<Map<String, dynamic>>> _behoerdenStandorte = {};
  // Arbeitsvermittler DB Cache
  List<Map<String, dynamic>> _arbeitsvermittlerListe = [];
  bool _arbeitsvermittlerLoaded = false;
  bool _stammdatenLoaded = false;

  // All behörde types in order
  static const List<String> _allTypes = [
    'arbeitgeber', 'bundesagentur', 'jobcenter', 'sozialamt', 'finanzamt',
    'gericht',
    'krankenkasse', 'rentenversicherung', 'auslaenderbehoerde', 'familienkasse',
    'jugendamt', 'einwohnermeldeamt', 'wohngeldstelle', 'bamf', 'vermieter', 'deutschlandticket', 'schule', 'konsulat', 'polizei',
    'versorgungsamt', 'landratsamt', 'rundfunkbeitrag', 'kindergarten',
  ];

  // Fields per type for completion calculation
  static const Map<String, List<String>> _typeFields = {
    'arbeitgeber': ['firma', 'position', 'ort', 'beschreibung', 'von_monat', 'von_jahr', 'beschaeftigungsart', 'stundenlohn', 'entfernung_km'],
    'bundesagentur': ['kundennummer', 'arbeitsvermittler', 'arbeitsvermittler_tel', 'arbeitsvermittler_email', 'dienststelle', 'arbeitsuchend_datum', 'arbeitslos_datum'],
    'jobcenter': ['kundennummer', 'arbeitsvermittler', 'arbeitsvermittler_tel', 'arbeitsvermittler_email', 'dienststelle', 'bg_nummer'],
    'sozialamt': ['kundennummer', 'sachbearbeiter', 'sachbearbeiter_tel', 'dienststelle'],
    'finanzamt': ['steuerid', 'finanzamt_name', 'dienststelle', 'steuerklasse', 'jahreseinkommen', 'elster_konto'],
    'gericht': ['gericht_typ', 'gericht_name', 'aktenzeichen', 'dienststelle', 'sachbearbeiter'],
    'krankenkasse': ['krankenkasse_name', 'versichertennummer', 'versicherungsart'],
    'rentenversicherung': ['versicherungsnummer', 'rentenversicherung_name', 'dienststelle', 'rentenart', 'entgeltpunkte'],
    'auslaenderbehoerde': ['aufenthaltstitel', 'gueltig_bis', 'dienststelle', 'aktenzeichen'],
    'familienkasse': ['kindergeld_nummer', 'dienststelle', 'sachbearbeiter', 'anzahl_kinder', 'kinder'],
    'jugendamt': ['sachbearbeiter', 'sachbearbeiter_tel', 'dienststelle'],
    'einwohnermeldeamt': ['anmeldung_datum', 'dienststelle'],
    'wohngeldstelle': ['aktenzeichen', 'dienststelle', 'antrag_status'],
    'bamf': ['aktenzeichen', 'dienststelle', 'antrag_status'],
    'vermieter': ['firma', 'telefon', 'email', 'strasse', 'plz', 'ort', 'kaltmiete', 'warmmiete'],
    'deutschlandticket': ['ticket_typ', 'anbieter', 'abo_status', 'abo_start', 'sepa_iban', 'sepa_kontoinhaber'],
    'schule': ['schul_name', 'schulart', 'schul_beginn'],
    'konsulat': ['konsulat_name', 'konsulat_adresse'],
    'polizei': ['zustaendige_dienststelle', 'aktenzeichen', 'sachbearbeiter'],
  };

  @override
  void initState() {
    super.initState();
    _loadTabConfig();
    _loadAllBehoerdeSummary();
    _loadStammdaten();
  }


  /// Load Krankenkassen + Finanzämter from server DB (cached for session)
  /// Bei Netzwerkproblemen werden statische Daten verwendet (kein Laden)
  Future<void> _loadStammdaten() async {
    if (_stammdatenLoaded) return;
    _stammdatenLoaded = true; // Nur einmal versuchen

    // Stammdaten loaded in separate behorde files (finanzamt, krankenkasse)

    // Arbeitgeber-Datenbank (separate try/catch)
    try {
      final agResult = await widget.apiService.getArbeitgeberStammdaten().timeout(const Duration(seconds: 5));
      debugPrint('[ARBEITGEBER_DB] success=${agResult['success']} count=${(agResult['data'] as List?)?.length ?? 0}');
      if (agResult['success'] == true && agResult['data'] != null) {
        _dbArbeitgeberListe = List<Map<String, dynamic>>.from(agResult['data']);
        debugPrint('[ARBEITGEBER_DB] Loaded ${_dbArbeitgeberListe.length} employers');
      } else {
        debugPrint('[ARBEITGEBER_DB] Failed: ${agResult['message']}');
      }
    } catch (e) {
      debugPrint('[ARBEITGEBER_DB] Error: $e');
    }

    if (mounted) setState(() {});
  }

  /// Load tab config (which tabs are enabled for this member)
  Future<void> _loadTabConfig() async {
    try {
      final result = await widget.apiService.getBehoerdeData(widget.user.id, 'tab_config');
      if (mounted) {
        setState(() {
          final data = result['data'];
          if (data != null && data['enabled'] != null) {
            _enabledTabs = Set<String>.from(List<String>.from(data['enabled']));
            for (final t in _allTypes) {
              if (!_enabledTabs.contains(t)) _enabledTabs.add(t);
            }
          } else {
            // Default: all enabled
            _enabledTabs = Set<String>.from(_allTypes);
          }
          // config loaded
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _enabledTabs = Set<String>.from(_allTypes);
          // config loaded
        });
      }
    }
  }

  /// Save tab config
  Future<void> _saveTabConfig() async {
    await widget.apiService.saveBehoerdeData(widget.user.id, 'tab_config', {
      'enabled': _enabledTabs.toList(),
    });
  }

  /// Load all behoerde data for completion % calculation
  Future<void> _loadAllBehoerdeSummary() async {
    for (final type in _allTypes) {
      if (!_behoerdeData.containsKey(type) && _behoerdeLoading[type] != true) {
        _behoerdeLoading[type] = true;
        try {
          final result = await widget.apiService.getBehoerdeData(widget.user.id, type);
          if (mounted) {
            setState(() {
              _behoerdeData[type] = (result['data'] != null)
                  ? Map<String, dynamic>.from(result['data'])
                  : {};
              _behoerdeLoading[type] = false;
            });
          }
        } catch (e) {
          if (mounted) {
            setState(() {
              _behoerdeLoading[type] = false;
              _behoerdeData[type] = {};
            });
          }
        }
      }
    }
  }

  /// Calculate completion percentage for a type
  int _getCompletionPercent(String type) {
    final data = _behoerdeData[type];
    if (data == null || data.isEmpty) return 0;
    // Arbeitgeber: if arbeitslos/nicht_beschaeftigt, consider fully complete
    if (type == 'arbeitgeber') {
      final art = data['beschaeftigungsart']?.toString() ?? '';
      if (art == 'arbeitslos' || art == 'nicht_beschaeftigt' || art == 'rentner') return 100;
    }
    final fields = _typeFields[type];
    if (fields == null || fields.isEmpty) return 0;
    int filled = 0;
    for (final field in fields) {
      final val = data[field]?.toString() ?? '';
      if (val.isNotEmpty) filled++;
    }
    return ((filled / fields.length) * 100).round();
  }

  Future<void> _loadBehoerdeData(String type) async {
    if (_behoerdeLoading[type] == true) return;
    if (_behoerdeData.containsKey(type)) return;
    _behoerdeLoading[type] = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
    try {
      final result = await widget.apiService.getBehoerdeData(widget.user.id, type);
      if (mounted) {
        setState(() {
          _behoerdeData[type] = (result['data'] != null)
              ? Map<String, dynamic>.from(result['data'])
              : {};
          _behoerdeLoading[type] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _behoerdeLoading[type] = false;
          _behoerdeData[type] = {};
        });
      }
    }
  }

  /// Auto-save a single field (e.g. antraege, meldungen) by merging with existing cached data
  Future<void> _autoSaveField(String type, String field, dynamic value) async {
    final existing = Map<String, dynamic>.from(_behoerdeData[type] ?? {});
    existing[field] = value;
    _behoerdeData[type] = existing;
    try {
      await widget.apiService.saveBehoerdeData(widget.user.id, type, existing);
    } catch (_) {
      // Silent fail for auto-save — data persists in local cache until manual save
    }
  }

  Future<void> _saveBehoerdeData(String type, Map<String, dynamic> data) async {
    setState(() => _behoerdeSaving[type] = true);
    try {
      final result = await widget.apiService.saveBehoerdeData(widget.user.id, type, data);
      if (mounted) {
        if (result['success'] == true) {
          setState(() => _behoerdeData[type] = data);
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
      if (mounted) setState(() => _behoerdeSaving[type] = false);
    }
  }


  Widget _buildMemberAddressCard() {
    final strasse = widget.user.strasse ?? '';
    final hausnummer = widget.user.hausnummer ?? '';
    final plz = widget.user.plz ?? '';
    final ort = widget.user.ort ?? '';
    final hasAddress = plz.isNotEmpty && ort.isNotEmpty;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: hasAddress ? Colors.blue.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: hasAddress ? Colors.blue.shade200 : Colors.orange.shade300),
      ),
      child: Row(
        children: [
          Icon(hasAddress ? Icons.location_on : Icons.warning_amber, size: 18, color: hasAddress ? Colors.blue.shade700 : Colors.orange.shade700),
          const SizedBox(width: 8),
          Expanded(
            child: hasAddress
                ? Text('Meldeadresse: $strasse $hausnummer, $plz $ort', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade800))
                : Text('Keine Adresse hinterlegt — bitte Stufe 1 (Verifizierung) ausfüllen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
          ),
        ],
      ),
    );
  }

  // Tab icons & labels mapping
  static const List<Map<String, dynamic>> _tabDefs = [
    {'type': 'arbeitgeber', 'icon': Icons.factory, 'label': 'Arbeitgeber'},
    {'type': 'bundesagentur', 'icon': Icons.work, 'label': 'Arbeitsagentur'},
    {'type': 'jobcenter', 'icon': Icons.business_center, 'label': 'Jobcenter'},
    {'type': 'landratsamt', 'icon': Icons.account_balance_wallet, 'label': 'Landratsamt'},
    {'type': 'sozialamt', 'icon': Icons.volunteer_activism, 'label': 'Sozialamt'},
    {'type': 'finanzamt', 'icon': Icons.account_balance_wallet, 'label': 'Finanzamt'},
    {'type': 'gericht', 'icon': Icons.gavel, 'label': 'Gericht'},
    {'type': 'krankenkasse', 'icon': Icons.local_hospital, 'label': 'Krankenkasse'},
    {'type': 'rentenversicherung', 'icon': Icons.elderly, 'label': 'Rentenversicherung'},
    {'type': 'auslaenderbehoerde', 'icon': Icons.public, 'label': 'Ausl\u00E4nderbeh\u00F6rde'},
    {'type': 'familienkasse', 'icon': Icons.child_care, 'label': 'Familienkasse'},
    {'type': 'jugendamt', 'icon': Icons.family_restroom, 'label': 'Jugendamt'},
    {'type': 'einwohnermeldeamt', 'icon': Icons.home, 'label': 'Einwohnermeldeamt'},
    {'type': 'wohngeldstelle', 'icon': Icons.house, 'label': 'Wohngeldstelle'},
    {'type': 'bamf', 'icon': Icons.flag, 'label': 'BAMF'},
    {'type': 'vermieter', 'icon': Icons.apartment, 'label': 'Vermieter'},
    {'type': 'deutschlandticket', 'icon': Icons.train, 'label': 'Deutschlandticket'},
    {'type': 'schule', 'icon': Icons.school, 'label': 'Schule'},
    {'type': 'konsulat', 'icon': Icons.account_balance, 'label': 'Konsulat'},
    {'type': 'polizei', 'icon': Icons.local_police, 'label': 'Polizei'},
    {'type': 'versorgungsamt', 'icon': Icons.accessible, 'label': 'Versorgungsamt'},
    {'type': 'rundfunkbeitrag', 'icon': Icons.radio, 'label': 'ARD ZDF'},
    {'type': 'kindergarten', 'icon': Icons.child_care, 'label': 'Kindergarten'},
  ];

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 1100;
    return DefaultTabController(
      length: 22,
      child: Column(
        children: [
          _buildMemberAddressCard(),
          // Settings row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TabBar(
                    labelColor: Colors.blue.shade700,
                    unselectedLabelColor: Colors.grey.shade600,
                    indicatorColor: Colors.blue.shade700,
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    tabs: _tabDefs.map((def) {
                      final type = def['type'] as String;
                      final icon = def['icon'] as IconData;
                      final label = def['label'] as String;
                      final enabled = _enabledTabs.isEmpty || _enabledTabs.contains(type);
                      final pct = _getCompletionPercent(type);
                      return _behoerdeTabItem(icon, label, isCompact, type: type, enabled: enabled, completionPct: pct);
                    }).toList(),
                  ),
                ),
                // Settings button
                IconButton(
                  icon: const Icon(Icons.settings, size: 20),
                  tooltip: 'Tabs verwalten',
                  onPressed: _showTabConfigDialog,
                  color: Colors.grey.shade600,
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildTabContent('arbeitgeber', () {
                  // Lade Hausarzt-Daten falls nicht vorhanden (fuer Krankmeldungen)
                  if (!_behoerdeData.containsKey('gesundheit_hausarzt') && _behoerdeLoading['gesundheit_hausarzt'] != true) {
                    _loadBehoerdeData('gesundheit_hausarzt');
                  }
                  return ArbeitgeberBehoerdeContent(
                    user: widget.user,
                    apiService: widget.apiService,
                    dbArbeitgeberListe: _dbArbeitgeberListe,
                    behoerdeData: _behoerdeData['arbeitgeber'] ?? {},
                    isLoading: _behoerdeLoading['arbeitgeber'] == true,
                    onSave: () {},
                    onDataChanged: (data) => _saveBehoerdeData('arbeitgeber', data),
                    hausarztData: _behoerdeData['gesundheit_hausarzt'] ?? {},
                    ticketService: widget.ticketService,
                    adminMitgliedernummer: widget.adminMitgliedernummer,
                  );
                }),
                BehordeArbeitsagenturContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                  arbeitsvermittlerBuilder: ({required type, required data, required arbeitsvermittlerController, required arbeitsvermittlerTelController, required arbeitsvermittlerEmailController, required setLocalState}) => _buildArbeitsvermittlerSection(data: data, arbeitsvermittlerController: arbeitsvermittlerController, arbeitsvermittlerTelController: arbeitsvermittlerTelController, arbeitsvermittlerEmailController: arbeitsvermittlerEmailController, setLocalState: setLocalState),
                  antraegeBuilder: ({required behoerdeType, required antraege, required artItems, required statusItems, required onChanged, required context}) => _buildAntraegeSection(behoerdeType: behoerdeType, antraege: antraege, artItems: artItems, statusItems: statusItems, onChanged: onChanged, context: context),
                  meldungenBuilder: ({required meldungen, required onChanged, required context}) => _buildMeldungenSection(meldungen: meldungen, onChanged: onChanged, context: context),
                  begutachtungBuilder: ({required behoerdeType, required behoerdeLabel, required begutachtungen, required data, required onChanged, required setLocalState}) => _buildBegutachtungSection(behoerdeType: behoerdeType, behoerdeLabel: behoerdeLabel, begutachtungen: begutachtungen, data: data, onChanged: onChanged, setLocalState: setLocalState),
                  termineBuilder: ({required behoerdeType, required behoerdeLabel, required termine, required data, required onChanged, required setLocalState}) => _buildBehoerdeTermineSection(behoerdeType: behoerdeType, behoerdeLabel: behoerdeLabel, termine: termine, data: data, onChanged: onChanged, setLocalState: setLocalState),
                  autoSaveField: (t, f, v) => _autoSaveField(t, f, v),
                  getTermineListe: (d) => _getTermineListe(d),
                  getBegutachtungen: (d) => _getBegutachtungen(d),
                  getMeldungen: (d) => _getMeldungen(d),
                  getAntraege: (d) => _getAntraege(d),
                  ticketService: TicketService(),
                  adminMitgliedernummer: widget.adminMitgliedernummer,
                  memberMitgliedernummer: widget.user.mitgliedernummer,
                  memberName: widget.user.name,
                ),
                BehordeJobcenterContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                ),
                _buildTabContent('landratsamt', () => BehordeLandratsamtContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                )),
                BehordeSozialamtContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeFinanzamtContent(
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                  apiService: widget.apiService,
                  user: widget.user,
                ),
                BehordeGerichtContent(
                  user: widget.user,
                  apiService: widget.apiService,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                ),
                BehordeKrankenkasseContent(
                  apiService: widget.apiService,
                  ticketService: widget.ticketService,
                  user: widget.user,
                  adminMitgliedernummer: widget.adminMitgliedernummer,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                  termineBuilder: ({required behoerdeType, required behoerdeLabel, required termine, required data, required onChanged, required setLocalState}) => _buildBehoerdeTermineSection(behoerdeType: behoerdeType, behoerdeLabel: behoerdeLabel, termine: termine, data: data, onChanged: onChanged, setLocalState: setLocalState),
                  autoSaveField: (t, f, v) => _autoSaveField(t, f, v),
                ),
                BehordeRentenversicherungContent(
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeAuslaenderbehoerdeContent(
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeFamilienkasseContent(
                  apiService: widget.apiService,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeJugendamtContent(
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeEinwohnermeldeamtContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeWohngeldstelleContent(
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeBamfContent(
                  apiService: widget.apiService,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                  dienststelleBuilder: (t, c) => _buildDienststelleField(t, c),
                ),
                BehordeVermieterContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                ),
                BehordeDeutschlandticketContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                ),
                BehordeSchuleContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                ),
                BehordeKonsulatContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                ),
                BehordePolizeiContent(
                  apiService: widget.apiService,
                  adminMitgliedernummer: widget.adminMitgliedernummer,
                  clientMitgliedernummer: widget.user.mitgliedernummer,
                  userId: widget.user.id,
                ),
                _buildTabContent('versorgungsamt', () => BehordeVersorgungsamtContent(
                  apiService: widget.apiService,
                  terminService: widget.terminService,
                  userId: widget.user.id,
                  user: widget.user,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                )),
                _buildTabContent('rundfunkbeitrag', () => BehordeRundfunkbeitragContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                  user: widget.user,
                  getData: (t) => _behoerdeData[t] ?? {},
                  isLoading: (t) => _behoerdeLoading[t] == true,
                  isSaving: (t) => _behoerdeSaving[t] == true,
                  loadData: (t) => _loadBehoerdeData(t),
                  saveData: (t, d) => _saveBehoerdeData(t, d),
                )),
                _buildTabContent('kindergarten', () => BehordeKindergartenContent(
                  apiService: widget.apiService,
                  userId: widget.user.id,
                )),
              ],
            ),
          ),
          ],
        ),
      );
  }

  Widget _behoerdeTabItem(IconData icon, String label, bool isCompact, {required String type, required bool enabled, required int completionPct}) {
    final Color pctColor;
    if (completionPct == 0) {
      pctColor = Colors.grey;
    } else if (completionPct < 50) {
      pctColor = Colors.orange;
    } else if (completionPct < 100) {
      pctColor = Colors.blue;
    } else {
      pctColor = Colors.green;
    }

    final opacity = enabled ? 1.0 : 0.35;

    if (isCompact) {
      return Tab(
        child: Opacity(
          opacity: opacity,
          child: Tooltip(
            message: enabled ? '$label ($completionPct%)' : '$label (deaktiviert)',
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(icon, size: 18),
                if (completionPct > 0)
                  Positioned(
                    right: -8,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                      decoration: BoxDecoration(color: pctColor, borderRadius: BorderRadius.circular(6)),
                      child: Text('$completionPct', style: const TextStyle(fontSize: 8, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Tab(
      child: Opacity(
        opacity: opacity,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
            const SizedBox(width: 4),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: pctColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pctColor.withValues(alpha: 0.4), width: 0.5),
              ),
              child: Text('$completionPct%', style: TextStyle(fontSize: 9, color: pctColor, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  /// Wrapper: show disabled message if tab is not enabled
  Widget _buildTabContent(String type, Widget Function() builder) {
    final enabled = _enabledTabs.isEmpty || _enabledTabs.contains(type);
    if (!enabled) {
      final def = _tabDefs.firstWhere((d) => d['type'] == type);
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(def['icon'] as IconData, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('${def['label']} ist f\u00FCr dieses Mitglied deaktiviert.',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() => _enabledTabs.add(type));
                _saveTabConfig();
              },
              icon: const Icon(Icons.visibility, size: 16),
              label: const Text('Aktivieren'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
            ),
          ],
        ),
      );
    }
    return builder();
  }

  /// Dialog to manage which tabs are enabled
  void _showTabConfigDialog() {
    final tempEnabled = Set<String>.from(_enabledTabs);
    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.settings, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(child: Text('Tabs verwalten', style: TextStyle(fontSize: 16))),
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        tempEnabled.clear();
                        tempEnabled.addAll(_allTypes);
                      });
                    },
                    child: const Text('Alle an', style: TextStyle(fontSize: 12)),
                  ),
                  TextButton(
                    onPressed: () {
                      setDialogState(() => tempEnabled.clear());
                    },
                    child: const Text('Alle aus', style: TextStyle(fontSize: 12)),
                  ),
                ],
              ),
              content: SizedBox(
                width: 400,
                child: ListView(
                  shrinkWrap: true,
                  children: _tabDefs.map((def) {
                    final type = def['type'] as String;
                    final icon = def['icon'] as IconData;
                    final label = def['label'] as String;
                    final pct = _getCompletionPercent(type);
                    final isOn = tempEnabled.contains(type);
                    return CheckboxListTile(
                      value: isOn,
                      dense: true,
                      secondary: Icon(icon, size: 20, color: isOn ? Colors.blue : Colors.grey.shade400),
                      title: Text(label, style: TextStyle(fontSize: 13, color: isOn ? Colors.black : Colors.grey)),
                      subtitle: Text('$pct% ausgef\u00FCllt', style: TextStyle(fontSize: 11, color: pct > 0 ? Colors.green.shade700 : Colors.grey)),
                      onChanged: (val) {
                        setDialogState(() {
                          if (val == true) {
                            tempEnabled.add(type);
                          } else {
                            tempEnabled.remove(type);
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _enabledTabs = tempEnabled);
                    _saveTabConfig();
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Tab-Konfiguration gespeichert'), backgroundColor: Colors.green),
                    );
                  },
                  child: const Text('Speichern'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildArbeitsvermittlerSection({
    required Map<String, dynamic> data,
    required TextEditingController arbeitsvermittlerController,
    required TextEditingController arbeitsvermittlerTelController,
    required TextEditingController arbeitsvermittlerEmailController,
    required StateSetter setLocalState,
  }) {
    // Lazy-load Arbeitsvermittler from DB
    if (!_arbeitsvermittlerLoaded) {
      _arbeitsvermittlerLoaded = true;
      widget.apiService.getArbeitsvermittler().then((result) {
        if (mounted) setState(() => _arbeitsvermittlerListe = result);
      });
    }

    final selectedId = data['arbeitsvermittler_id'];
    Map<String, dynamic>? selected;
    if (selectedId != null) {
      for (final av in _arbeitsvermittlerListe) {
        if (av['id'].toString() == selectedId.toString()) { selected = av; break; }
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBehoerdeSectionHeader(Icons.support_agent, 'Arbeitsvermittler', Colors.teal),
        const SizedBox(height: 8),
        // Dropdown + Neu button - always visible
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.teal.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.teal.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.person_search, size: 16, color: Colors.teal.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Arbeitsvermittler/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700))),
                  TextButton.icon(
                    onPressed: () => _showAddArbeitsvermittlerDialog(setLocalState),
                    icon: Icon(Icons.person_add, size: 14, color: Colors.teal.shade700),
                    label: Text('Neu hinzufugen', style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
                    style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                isExpanded: true,
                initialValue: selectedId?.toString(),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                  filled: true,
                  fillColor: Colors.white,
                  hintText: _arbeitsvermittlerListe.isEmpty ? 'Keine Arbeitsvermittler vorhanden' : 'Arbeitsvermittler/in auswahlen...',
                  hintStyle: const TextStyle(fontSize: 12),
                ),
                items: _arbeitsvermittlerListe.map((av) {
                  final anrede = av['anrede']?.toString() ?? '';
                  final name = av['name']?.toString() ?? '';
                  final ort = av['standort_name']?.toString() ?? '';
                  return DropdownMenuItem<String>(
                    value: av['id'].toString(),
                    child: Text('${anrede.isNotEmpty ? '$anrede ' : ''}$name${ort.isNotEmpty ? ' ($ort)' : ''}', style: const TextStyle(fontSize: 12)),
                  );
                }).toList(),
                onChanged: (v) {
                  setLocalState(() {
                    data['arbeitsvermittler_id'] = v;
                    if (v != null) {
                      for (final av in _arbeitsvermittlerListe) {
                        if (av['id'].toString() == v) {
                          final anrede = av['anrede']?.toString() ?? '';
                          arbeitsvermittlerController.text = '${anrede.isNotEmpty ? '$anrede ' : ''}${av['name'] ?? ''}';
                          arbeitsvermittlerTelController.text = av['telefon']?.toString() ?? '';
                          arbeitsvermittlerEmailController.text = av['email']?.toString() ?? '';
                          break;
                        }
                      }
                    }
                  });
                },
              ),
            ],
          ),
        ),
        // Show selected details card
        if (selected != null) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.badge, size: 16, color: Colors.teal.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${selected['anrede'] ?? ''} ${selected['name'] ?? ''}', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
                  ],
                ),
                if ((selected['standort_name']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(children: [
                    Icon(Icons.business, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(child: Text(selected['standort_name'], style: const TextStyle(fontSize: 11))),
                  ]),
                ],
                if ((selected['strasse']?.toString() ?? '').isNotEmpty || (selected['plz_ort']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.place, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(child: Text('${selected['strasse'] ?? ''}, ${selected['plz_ort'] ?? ''}', style: const TextStyle(fontSize: 11))),
                  ]),
                ],
                if ((selected['zimmernummer']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.door_front_door, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text('Zimmer ${selected['zimmernummer']}', style: const TextStyle(fontSize: 11)),
                  ]),
                ],
                if ((selected['telefon']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.phone, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(selected['telefon'], style: const TextStyle(fontSize: 11)),
                  ]),
                ],
                if ((selected['email']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.email, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(selected['email'], style: const TextStyle(fontSize: 11)),
                  ]),
                ],
                if ((selected['oeffnungszeiten']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(children: [
                    Icon(Icons.schedule, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(child: Text(selected['oeffnungszeiten'], style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showAddArbeitsvermittlerDialog(StateSetter parentSetState) {
    final nameC = TextEditingController();
    String anrede = 'Frau';
    final standortNameC = TextEditingController();
    final strasseC = TextEditingController();
    final plzOrtC = TextEditingController();
    final zimmerC = TextEditingController();
    final telefonC = TextEditingController();
    final emailC = TextEditingController();
    final oeffnungszeitenC = TextEditingController();
    final notizenC = TextEditingController();

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) => AlertDialog(
          title: Row(children: [
            Icon(Icons.person_add, size: 20, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Expanded(child: Text('Neuer Arbeitsvermittler', style: TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    SizedBox(
                      width: 120,
                      child: DropdownButtonFormField<String>(
                        initialValue: anrede,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: 'Anrede',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'Frau', child: Text('Frau', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'Herr', child: Text('Herr', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setDlgState(() => anrede = v ?? 'Frau'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: nameC,
                        decoration: InputDecoration(
                          labelText: 'Name *',
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: standortNameC, decoration: InputDecoration(labelText: 'Standort / Dienststelle', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: strasseC, decoration: InputDecoration(labelText: 'Strasse', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: plzOrtC, decoration: InputDecoration(labelText: 'PLZ Ort', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13))),
                  ]),
                  const SizedBox(height: 10),
                  Row(children: [
                    Expanded(child: TextField(controller: zimmerC, decoration: InputDecoration(labelText: 'Zimmernummer', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13))),
                    const SizedBox(width: 12),
                    Expanded(child: TextField(controller: telefonC, decoration: InputDecoration(labelText: 'Telefon', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13))),
                  ]),
                  const SizedBox(height: 10),
                  TextField(controller: emailC, decoration: InputDecoration(labelText: 'E-Mail', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(controller: oeffnungszeitenC, decoration: InputDecoration(labelText: 'Offnungszeiten', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13)),
                  const SizedBox(height: 10),
                  TextField(controller: notizenC, maxLines: 2, decoration: InputDecoration(labelText: 'Notizen', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10)), style: const TextStyle(fontSize: 13)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
            FilledButton.icon(
              icon: const Icon(Icons.save, size: 16),
              label: const Text('Speichern'),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade600),
              onPressed: () async {
                if (nameC.text.trim().isEmpty) return;
                final result = await widget.apiService.manageArbeitsvermittler({
                  'action': 'add',
                  'name': nameC.text.trim(),
                  'anrede': anrede,
                  'standort_name': standortNameC.text.trim(),
                  'strasse': strasseC.text.trim(),
                  'plz_ort': plzOrtC.text.trim(),
                  'zimmernummer': zimmerC.text.trim(),
                  'telefon': telefonC.text.trim(),
                  'email': emailC.text.trim(),
                  'oeffnungszeiten': oeffnungszeitenC.text.trim(),
                  'notizen': notizenC.text.trim(),
                });
                if (result['success'] == true && result['arbeitsvermittler'] != null) {
                  _arbeitsvermittlerListe.add(Map<String, dynamic>.from(result['arbeitsvermittler']));
                  if (mounted) parentSetState(() {});
                }
                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              },
            ),
          ],
        ),
      ),
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



  /// Find selected standort from cache by matching controller text
  Map<String, dynamic>? _findSelectedStandort(String type, String controllerText) {
    final standortTyp = type == 'jobcenter' ? 'jobcenter' : (type == 'bundesagentur' ? 'arbeitsagentur' : (type == 'krankenkasse' ? 'krankenkasse' : null));
    if (standortTyp == null) return null;
    final standorte = _behoerdenStandorte[standortTyp] ?? [];
    for (final s in standorte) {
      final fullText = '${s['name']}, ${s['strasse']}, ${s['plz_ort']}';
      if (controllerText == fullText || controllerText == s['name']) return s;
    }
    return null;
  }

  Widget _buildDienststelleField(String type, TextEditingController controller, {StateSetter? setLocalState}) {
    final hasStandortDb = type == 'jobcenter' || type == 'bundesagentur' || type == 'krankenkasse';
    final standortTyp = type == 'jobcenter' ? 'jobcenter' : (type == 'bundesagentur' ? 'arbeitsagentur' : (type == 'krankenkasse' ? 'krankenkasse' : null));
    // Lazy-load standorte on first access
    if (hasStandortDb && !_behoerdenStandorte.containsKey(standortTyp)) {
      _behoerdenStandorte[standortTyp!] = [];
      widget.apiService.getBehoerdenStandorte(typ: standortTyp).then((result) {
        if (result.isNotEmpty && mounted) {
          setState(() => _behoerdenStandorte[standortTyp] = result);
        }
      });
    }

    final standorte = hasStandortDb ? (_behoerdenStandorte[standortTyp] ?? []) : <Map<String, dynamic>>[];
    final selectedStandort = hasStandortDb ? _findSelectedStandort(type, controller.text) : null;

    // Logo & colors per type
    final isJobcenter = type == 'jobcenter';
    final isKrankenkasse = type == 'krankenkasse';
    final brandColor = isJobcenter ? const Color(0xFFE30613) : (isKrankenkasse ? const Color(0xFF00843D) : const Color(0xFF003F7D)); // JC red, KK green, AA blue
    final brandIcon = isJobcenter ? Icons.work : (isKrankenkasse ? Icons.local_hospital : Icons.account_balance);
    final brandLabel = isJobcenter ? 'Jobcenter' : (isKrankenkasse ? 'Krankenkasse' : 'Agentur für Arbeit');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(children: [
          Icon(brandIcon, size: 16, color: brandColor),
          const SizedBox(width: 6),
          Text('Zuständige Behörde', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: brandColor)),
        ]),
        const SizedBox(height: 8),

        // If a standort is selected, show info card
        if (selectedStandort != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [brandColor.withValues(alpha: 0.05), brandColor.withValues(alpha: 0.12)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: brandColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Logo row
                Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: brandColor,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(brandIcon, color: Colors.white, size: 22),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(selectedStandort['name']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: brandColor)),
                          Text(brandLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                    // Change button
                    InkWell(
                      onTap: () {
                        controller.clear();
                        _autoSaveField(type, 'dienststelle', '');
                        setLocalState?.call(() {});
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: Text('Ändern', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Address
                _buildStandortInfoRow(Icons.place, '${selectedStandort['strasse']}, ${selectedStandort['plz_ort']}'),
                // Phone
                if ((selectedStandort['telefon']?.toString() ?? '').isNotEmpty)
                  _buildStandortInfoRow(Icons.phone, selectedStandort['telefon'].toString()),
                // Fax
                if ((selectedStandort['fax']?.toString() ?? '').isNotEmpty)
                  _buildStandortInfoRow(Icons.fax, selectedStandort['fax'].toString()),
                // Email
                if ((selectedStandort['email']?.toString() ?? '').isNotEmpty)
                  _buildStandortInfoRow(Icons.email, selectedStandort['email'].toString()),
                // Website
                if ((selectedStandort['website']?.toString() ?? '').isNotEmpty)
                  _buildStandortInfoRow(Icons.language, selectedStandort['website'].toString()),
                // Opening hours
                if ((selectedStandort['oeffnungszeiten']?.toString() ?? '').isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Icon(Icons.access_time, size: 13, color: brandColor),
                          const SizedBox(width: 4),
                          Text('Öffnungszeiten', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: brandColor)),
                        ]),
                        const SizedBox(height: 4),
                        Text(
                          selectedStandort['oeffnungszeiten'].toString(),
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade700, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ] else if (hasStandortDb && standorte.isNotEmpty) ...[
          // Dropdown to select
          DropdownButtonFormField<int>(
            isExpanded: true,
            decoration: InputDecoration(
              labelText: '$brandLabel auswählen',
              prefixIcon: Icon(brandIcon, size: 18, color: brandColor),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            hint: Text('$brandLabel auswählen...', style: const TextStyle(fontSize: 13)),
            items: standorte.map((s) {
              final id = s['id'] is int ? s['id'] as int : int.tryParse(s['id'].toString()) ?? 0;
              return DropdownMenuItem<int>(
                value: id,
                child: Text('${s['name']} — ${s['plz_ort']}', style: const TextStyle(fontSize: 12)),
              );
            }).toList(),
            onChanged: (id) {
              if (id == null) return;
              final sel = standorte.firstWhere(
                (s) => (s['id'] is int ? s['id'] : int.tryParse(s['id'].toString())) == id,
                orElse: () => {},
              );
              if (sel.isNotEmpty) {
                final fullText = '${sel['name']}, ${sel['strasse']}, ${sel['plz_ort']}';
                controller.text = fullText;
                _autoSaveField(type, 'dienststelle', fullText);
                // Update ort in all existing termine
                _updateTermineOrt(type, fullText);
                setLocalState?.call(() {});
              }
            },
          ),
        ] else ...[
          // Manual input fallback (no DB or other types)
          TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: 'Dienststelle eingeben',
              prefixIcon: const Icon(Icons.location_city, size: 20),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              isDense: true,
            ),
            onChanged: (val) => _autoSaveField(type, 'dienststelle', val.trim()),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }

  /// Update ort in all existing termine when Dienststelle changes
  void _updateTermineOrt(String type, String newOrt) {
    final data = _behoerdeData[type];
    if (data == null) return;
    final termine = _getTermineListe(data);
    if (termine.isEmpty) return;
    bool changed = false;
    for (final t in termine) {
      if (t['ort']?.toString() != newOrt) {
        t['ort'] = newOrt;
        changed = true;
      }
    }
    if (changed) {
      data['termine'] = termine;
      _autoSaveField(type, 'termine', termine);
    }
  }

  Widget _buildStandortInfoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 13, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  // === ANTRAEGE HELPERS ===

  /// Migrate old flat antrag fields to new antraege list format
  List<Map<String, dynamic>> _getAntraege(Map<String, dynamic> data) {
    // New format already exists
    if (data['antraege'] is List && (data['antraege'] as List).isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        (data['antraege'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    // Migrate old flat format
    if ((data['antrag_art'] ?? '').toString().isNotEmpty) {
      final now = DateTime.now();
      final datum = (data['antrag_datum'] ?? '').toString();
      final status = (data['antrag_status'] ?? '').toString();
      return [
        {
          'art': data['antrag_art'],
          'status': status,
          'datum': datum,
          'notiz': data['antrag_notiz'] ?? '',
          'verlauf': [
            {
              'datum': datum.isNotEmpty ? datum : '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}',
              'status': status,
              'aktion': 'Antrag erstellt (migriert)',
            },
          ],
        },
      ];
    }
    return [];
  }

  List<Map<String, dynamic>> _getTermineListe(Map<String, dynamic> data) {
    if (data['termine'] is List && (data['termine'] as List).isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        (data['termine'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  }

  /// Get status display text with emoji
  String _antragStatusText(String status) {
    const map = {
      'eingereicht': 'Eingereicht',
      'in_bearbeitung': 'In Bearbeitung',
      'unterlagen_fehlen': 'Unterlagen nachgefordert',
      'unterlagen_nachgefordert': 'Unterlagen nachgefordert',
      'bewilligt': 'Bewilligt',
      'teilweise_bewilligt': 'Teilweise bewilligt',
      'abgelehnt': 'Abgelehnt',
      'widerspruch': 'Widerspruch eingelegt',
      'klage': 'Klage beim Sozialgericht',
      'beantragt': 'Beantragt',
      'laufend': 'Laufend',
      'zurueckgezogen': 'Zuruckgezogen',
      'verweigerung': 'Verweigerung durch Mitglied',
    };
    return map[status] ?? status;
  }

  Color _antragStatusColor(String status) {
    switch (status) {
      case 'eingereicht':
      case 'beantragt':
        return Colors.blue;
      case 'in_bearbeitung':
        return Colors.orange;
      case 'unterlagen_fehlen':
      case 'unterlagen_nachgefordert':
        return Colors.amber.shade800;
      case 'bewilligt':
        return Colors.green;
      case 'teilweise_bewilligt':
        return Colors.teal;
      case 'abgelehnt':
        return Colors.red;
      case 'widerspruch':
        return Colors.deepPurple;
      case 'klage':
        return Colors.brown;
      case 'zurueckgezogen':
        return Colors.blueGrey;
      case 'verweigerung':
        return Colors.red.shade900;
      default:
        return Colors.grey;
    }
  }

  String _antragArtText(String art, String behoerdeType) {
    if (behoerdeType == 'bundesagentur') {
      const map = {
        'erstantrag': 'Erstantrag ALG I',
        'weiterbewilligung': 'Weiterbewilligungsantrag',
        'wiederholung': 'Wiederholungsantrag',
      };
      return map[art] ?? art;
    } else {
      const map = {
        'erstantrag': 'Erstantrag',
        'weiterbewilligung': 'Weiterbewilligungsantrag (WBA)',
        'aenderungsantrag': 'Anderungsantrag',
        'mehrbedarf': 'Antrag auf Mehrbedarf',
        'erstausstattung': 'Antrag auf Erstausstattung',
        'umzugskosten': 'Antrag auf Umzugskosten',
        'but': 'Bildung und Teilhabe (BuT)',
        'ueberpruefung': 'Uberpruefungsantrag',
      };
      return map[art] ?? art;
    }
  }

  /// Show dialog to create or edit an Antrag
  Future<Map<String, dynamic>?> _showAntragDialog({
    required BuildContext context,
    required String behoerdeType,
    required List<DropdownMenuItem<String>> artItems,
    required List<DropdownMenuItem<String>> statusItems,
    Map<String, dynamic>? existingAntrag,
  }) async {
    final antragId = existingAntrag?['id']?.toString() ?? DateTime.now().millisecondsSinceEpoch.toString();
    String art = existingAntrag?['art'] ?? '';
    String status = existingAntrag?['status'] ?? '';
    String einreichungsweg = existingAntrag?['einreichungsweg'] ?? 'online';
    final datumController = TextEditingController(text: existingAntrag?['datum'] ?? '');
    final notizController = TextEditingController(text: existingAntrag?['notiz'] ?? '');
    final isEdit = existingAntrag != null;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(isEdit ? Icons.edit : Icons.add_circle, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'Antrag bearbeiten' : 'Neuer Antrag', style: const TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Antragsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: art.isEmpty ? null : art,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        hint: const Text('Auswahlen...', style: TextStyle(fontSize: 13)),
                        items: artItems,
                        onChanged: (v) => setDlgState(() => art = v ?? ''),
                      ),
                      const SizedBox(height: 16),
                      Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: status.isEmpty ? null : status,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        hint: const Text('Status...', style: TextStyle(fontSize: 13)),
                        items: statusItems,
                        onChanged: (v) => setDlgState(() => status = v ?? ''),
                      ),
                      const SizedBox(height: 16),
                      Text('Einreichungsweg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: einreichungsweg,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          prefixIcon: const Icon(Icons.send, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'vor_ort', child: Text('Vor Ort (persoenlich)', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'online', child: Text('Online', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'post', child: Text('Per Post', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'telefonisch', child: Text('Telefonisch', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setDlgState(() => einreichungsweg = v ?? 'online'),
                      ),
                      const SizedBox(height: 16),
                      Text('Eingereicht am', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: datumController,
                        readOnly: true,
                        decoration: InputDecoration(
                          hintText: 'TT.MM.JJJJ',
                          prefixIcon: const Icon(Icons.calendar_today, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            locale: const Locale('de', 'DE'),
                          );
                          if (picked != null) {
                            datumController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: notizController,
                        maxLines: 3,
                        decoration: InputDecoration(
                          hintText: 'z.B. Fehlende Unterlagen, Fristen...',
                          prefixIcon: const Icon(Icons.notes, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Divider(),
                      _buildAntragDokumente(
                        antragId: antragId,
                        behoerdeType: behoerdeType,
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
                  onPressed: art.isEmpty ? null : () {
                    final now = DateTime.now();
                    final nowStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
                    final Map<String, dynamic> result = {
                      'id': antragId,
                      'art': art,
                      'status': status,
                      'einreichungsweg': einreichungsweg,
                      'datum': datumController.text.trim(),
                      'notiz': notizController.text.trim(),
                    };

                    // Build verlauf
                    List<Map<String, dynamic>> verlauf = [];
                    if (isEdit) {
                      verlauf = List<Map<String, dynamic>>.from(
                        (existingAntrag['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
                      );
                      // Check if status changed
                      if (status != existingAntrag['status']) {
                        verlauf.add({
                          'datum': nowStr,
                          'status': status,
                          'alter_status': existingAntrag['status'],
                          'aktion': 'Status geandert: ${_antragStatusText(existingAntrag['status'] ?? '')} -> ${_antragStatusText(status)}',
                        });
                      }
                      // Check if notiz changed
                      if (notizController.text.trim() != (existingAntrag['notiz'] ?? '')) {
                        verlauf.add({
                          'datum': nowStr,
                          'aktion': 'Notiz aktualisiert',
                          'status': status,
                        });
                      }
                    } else {
                      final wegLabel = einreichungsweg == 'vor_ort' ? 'Vor Ort' : einreichungsweg == 'online' ? 'Online' : einreichungsweg == 'post' ? 'Per Post' : 'Telefonisch';
                      final statusLabels = {'neu': 'Neu', 'geplant': 'Geplant', 'eingereicht': 'Eingereicht', 'in_bearbeitung': 'In Bearbeitung', 'unterlagen_fehlen': 'Unterlagen nachgefordert', 'bewilligt': 'Bewilligt', 'abgelehnt': 'Abgelehnt', 'zurueckgezogen': 'Zurückgezogen', 'verweigerung': 'Verweigerung'};
                      final actualStatus = status.isNotEmpty ? status : 'neu';
                      final aktionText = actualStatus == 'neu' ? 'Neu' : actualStatus == 'geplant' ? 'Geplant' : 'Antrag ${statusLabels[actualStatus] ?? actualStatus} ($wegLabel)';
                      verlauf = [
                        {
                          'datum': datumController.text.trim().isNotEmpty ? datumController.text.trim() : nowStr,
                          'status': actualStatus,
                          'aktion': aktionText,
                        },
                      ];
                    }
                    result['verlauf'] = verlauf;

                    Navigator.pop(ctx, result);
                  },
                  icon: Icon(isEdit ? Icons.save : Icons.add, size: 18),
                  label: Text(isEdit ? 'Speichern' : 'Hinzufugen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildAntragDokumente({
    required String antragId,
    required String behoerdeType,
  }) {
    if (antragId.isEmpty) return const SizedBox.shrink();

    final refreshKey = ValueNotifier<int>(0);

    return ValueListenableBuilder<int>(
      valueListenable: refreshKey,
      builder: (context, _, __) {
        return FutureBuilder<Map<String, dynamic>>(
          key: ValueKey('antrag_docs_${antragId}_${refreshKey.value}'),
          future: widget.apiService.getAntragDokumente(
            userId: widget.user.id,
            behoerdeType: behoerdeType,
            antragId: antragId,
          ),
          builder: (context, snapshot) {
            final docs = (snapshot.data?['dokumente'] as List?)
                ?.map((e) => Map<String, dynamic>.from(e as Map))
                .toList() ?? [];
            final isLoading = snapshot.connectionState == ConnectionState.waiting;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.attach_file, size: 16, color: Colors.teal.shade700),
                    const SizedBox(width: 6),
                    Text('Dokumente', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                    if (docs.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: Colors.teal.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('${docs.length}/10', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                      ),
                    ],
                    const Spacer(),
                    if (!isLoading && docs.length < 10)
                      TextButton.icon(
                        onPressed: () async {
                          final remaining = 10 - docs.length;
                          final result = await FilePickerHelper.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
                            allowMultiple: true,
                          );
                          if (result != null && result.files.isNotEmpty) {
                            final filesToUpload = result.files.take(remaining).toList();
                            if (result.files.length > remaining && context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Max 10 Dokumente - nur $remaining werden hochgeladen'), backgroundColor: Colors.orange),
                              );
                            }

                            // Show progress dialog
                            if (!context.mounted) return;
                            showDialog(
                              context: context,
                              barrierDismissible: false,
                              builder: (dlgCtx) {
                                return _AntragUploadProgressDialog(
                                  files: filesToUpload,
                                  apiService: widget.apiService,
                                  userId: widget.user.id,
                                  behoerdeType: behoerdeType,
                                  antragId: antragId,
                                  onComplete: (successCount, errorMsg) {
                                    Navigator.pop(dlgCtx);
                                    refreshKey.value++;
                                    if (context.mounted) {
                                      if (errorMsg != null) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('Fehler: $errorMsg'), backgroundColor: Colors.red),
                                        );
                                      } else {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(content: Text('$successCount Dokument(e) hochgeladen'), backgroundColor: Colors.green),
                                        );
                                      }
                                    }
                                  },
                                );
                              },
                            );
                          }
                        },
                        icon: Icon(Icons.upload_file, size: 16, color: Colors.teal.shade700),
                        label: Text('Hochladen (JPG/PDF)', style: TextStyle(fontSize: 11, color: Colors.teal.shade700)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2)),
                      ),
                  ],
                ),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.all(8),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (docs.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Keine Dokumente vorhanden', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                  )
                else
                  Container(
                    margin: const EdgeInsets.only(top: 6),
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.teal.shade100),
                    ),
                    child: Column(
                      children: docs.map((doc) {
                        final isPdf = (doc['mime_type'] ?? '').toString().contains('pdf');
                        final size = ((doc['file_size'] ?? 0) as num) / 1024;
                        final sizeStr = size > 1024 ? '${(size / 1024).toStringAsFixed(1)} MB' : '${size.toStringAsFixed(0)} KB';
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Icon(isPdf ? Icons.picture_as_pdf : Icons.image, size: 18, color: isPdf ? Colors.red : Colors.blue),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(doc['filename'] ?? '', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                                    Text(sizeStr, style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                  ],
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.visibility, size: 16, color: Colors.indigo.shade600),
                                tooltip: 'Vorschau',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                onPressed: () async {
                                  try {
                                    final response = await widget.apiService.downloadAntragDokument(doc['id'] as int);
                                    if (response.statusCode == 200) {
                                      final tempDir = await getTemporaryDirectory();
                                      final fileName = doc['filename'] ?? 'dokument';
                                      final tempFile = io.File('${tempDir.path}/$fileName');
                                      await tempFile.writeAsBytes(response.bodyBytes);
                                      if (context.mounted) {
                                        await FileViewerDialog.show(context, tempFile.path, fileName);
                                      }
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: Icon(Icons.download, size: 16, color: Colors.teal.shade700),
                                tooltip: 'Herunterladen',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                onPressed: () async {
                                  try {
                                    final response = await widget.apiService.downloadAntragDokument(doc['id'] as int);
                                    if (response.statusCode == 200) {
                                      final savePath = await FilePickerHelper.saveFile(
                                        dialogTitle: 'Dokument speichern',
                                        fileName: doc['filename'] ?? 'dokument',
                                      );
                                      if (savePath != null) {
                                        final file = io.File(savePath);
                                        await file.writeAsBytes(response.bodyBytes);
                                        if (context.mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(content: Text('Dokument gespeichert'), backgroundColor: Colors.green),
                                          );
                                        }
                                      }
                                    }
                                  } catch (e) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
                                      );
                                    }
                                  }
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                                tooltip: 'Loschen',
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: const Text('Dokument loschen?', style: TextStyle(fontSize: 15)),
                                      content: Text('${doc['filename']} wirklich loschen?'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(ctx, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                          child: const Text('Loschen'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await widget.apiService.deleteAntragDokument(doc['id'] as int);
                                    refreshKey.value++;
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAntragDetailDialog({
    required BuildContext context,
    required Map<String, dynamic> antrag,
    required int idx,
    required String behoerdeType,
    required List<DropdownMenuItem<String>> artItems,
    required List<DropdownMenuItem<String>> statusItems,
    required List<Map<String, dynamic>> antraege,
    required void Function(List<Map<String, dynamic>>) onChanged,
  }) {
    final art = antrag['art'] ?? '';
    final status = antrag['status'] ?? '';
    final weg = antrag['einreichungsweg'] ?? '';
    final datum = antrag['datum'] ?? '';
    final notiz = antrag['notiz'] ?? '';
    final verlauf = List<Map<String, dynamic>>.from(
      (antrag['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    final wegLabel = weg == 'vor_ort' ? 'Vor Ort' : weg == 'online' ? 'Online' : weg == 'post' ? 'Per Post' : weg == 'telefonisch' ? 'Telefonisch' : weg;

    showDialog(context: context, builder: (dlgCtx) => DefaultTabController(length: 3, child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      contentPadding: EdgeInsets.zero,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.description, color: _antragStatusColor(status), size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(_antragArtText(art, behoerdeType), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: _antragStatusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
            child: Text(_antragStatusText(status), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: _antragStatusColor(status)))),
          const SizedBox(width: 4),
          IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.orange.shade700), tooltip: 'Bearbeiten', onPressed: () async {
            Navigator.pop(dlgCtx);
            final result = await _showAntragDialog(context: context, behoerdeType: behoerdeType, artItems: artItems, statusItems: statusItems, existingAntrag: antrag);
            if (result != null) { final updated = List<Map<String, dynamic>>.from(antraege); updated[idx] = result; onChanged(updated); }
          }),
          IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async {
            Navigator.pop(dlgCtx);
            final updated = List<Map<String, dynamic>>.from(antraege)..removeAt(idx);
            onChanged(updated);
          }),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx)),
        ]),
        const SizedBox(height: 4),
        TabBar(labelColor: Colors.orange.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.orange.shade700, tabs: const [
          Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
          Tab(icon: Icon(Icons.folder_open, size: 16), text: 'Dokumente'),
          Tab(icon: Icon(Icons.history, size: 16), text: 'Verlauf'),
        ]),
      ]),
      content: SizedBox(width: 550, height: 400, child: TabBarView(children: [
        // ═══ TAB 1: Details ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _antragDetailRow(Icons.category, 'Art', _antragArtText(art, behoerdeType)),
              _antragDetailRow(Icons.flag, 'Status', _antragStatusText(status)),
              if (datum.isNotEmpty) _antragDetailRow(Icons.calendar_today, 'Datum', datum),
              if (wegLabel.isNotEmpty) _antragDetailRow(Icons.send, 'Einreichungsweg', wegLabel),
            ])),
          if (notiz.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('Notiz', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(notiz, style: const TextStyle(fontSize: 12))),
          ],
        ])),

        // ═══ TAB 2: Dokumente ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _buildAntragDokumente(antragId: antrag['id']?.toString() ?? '', behoerdeType: behoerdeType),
        ])),

        // ═══ TAB 3: Verlauf ═══
        StatefulBuilder(builder: (vCtx, setVerlauf) => SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.history, size: 16, color: Colors.blue.shade700), const SizedBox(width: 6),
            Text('Verlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
            const Spacer(),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
              onPressed: () {
                final vDatumC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
                final vNotizC = TextEditingController();
                String vStatus = status;
                showDialog(context: vCtx, builder: (addCtx) => StatefulBuilder(builder: (addCtx, setAdd) => AlertDialog(
                  title: Row(children: [Icon(Icons.add_circle, size: 18, color: Colors.blue.shade600), const SizedBox(width: 8), const Text('Verlaufseintrag', style: TextStyle(fontSize: 14))]),
                  content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextFormField(controller: vDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: addCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) vDatumC.text = DateFormat('dd.MM.yyyy').format(p); }))),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: statusItems.any((i) => i.value == vStatus) ? vStatus : null,
                      decoration: InputDecoration(labelText: 'Status', prefixIcon: Icon(Icons.flag, size: 16, color: Colors.orange.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      items: statusItems, onChanged: (v) => setAdd(() => vStatus = v ?? vStatus)),
                    const SizedBox(height: 10),
                    TextFormField(controller: vNotizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz / Aktion', hintText: 'z.B. Kunde gefragt wann hätte Zeit für Termin?', hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                  ])),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(addCtx), child: const Text('Abbrechen')),
                    FilledButton(onPressed: () {
                      Navigator.pop(addCtx);
                      verlauf.add({'datum': vDatumC.text, 'status': vStatus, 'aktion': vNotizC.text.trim().isNotEmpty ? vNotizC.text.trim() : _antragStatusText(vStatus)});
                      antrag['verlauf'] = verlauf;
                      antrag['status'] = vStatus;
                      final updated = List<Map<String, dynamic>>.from(antraege);
                      updated[idx] = antrag;
                      onChanged(updated);
                      setVerlauf(() {});
                    }, child: const Text('Hinzufügen')),
                  ],
                )));
              },
            ),
          ]),
          const SizedBox(height: 10),
          if (verlauf.isEmpty)
            Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text('Kein Verlauf vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center))
          else
            ...verlauf.reversed.toList().map((v) => Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(width: 10, height: 10, margin: const EdgeInsets.only(top: 3, right: 10), decoration: BoxDecoration(color: _antragStatusColor(v['status'] ?? ''), shape: BoxShape.circle)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: _antragStatusColor(v['status'] ?? '').withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                      child: Text(_antragStatusText(v['status'] ?? ''), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: _antragStatusColor(v['status'] ?? '')))),
                  ]),
                  if ((v['aktion']?.toString() ?? '').isNotEmpty)
                    Text(v['aktion'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ])),
              ]),
            )),
        ]))),
      ])),
    )));
  }

  Widget _antragDetailRow(IconData icon, String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.orange.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
    ]));
  }

  Widget _buildAntraegeSection({
    required String behoerdeType,
    required List<Map<String, dynamic>> antraege,
    required List<DropdownMenuItem<String>> artItems,
    required List<DropdownMenuItem<String>> statusItems,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required BuildContext context,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header with add button
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              Icon(Icons.assignment, size: 20, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              Text('Antrage', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              const SizedBox(width: 8),
              if (antraege.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${antraege.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final result = await _showAntragDialog(
                    context: context,
                    behoerdeType: behoerdeType,
                    artItems: artItems,
                    statusItems: statusItems,
                  );
                  if (result != null) {
                    final updated = List<Map<String, dynamic>>.from(antraege);
                    updated.add(result);
                    onChanged(updated);
                  }
                },
                icon: Icon(Icons.add_circle, size: 18, color: Colors.orange.shade700),
                label: Text('Neuer Antrag', style: TextStyle(fontSize: 12, color: Colors.orange.shade700)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
              Expanded(child: Divider(color: Colors.orange.shade200, thickness: 1)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (antraege.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300, style: BorderStyle.solid),
            ),
            child: Column(
              children: [
                Icon(Icons.assignment_outlined, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Keine Antrage vorhanden', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ],
            ),
          )
        else
          ...antraege.asMap().entries.map((entry) {
            final idx = entry.key;
            final antrag = entry.value;
            final art = antrag['art'] ?? '';
            final status = antrag['status'] ?? '';
            final weg = antrag['einreichungsweg'] ?? '';
            final datum = antrag['datum'] ?? '';
            return InkWell(
              onTap: () => _showAntragDetailDialog(context: context, antrag: antrag, idx: idx, behoerdeType: behoerdeType, artItems: artItems, statusItems: statusItems, antraege: antraege, onChanged: onChanged),
              borderRadius: BorderRadius.circular(8),
              child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(children: [
                Icon(Icons.description, color: _antragStatusColor(status), size: 22),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(_antragArtText(art, behoerdeType), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: _antragStatusColor(status).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12), border: Border.all(color: _antragStatusColor(status).withValues(alpha: 0.4))),
                      child: Text(_antragStatusText(status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _antragStatusColor(status))),
                    ),
                  ]),
                  if (datum.isNotEmpty || weg.isNotEmpty)
                    Text([if (datum.isNotEmpty) datum, if (weg.isNotEmpty) weg == 'vor_ort' ? 'Vor Ort' : weg == 'online' ? 'Online' : weg == 'post' ? 'Per Post' : weg == 'telefonisch' ? 'Telefonisch' : weg].join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ]),
            ));
          }),
      ],
    );
  }

  // === ARBEITSUCHENDMELDUNG HELPERS ===

  // ========== MEDIZINISCHE BEGUTACHTUNG SECTION ==========

  List<Map<String, dynamic>> _getBegutachtungen(Map<String, dynamic> data) {
    if (data['begutachtungen'] is List && (data['begutachtungen'] as List).isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        (data['begutachtungen'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  }

  String _begutachtungPhaseLabel(String phase) {
    switch (phase) {
      case 'phase_1': return 'Phase 1: Antrag';
      case 'phase_2': return 'Phase 2: Hausarzt';
      case 'phase_3': return 'Phase 3: Einreichung';
      case 'phase_4': return 'Phase 4: Ergebnis';
      case 'abgeschlossen': return 'Abgeschlossen';
      default: return 'Phase 1: Antrag';
    }
  }

  Color _begutachtungPhaseColor(String phase) {
    switch (phase) {
      case 'phase_1': return Colors.orange;
      case 'phase_2': return Colors.blue;
      case 'phase_3': return Colors.indigo;
      case 'phase_4': return Colors.purple;
      case 'abgeschlossen': return Colors.green;
      default: return Colors.orange;
    }
  }

  int _begutachtungPhaseIndex(String phase) {
    switch (phase) {
      case 'phase_1': return 0;
      case 'phase_2': return 1;
      case 'phase_3': return 2;
      case 'phase_4': return 3;
      case 'abgeschlossen': return 4;
      default: return 0;
    }
  }

  Widget _buildBegutachtungPhaseIndicator(String phase) {
    final idx = _begutachtungPhaseIndex(phase);
    final phases = ['Antrag', 'Hausarzt', 'Einreichung', 'Ergebnis'];
    return Row(
      children: List.generate(phases.length, (i) {
        final done = i < idx || phase == 'abgeschlossen';
        final active = i == idx && phase != 'abgeschlossen';
        final color = done ? Colors.green : (active ? _begutachtungPhaseColor(phase) : Colors.grey.shade300);
        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  if (i > 0) Expanded(child: Container(height: 2, color: done ? Colors.green.shade300 : Colors.grey.shade200)),
                  Container(
                    width: 24, height: 24,
                    decoration: BoxDecoration(
                      color: done ? Colors.green : (active ? color : Colors.grey.shade200),
                      shape: BoxShape.circle,
                      border: Border.all(color: active ? color : Colors.transparent, width: 2),
                    ),
                    child: Center(child: done
                      ? const Icon(Icons.check, size: 14, color: Colors.white)
                      : Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: active ? Colors.white : Colors.grey.shade500))),
                  ),
                  if (i < phases.length - 1) Expanded(child: Container(height: 2, color: done ? Colors.green.shade300 : Colors.grey.shade200)),
                ],
              ),
              const SizedBox(height: 2),
              Text(phases[i], style: TextStyle(fontSize: 9, fontWeight: active || done ? FontWeight.bold : FontWeight.normal, color: done ? Colors.green.shade700 : (active ? color : Colors.grey.shade400))),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildBegutachtungSection({
    required String behoerdeType,
    required String behoerdeLabel,
    required List<Map<String, dynamic>> begutachtungen,
    required Map<String, dynamic> data,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required StateSetter setLocalState,
  }) {
    // 4-PHASEN Medizinische Begutachtung
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        _buildBehoerdeSectionHeader(Icons.medical_services, 'Medizinische Begutachtung (Ärztlicher Dienst)', Colors.red.shade700),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.red.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Info box
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade300),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.amber.shade800),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Der Ärztliche Dienst erstellt sozialmedizinische Stellungnahmen. Ablauf: Antrag \u2192 Hausarzt \u2192 Einreichung \u2192 Ergebnis',
                        style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => _showBegutachtungDialog(
                  behoerdeType: behoerdeType,
                  behoerdeLabel: behoerdeLabel,
                  begutachtungen: begutachtungen,
                  data: data,
                  onChanged: onChanged,
                  setLocalState: setLocalState,
                ),
                icon: Icon(Icons.add, size: 16, color: Colors.red.shade700),
                label: Text('Neue Begutachtung', style: TextStyle(fontSize: 12, color: Colors.red.shade700)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: Colors.red.shade300),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
              if (begutachtungen.isNotEmpty) ...[
                const SizedBox(height: 12),
                ...begutachtungen.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final b = entry.value;
                  final phase = b['phase']?.toString() ?? 'phase_1';
                  final antragDatum = b['antrag_datum']?.toString() ?? '';
                  final arbeitsvermittler = b['antrag_arbeitsvermittler']?.toString() ?? '';
                  final phaseColor = _begutachtungPhaseColor(phase);
                  final phaseLabel = _begutachtungPhaseLabel(phase);

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => _showBegutachtungViewDialog(
                        behoerdeType: behoerdeType,
                        behoerdeLabel: behoerdeLabel,
                        begutachtungen: begutachtungen,
                        data: data,
                        onChanged: onChanged,
                        setLocalState: setLocalState,
                        begutachtung: b,
                        begutachtungIndex: idx,
                      ),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.shade100),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.medical_services, size: 16, color: Colors.red.shade600),
                                const SizedBox(width: 6),
                                Expanded(child: Text('Begutachtung ${idx + 1}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade800))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: phaseColor.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(phaseLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: phaseColor)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            _buildBegutachtungPhaseIndicator(phase),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                if (antragDatum.isNotEmpty) ...[
                                  Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Text('Antrag: ${_formatDateDisplay(antragDatum)}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                  const SizedBox(width: 12),
                                ],
                                if (arbeitsvermittler.isNotEmpty) ...[
                                  Icon(Icons.person, size: 12, color: Colors.grey.shade500),
                                  const SizedBox(width: 4),
                                  Expanded(child: Text(arbeitsvermittler, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _showBegutachtungDialog({
    required String behoerdeType,
    required String behoerdeLabel,
    required List<Map<String, dynamic>> begutachtungen,
    required Map<String, dynamic> data,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required StateSetter setLocalState,
    Map<String, dynamic>? existing,
    int? editIndex,
  }) {
    // Phase 1: Antrag
    final antragDatumC = TextEditingController(text: existing?['antrag_datum']?.toString() ?? '');
    String antragBehoerde = existing?['antrag_behoerde']?.toString() ?? behoerdeLabel;
    final antragArbeitsvermittlerC = TextEditingController(text: existing?['antrag_arbeitsvermittler']?.toString() ?? '');
    bool formulareErhalten = existing?['formulare_erhalten'] == true;
    final formulareErhaltenDatumC = TextEditingController(text: existing?['formulare_erhalten_datum']?.toString() ?? '');
    bool umschlagErhalten = existing?['umschlag_erhalten'] == true;
    final antragGrundC = TextEditingController(text: existing?['antrag_grund']?.toString() ?? '');

    // Phase 2: Hausarzt-Termin
    final hausarztNameC = TextEditingController(text: existing?['hausarzt_name']?.toString() ?? '');
    final hausarztPraxisC = TextEditingController(text: existing?['hausarzt_praxis']?.toString() ?? '');
    final hausarztTerminDatumC = TextEditingController(text: existing?['hausarzt_termin_datum']?.toString() ?? '');
    final hausarztTerminUhrzeitC = TextEditingController(text: existing?['hausarzt_termin_uhrzeit']?.toString() ?? '');
    bool hausarztTerminAddToCalendar = existing?['hausarzt_termin_id'] != null || (editIndex == null);

    // Phase 3: Einreichung
    bool fragebogenAusgefuellt = existing?['fragebogen_ausgefuellt'] == true;
    final fragebogenDatumC = TextEditingController(text: existing?['fragebogen_datum']?.toString() ?? '');
    bool umschlagVersiegelt = existing?['umschlag_versiegelt'] == true;
    bool eingereicht = existing?['eingereicht'] == true;
    final eingereichtDatumC = TextEditingController(text: existing?['eingereicht_datum']?.toString() ?? '');
    String eingereichtWo = existing?['eingereicht_wo']?.toString() ?? '';

    // Phase 4: Ergebnis
    bool ergebnisErhalten = existing?['ergebnis_erhalten'] == true;
    final ergebnisDatumC = TextEditingController(text: existing?['ergebnis_datum']?.toString() ?? '');
    bool einladungErhalten = existing?['einladung_erhalten'] == true;
    final einladungDatumC = TextEditingController(text: existing?['einladung_datum']?.toString() ?? '');
    final einladungUhrzeitC = TextEditingController(text: existing?['einladung_uhrzeit']?.toString() ?? '');
    final ergebnisTextC = TextEditingController(text: existing?['ergebnis_text']?.toString() ?? '');
    final einschraenkungenC = TextEditingController(text: existing?['einschraenkungen']?.toString() ?? '');
    final arbeitsfaehigStundenC = TextEditingController(text: existing?['arbeitsfaehig_stunden']?.toString() ?? '');

    // General
    String phase = existing?['phase']?.toString() ?? 'phase_1';
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');

    // Auto-fill Arbeitsvermittler from Behörde data
    if (antragArbeitsvermittlerC.text.isEmpty) {
      antragArbeitsvermittlerC.text = data['arbeitsvermittler']?.toString() ?? '';
    }

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          return AlertDialog(
            title: Row(children: [
              Icon(Icons.medical_services, size: 18, color: Colors.red.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(editIndex != null ? 'Begutachtung bearbeiten' : 'Neue Begutachtung', style: const TextStyle(fontSize: 15))),
            ]),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Phase indicator
                    _buildBegutachtungPhaseIndicator(phase),
                    const SizedBox(height: 4),
                    // Phase selector
                    Center(
                      child: DropdownButton<String>(
                        value: phase,
                        underline: const SizedBox.shrink(),
                        isDense: true,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: _begutachtungPhaseColor(phase)),
                        items: [
                          DropdownMenuItem(value: 'phase_1', child: Text('Phase 1: Antrag', style: TextStyle(fontSize: 12, color: _begutachtungPhaseColor('phase_1')))),
                          DropdownMenuItem(value: 'phase_2', child: Text('Phase 2: Hausarzt', style: TextStyle(fontSize: 12, color: _begutachtungPhaseColor('phase_2')))),
                          DropdownMenuItem(value: 'phase_3', child: Text('Phase 3: Einreichung', style: TextStyle(fontSize: 12, color: _begutachtungPhaseColor('phase_3')))),
                          DropdownMenuItem(value: 'phase_4', child: Text('Phase 4: Ergebnis', style: TextStyle(fontSize: 12, color: _begutachtungPhaseColor('phase_4')))),
                          DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen', style: TextStyle(fontSize: 12, color: _begutachtungPhaseColor('abgeschlossen')))),
                        ],
                        onChanged: (v) => setDlgState(() => phase = v ?? 'phase_1'),
                      ),
                    ),
                    const Divider(height: 20),

                    // ============ PHASE 1: ANTRAG ============
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.description, size: 16, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            Text('Phase 1: Antrag / Aufforderung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                          ]),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: antragDatumC,
                            readOnly: true,
                            decoration: InputDecoration(
                              labelText: 'Antrag gestellt am *',
                              prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.orange.shade600),
                              suffixIcon: IconButton(
                                icon: const Icon(Icons.edit_calendar, size: 16),
                                onPressed: () async {
                                  final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(antragDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                  if (picked != null) antragDatumC.text = DateFormat('yyyy-MM-dd').format(picked);
                                },
                              ),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              helperText: 'Wann wurde die Begutachtung angefordert?',
                              helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Text('Angefordert von: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text('Jobcenter', style: TextStyle(fontSize: 11, color: antragBehoerde == 'Jobcenter' ? Colors.white : Colors.blue.shade700)),
                                selected: antragBehoerde == 'Jobcenter',
                                selectedColor: Colors.blue.shade600,
                                backgroundColor: Colors.blue.shade50,
                                side: BorderSide(color: antragBehoerde == 'Jobcenter' ? Colors.blue.shade600 : Colors.blue.shade200),
                                onSelected: (_) => setDlgState(() => antragBehoerde = 'Jobcenter'),
                              ),
                              const SizedBox(width: 8),
                              ChoiceChip(
                                label: Text('Arbeitsagentur', style: TextStyle(fontSize: 11, color: antragBehoerde == 'Arbeitsagentur' ? Colors.white : Colors.indigo.shade700)),
                                selected: antragBehoerde == 'Arbeitsagentur',
                                selectedColor: Colors.indigo.shade600,
                                backgroundColor: Colors.indigo.shade50,
                                side: BorderSide(color: antragBehoerde == 'Arbeitsagentur' ? Colors.indigo.shade600 : Colors.indigo.shade200),
                                onSelected: (_) => setDlgState(() => antragBehoerde = 'Arbeitsagentur'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: antragArbeitsvermittlerC,
                            decoration: InputDecoration(
                              labelText: 'Arbeitsvermittler/in (wer hat die Begutachtung angefordert?)',
                              prefixIcon: Icon(Icons.support_agent, size: 18, color: Colors.orange.shade600),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 10),
                          TextFormField(
                            controller: antragGrundC,
                            decoration: InputDecoration(
                              labelText: 'Grund der Begutachtung (optional)',
                              prefixIcon: const Icon(Icons.subject, size: 18),
                              hintText: 'z.B. Feststellung Arbeitsfähigkeit, Erwerbsminderung...',
                              hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Formulare erhalten
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange.shade100),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.mail, size: 16, color: Colors.orange.shade700),
                                    const SizedBox(width: 6),
                                    Expanded(child: Text('Formulare & Umschlag erhalten?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.orange.shade800))),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: SwitchListTile(
                                        title: const Text('Gesundheitsfragebogen erhalten', style: TextStyle(fontSize: 11)),
                                        value: formulareErhalten,
                                        onChanged: (v) => setDlgState(() => formulareErhalten = v),
                                        activeThumbColor: Colors.green,
                                        dense: true,
                                        contentPadding: EdgeInsets.zero,
                                      ),
                                    ),
                                  ],
                                ),
                                SwitchListTile(
                                  title: const Text('Rückumschlag erhalten', style: TextStyle(fontSize: 11)),
                                  value: umschlagErhalten,
                                  onChanged: (v) => setDlgState(() => umschlagErhalten = v),
                                  activeThumbColor: Colors.green,
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                                if (formulareErhalten || umschlagErhalten) ...[
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: formulareErhaltenDatumC,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Erhalten am',
                                      prefixIcon: Icon(Icons.mark_email_read, size: 18, color: Colors.green.shade600),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.edit_calendar, size: 16),
                                        onPressed: () async {
                                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(formulareErhaltenDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                          if (picked != null) setDlgState(() => formulareErhaltenDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                                        },
                                      ),
                                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ============ PHASE 2: HAUSARZT-TERMIN ============
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.local_hospital, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text('Phase 2: Termin beim Hausarzt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                          ]),
                          const SizedBox(height: 4),
                          Text('Der Hausarzt füllt den medizinischen Teil des Fragebogens aus.', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                          const SizedBox(height: 10),
                          // Hausarzt aus Datenbank auswählen
                          FutureBuilder<Map<String, dynamic>>(
                            future: widget.apiService.searchAerzte(fachrichtung: 'Allgemeinmedizin'),
                            builder: (ctx, snap) {
                              if (!snap.hasData || snap.data?['success'] != true) {
                                return const SizedBox.shrink();
                              }
                              final aerzteListe = List<Map<String, dynamic>>.from(snap.data!['aerzte'] ?? []);
                              if (aerzteListe.isEmpty) return const SizedBox.shrink();
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Hausarzt aus Datenbank auswählen', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                                  const SizedBox(height: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.blue.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.white,
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: null,
                                        isExpanded: true,
                                        hint: const Text('Arzt auswählen...', style: TextStyle(fontSize: 12)),
                                        items: aerzteListe.map((arzt) {
                                          final name = arzt['arzt_name']?.toString() ?? '';
                                          final praxis = arzt['praxis_name']?.toString() ?? '';
                                          final ort = arzt['plz_ort']?.toString() ?? '';
                                          return DropdownMenuItem<String>(
                                            value: arzt['id'].toString(),
                                            child: Text(
                                              '$name${praxis.isNotEmpty ? ' - $praxis' : ''}${ort.isNotEmpty ? ' ($ort)' : ''}',
                                              style: const TextStyle(fontSize: 11),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val == null) return;
                                          for (final arzt in aerzteListe) {
                                            if (arzt['id'].toString() == val) {
                                              setDlgState(() {
                                                hausarztNameC.text = arzt['arzt_name']?.toString() ?? '';
                                                final strasse = arzt['strasse']?.toString() ?? '';
                                                final plzOrt = arzt['plz_ort']?.toString() ?? '';
                                                final praxisName = arzt['praxis_name']?.toString() ?? '';
                                                hausarztPraxisC.text = '$praxisName${strasse.isNotEmpty ? ', $strasse' : ''}${plzOrt.isNotEmpty ? ', $plzOrt' : ''}';
                                              });
                                              break;
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text('oder manuell eingeben:', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                  const SizedBox(height: 8),
                                ],
                              );
                            },
                          ),
                          TextFormField(
                            controller: hausarztNameC,
                            decoration: InputDecoration(
                              labelText: 'Hausarzt (Name)',
                              prefixIcon: Icon(Icons.person, size: 18, color: Colors.blue.shade600),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: hausarztPraxisC,
                            decoration: InputDecoration(
                              labelText: 'Praxis / Adresse',
                              prefixIcon: Icon(Icons.local_hospital, size: 18, color: Colors.blue.shade400),
                              isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: hausarztTerminDatumC,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: 'Termin am',
                                    prefixIcon: const Icon(Icons.calendar_today, size: 18),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.edit_calendar, size: 16),
                                      onPressed: () async {
                                        final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(hausarztTerminDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                        if (picked != null) hausarztTerminDatumC.text = DateFormat('yyyy-MM-dd').format(picked);
                                      },
                                    ),
                                    isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: hausarztTerminUhrzeitC,
                                  readOnly: true,
                                  decoration: InputDecoration(
                                    labelText: 'Uhrzeit',
                                    prefixIcon: const Icon(Icons.access_time, size: 18),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.schedule, size: 16),
                                      onPressed: () async {
                                        final parts = hausarztTerminUhrzeitC.text.split(':');
                                        final initTime = parts.length == 2 ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0) : const TimeOfDay(hour: 9, minute: 0);
                                        final picked = await showTimePicker(context: dlgCtx, initialTime: initTime);
                                        if (picked != null) hausarztTerminUhrzeitC.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                      },
                                    ),
                                    isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          SwitchListTile(
                            title: const Text('In Terminverwaltung eintragen', style: TextStyle(fontSize: 12)),
                            subtitle: const Text('Hausarzttermin im Kalender', style: TextStyle(fontSize: 10)),
                            secondary: Icon(Icons.calendar_month, size: 18, color: Colors.green.shade600),
                            value: hausarztTerminAddToCalendar,
                            activeTrackColor: Colors.green.shade200,
                            activeThumbColor: Colors.green.shade700,
                            onChanged: (v) => setDlgState(() => hausarztTerminAddToCalendar = v),
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ============ PHASE 3: EINREICHUNG ============
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.indigo.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.send, size: 16, color: Colors.indigo.shade700),
                            const SizedBox(width: 6),
                            Text('Phase 3: Einreichung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                          ]),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            title: const Text('Gesundheitsfragebogen ausgefüllt', style: TextStyle(fontSize: 12)),
                            value: fragebogenAusgefuellt,
                            onChanged: (v) => setDlgState(() => fragebogenAusgefuellt = v),
                            activeThumbColor: Colors.green,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (fragebogenAusgefuellt)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: TextFormField(
                                controller: fragebogenDatumC,
                                readOnly: true,
                                decoration: InputDecoration(
                                  labelText: 'Ausgefüllt am',
                                  prefixIcon: Icon(Icons.edit_calendar, size: 18, color: Colors.green.shade600),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.edit_calendar, size: 16),
                                    onPressed: () async {
                                      final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(fragebogenDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                      if (picked != null) setDlgState(() => fragebogenDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                                    },
                                  ),
                                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                              ),
                            ),
                          SwitchListTile(
                            title: const Text('Umschlag versiegelt', style: TextStyle(fontSize: 12)),
                            subtitle: const Text('Umschlag vom Hausarzt zugemacht/versiegelt', style: TextStyle(fontSize: 10)),
                            value: umschlagVersiegelt,
                            onChanged: (v) => setDlgState(() => umschlagVersiegelt = v),
                            activeThumbColor: Colors.green,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          const Divider(height: 12),
                          SwitchListTile(
                            title: const Text('Bei Agentur für Arbeit eingereicht', style: TextStyle(fontSize: 12)),
                            value: eingereicht,
                            onChanged: (v) => setDlgState(() => eingereicht = v),
                            activeThumbColor: Colors.green,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (eingereicht) ...[
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: eingereichtDatumC,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Eingereicht am',
                                      prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.indigo.shade600),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.edit_calendar, size: 16),
                                        onPressed: () async {
                                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(eingereichtDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                          if (picked != null) setDlgState(() => eingereichtDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                                        },
                                      ),
                                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('Wie eingereicht?', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 6,
                                        children: [
                                          ChoiceChip(
                                            label: Text('Post', style: TextStyle(fontSize: 10, color: eingereichtWo == 'post' ? Colors.white : Colors.indigo.shade700)),
                                            selected: eingereichtWo == 'post',
                                            selectedColor: Colors.indigo.shade600,
                                            onSelected: (_) => setDlgState(() => eingereichtWo = 'post'),
                                          ),
                                          ChoiceChip(
                                            label: Text('Persönlich', style: TextStyle(fontSize: 10, color: eingereichtWo == 'persoenlich' ? Colors.white : Colors.indigo.shade700)),
                                            selected: eingereichtWo == 'persoenlich',
                                            selectedColor: Colors.indigo.shade600,
                                            onSelected: (_) => setDlgState(() => eingereichtWo = 'persoenlich'),
                                          ),
                                          ChoiceChip(
                                            label: Text('Hausbriefkasten', style: TextStyle(fontSize: 10, color: eingereichtWo == 'hausbriefkasten' ? Colors.white : Colors.indigo.shade700)),
                                            selected: eingereichtWo == 'hausbriefkasten',
                                            selectedColor: Colors.indigo.shade600,
                                            onSelected: (_) => setDlgState(() => eingereichtWo = 'hausbriefkasten'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // ============ PHASE 4: ERGEBNIS ============
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade200),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.assignment, size: 16, color: Colors.purple.shade700),
                            const SizedBox(width: 6),
                            Text('Phase 4: Ergebnis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                          ]),
                          const SizedBox(height: 4),
                          Text('99% der Fälle werden anhand der Dokumente entschieden. Eine Einladung zur persönlichen Untersuchung ist selten.', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                          const SizedBox(height: 10),
                          SwitchListTile(
                            title: const Text('Ergebnis / Stellungnahme erhalten', style: TextStyle(fontSize: 12)),
                            value: ergebnisErhalten,
                            onChanged: (v) => setDlgState(() => ergebnisErhalten = v),
                            activeThumbColor: Colors.green,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (ergebnisErhalten) ...[
                            TextFormField(
                              controller: ergebnisDatumC,
                              readOnly: true,
                              decoration: InputDecoration(
                                labelText: 'Ergebnis erhalten am',
                                prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.purple.shade600),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.edit_calendar, size: 16),
                                  onPressed: () async {
                                    final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(ergebnisDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                    if (picked != null) setDlgState(() => ergebnisDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                                  },
                                ),
                                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: ergebnisTextC,
                              maxLines: 3,
                              decoration: InputDecoration(
                                labelText: 'Sozialmedizinische Stellungnahme',
                                hintText: 'z.B. Vollzeitig leistungsfähig mit Einschränkungen...',
                                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: einschraenkungenC,
                              maxLines: 2,
                              decoration: InputDecoration(
                                labelText: 'Festgestellte Einschränkungen',
                                hintText: 'z.B. Kein schweres Heben, keine stehende Tätigkeit...',
                                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextFormField(
                              controller: arbeitsfaehigStundenC,
                              decoration: InputDecoration(
                                labelText: 'Arbeitsfähig (Stunden/Tag)',
                                hintText: 'z.B. 6, 3-unter 6, unter 3',
                                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                prefixIcon: Icon(Icons.timer, size: 18, color: Colors.purple.shade400),
                                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          // Einladung (selten)
                          SwitchListTile(
                            title: const Text('Einladung zur persönlichen Vorstellung', style: TextStyle(fontSize: 12)),
                            subtitle: const Text('Selten \u2013 nur wenn Dokumente nicht ausreichen', style: TextStyle(fontSize: 10)),
                            value: einladungErhalten,
                            onChanged: (v) => setDlgState(() => einladungErhalten = v),
                            activeThumbColor: Colors.orange,
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                          if (einladungErhalten) ...[
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: einladungDatumC,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Einladung am',
                                      prefixIcon: Icon(Icons.calendar_today, size: 18, color: Colors.orange.shade600),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.edit_calendar, size: 16),
                                        onPressed: () async {
                                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(einladungDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                                          if (picked != null) setDlgState(() => einladungDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                                        },
                                      ),
                                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    controller: einladungUhrzeitC,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      labelText: 'Uhrzeit',
                                      prefixIcon: const Icon(Icons.access_time, size: 18),
                                      suffixIcon: IconButton(
                                        icon: const Icon(Icons.schedule, size: 16),
                                        onPressed: () async {
                                          final parts = einladungUhrzeitC.text.split(':');
                                          final initTime = parts.length == 2 ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0) : const TimeOfDay(hour: 9, minute: 0);
                                          final picked = await showTimePicker(context: dlgCtx, initialTime: initTime);
                                          if (picked != null) einladungUhrzeitC.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                        },
                                      ),
                                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    // === NOTIZ ===
                    TextFormField(
                      controller: notizC,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: 'Notiz (optional)',
                        prefixIcon: const Icon(Icons.note, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Abbrechen')),
              FilledButton.icon(
                icon: const Icon(Icons.save, size: 16),
                label: Text(editIndex != null ? 'Speichern' : 'Begutachtung erstellen'),
                style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                onPressed: () async {
                  final entry = <String, dynamic>{
                    'phase': phase,
                    // Phase 1
                    'antrag_datum': antragDatumC.text.trim(),
                    'antrag_behoerde': antragBehoerde,
                    'antrag_arbeitsvermittler': antragArbeitsvermittlerC.text.trim(),
                    'antrag_grund': antragGrundC.text.trim(),
                    'formulare_erhalten': formulareErhalten,
                    'formulare_erhalten_datum': formulareErhaltenDatumC.text.trim(),
                    'umschlag_erhalten': umschlagErhalten,
                    // Phase 2
                    'hausarzt_name': hausarztNameC.text.trim(),
                    'hausarzt_praxis': hausarztPraxisC.text.trim(),
                    'hausarzt_termin_datum': hausarztTerminDatumC.text.trim(),
                    'hausarzt_termin_uhrzeit': hausarztTerminUhrzeitC.text.trim(),
                    // Phase 3
                    'fragebogen_ausgefuellt': fragebogenAusgefuellt,
                    'fragebogen_datum': fragebogenDatumC.text.trim(),
                    'umschlag_versiegelt': umschlagVersiegelt,
                    'eingereicht': eingereicht,
                    'eingereicht_datum': eingereichtDatumC.text.trim(),
                    'eingereicht_wo': eingereichtWo,
                    // Phase 4
                    'ergebnis_erhalten': ergebnisErhalten,
                    'ergebnis_datum': ergebnisDatumC.text.trim(),
                    'einladung_erhalten': einladungErhalten,
                    'einladung_datum': einladungDatumC.text.trim(),
                    'einladung_uhrzeit': einladungUhrzeitC.text.trim(),
                    'ergebnis_text': ergebnisTextC.text.trim(),
                    'einschraenkungen': einschraenkungenC.text.trim(),
                    'arbeitsfaehig_stunden': arbeitsfaehigStundenC.text.trim(),
                    // General
                    'notiz': notizC.text.trim(),
                    'behoerde': behoerdeLabel,
                  };

                  // Preserve termin_id if editing
                  if (existing?['hausarzt_termin_id'] != null) entry['hausarzt_termin_id'] = existing!['hausarzt_termin_id'];

                  // Create Hausarzt termin in Terminverwaltung
                  if (hausarztTerminAddToCalendar && hausarztTerminDatumC.text.isNotEmpty) {
                    try {
                      final timeParts = hausarztTerminUhrzeitC.text.split(':');
                      final h = timeParts.length >= 2 ? (int.tryParse(timeParts[0]) ?? 9) : 9;
                      final m = timeParts.length >= 2 ? (int.tryParse(timeParts[1]) ?? 0) : 0;
                      final terminDate = DateTime.parse(hausarztTerminDatumC.text).add(Duration(hours: h, minutes: m));
                      final title = 'Hausarzt \u2013 Med. Begutachtung${hausarztNameC.text.isNotEmpty ? ' (${hausarztNameC.text.trim()})' : ''}';
                      final desc = [
                        'Medizinische Begutachtung \u2013 Hausarzttermin',
                        if (hausarztPraxisC.text.trim().isNotEmpty) 'Praxis: ${hausarztPraxisC.text.trim()}',
                        if (antragGrundC.text.trim().isNotEmpty) 'Grund: ${antragGrundC.text.trim()}',
                        'Mitglied: ${widget.user.name} (${widget.user.mitgliedernummer})',
                      ].join('\n');

                      final result = await widget.terminService.createTermin(
                        title: title,
                        category: 'sonstiges',
                        description: desc,
                        terminDate: terminDate,
                        durationMinutes: 30,
                        location: hausarztPraxisC.text.trim(),
                        participantIds: [widget.user.id],
                      );
                      if (result.containsKey('termin')) {
                        entry['hausarzt_termin_id'] = result['termin']['id'];
                      }
                    } catch (e) {
                      debugPrint('Begutachtung hausarzt termin error: $e');
                    }
                  }

                  final updated = List<Map<String, dynamic>>.from(begutachtungen);
                  if (editIndex != null && editIndex < updated.length) {
                    updated[editIndex] = entry;
                  } else {
                    updated.add(entry);
                  }

                  if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                  onChanged(updated);
                },
              ),
            ],
          );
        },
      ),
    );
  }

  void _showBegutachtungViewDialog({
    required String behoerdeType,
    required String behoerdeLabel,
    required List<Map<String, dynamic>> begutachtungen,
    required Map<String, dynamic> data,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required StateSetter setLocalState,
    required Map<String, dynamic> begutachtung,
    required int begutachtungIndex,
  }) {
    showDialog(
      context: context,
      builder: (dlgCtx) {
        final b = begutachtung;
        final phase = b['phase']?.toString() ?? 'phase_1';
        final phaseColor = _begutachtungPhaseColor(phase);
        final phaseLabel = _begutachtungPhaseLabel(phase);

        return AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
          title: Row(children: [
            Icon(Icons.medical_services, size: 20, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('Begutachtung \u2013 $behoerdeLabel', style: const TextStyle(fontSize: 15))),
            IconButton(
              icon: Icon(Icons.edit, size: 18, color: Colors.blue.shade600),
              tooltip: 'Bearbeiten',
              onPressed: () {
                Navigator.pop(dlgCtx);
                _showBegutachtungDialog(
                  behoerdeType: behoerdeType,
                  behoerdeLabel: behoerdeLabel,
                  begutachtungen: begutachtungen,
                  data: data,
                  onChanged: onChanged,
                  setLocalState: setLocalState,
                  existing: b,
                  editIndex: begutachtungIndex,
                );
              },
            ),
            IconButton(
              icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
              tooltip: 'Löschen',
              onPressed: () {
                Navigator.pop(dlgCtx);
                final updated = List<Map<String, dynamic>>.from(begutachtungen)..removeAt(begutachtungIndex);
                onChanged(updated);
              },
            ),
            IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx)),
          ]),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Phase indicator
                  _buildBegutachtungPhaseIndicator(phase),
                  const SizedBox(height: 4),
                  Center(child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: phaseColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
                    child: Text(phaseLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: phaseColor)),
                  )),
                  const SizedBox(height: 12),

                  // === PHASE 1 ===
                  _buildViewPhaseHeader('Phase 1: Antrag', Icons.description, Colors.orange),
                  _terminInfoRow(Icons.calendar_today, 'Antrag am', (b['antrag_datum']?.toString() ?? '').isNotEmpty ? _formatDateDisplay(b['antrag_datum'].toString()) : '\u2013', Colors.orange),
                  _terminInfoRow(Icons.business, 'Angefordert von', b['antrag_behoerde']?.toString() ?? '\u2013', Colors.orange),
                  _terminInfoRow(Icons.support_agent, 'Arbeitsvermittler', (b['antrag_arbeitsvermittler']?.toString() ?? '').isNotEmpty ? b['antrag_arbeitsvermittler'].toString() : '\u2013', Colors.orange),
                  if ((b['antrag_grund']?.toString() ?? '').isNotEmpty)
                    _terminInfoRow(Icons.subject, 'Grund', b['antrag_grund'].toString(), Colors.orange),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Icon(b['formulare_erhalten'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: b['formulare_erhalten'] == true ? Colors.green : Colors.red),
                      const SizedBox(width: 6),
                      Text('Formulare erhalten', style: TextStyle(fontSize: 12, color: b['formulare_erhalten'] == true ? Colors.green.shade700 : Colors.red.shade700)),
                      const SizedBox(width: 12),
                      Icon(b['umschlag_erhalten'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: b['umschlag_erhalten'] == true ? Colors.green : Colors.red),
                      const SizedBox(width: 6),
                      Text('Rückumschlag erhalten', style: TextStyle(fontSize: 12, color: b['umschlag_erhalten'] == true ? Colors.green.shade700 : Colors.red.shade700)),
                    ]),
                  ),
                  if ((b['formulare_erhalten_datum']?.toString() ?? '').isNotEmpty)
                    _terminInfoRow(Icons.mark_email_read, 'Erhalten am', _formatDateDisplay(b['formulare_erhalten_datum'].toString()), Colors.green),
                  const Divider(height: 16),

                  // === PHASE 2 ===
                  _buildViewPhaseHeader('Phase 2: Hausarzt', Icons.local_hospital, Colors.blue),
                  _terminInfoRow(Icons.person, 'Hausarzt', (b['hausarzt_name']?.toString() ?? '').isNotEmpty ? b['hausarzt_name'].toString() : '\u2013', Colors.blue),
                  if ((b['hausarzt_praxis']?.toString() ?? '').isNotEmpty)
                    _terminInfoRow(Icons.local_hospital, 'Praxis', b['hausarzt_praxis'].toString(), Colors.blue),
                  _terminInfoRow(Icons.calendar_today, 'Termin am', (b['hausarzt_termin_datum']?.toString() ?? '').isNotEmpty ? '${_formatDateDisplay(b['hausarzt_termin_datum'].toString())}${(b['hausarzt_termin_uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${b['hausarzt_termin_uhrzeit']} Uhr' : ''}' : '\u2013', Colors.blue),
                  if (b['hausarzt_termin_id'] != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.calendar_month, size: 13, color: Colors.green.shade700),
                          const SizedBox(width: 4),
                          Text('Im Kalender', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ),
                  const Divider(height: 16),

                  // === PHASE 3 ===
                  _buildViewPhaseHeader('Phase 3: Einreichung', Icons.send, Colors.indigo),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Column(
                      children: [
                        Row(children: [
                          Icon(b['fragebogen_ausgefuellt'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: b['fragebogen_ausgefuellt'] == true ? Colors.green : Colors.red),
                          const SizedBox(width: 6),
                          Text('Fragebogen ausgefüllt', style: TextStyle(fontSize: 12, color: b['fragebogen_ausgefuellt'] == true ? Colors.green.shade700 : Colors.red.shade700)),
                          if (b['fragebogen_ausgefuellt'] == true && (b['fragebogen_datum']?.toString() ?? '').isNotEmpty)
                            Text(' (${_formatDateDisplay(b['fragebogen_datum'].toString())})', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(b['umschlag_versiegelt'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: b['umschlag_versiegelt'] == true ? Colors.green : Colors.red),
                          const SizedBox(width: 6),
                          Text('Umschlag versiegelt', style: TextStyle(fontSize: 12, color: b['umschlag_versiegelt'] == true ? Colors.green.shade700 : Colors.red.shade700)),
                        ]),
                        const SizedBox(height: 4),
                        Row(children: [
                          Icon(b['eingereicht'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: b['eingereicht'] == true ? Colors.green : Colors.red),
                          const SizedBox(width: 6),
                          Text('Eingereicht', style: TextStyle(fontSize: 12, color: b['eingereicht'] == true ? Colors.green.shade700 : Colors.red.shade700)),
                          if (b['eingereicht'] == true && (b['eingereicht_datum']?.toString() ?? '').isNotEmpty)
                            Text(' am ${_formatDateDisplay(b['eingereicht_datum'].toString())}', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                          if (b['eingereicht'] == true && (b['eingereicht_wo']?.toString() ?? '').isNotEmpty)
                            Text(' (${b['eingereicht_wo'] == 'post' ? 'per Post' : b['eingereicht_wo'] == 'persoenlich' ? 'persönlich' : 'Hausbriefkasten'})', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                        ]),
                      ],
                    ),
                  ),
                  const Divider(height: 16),

                  // === PHASE 4 ===
                  _buildViewPhaseHeader('Phase 4: Ergebnis', Icons.assignment, Colors.purple),
                  if (b['ergebnis_erhalten'] == true) ...[
                    _terminInfoRow(Icons.calendar_today, 'Ergebnis am', (b['ergebnis_datum']?.toString() ?? '').isNotEmpty ? _formatDateDisplay(b['ergebnis_datum'].toString()) : '\u2013', Colors.purple),
                    if ((b['ergebnis_text']?.toString() ?? '').isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Stellungnahme:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                              const SizedBox(height: 2),
                              Text(b['ergebnis_text'].toString(), style: const TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      ),
                    if ((b['einschraenkungen']?.toString() ?? '').isNotEmpty)
                      _terminInfoRow(Icons.warning_amber, 'Einschränkungen', b['einschraenkungen'].toString(), Colors.orange),
                    if ((b['arbeitsfaehig_stunden']?.toString() ?? '').isNotEmpty)
                      _terminInfoRow(Icons.timer, 'Arbeitsfähig', '${b['arbeitsfaehig_stunden']} Std./Tag', Colors.purple),
                  ] else
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text('Ergebnis steht noch aus...', style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: Colors.grey.shade500)),
                    ),

                  if (b['einladung_erhalten'] == true) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.orange.shade200)),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Icon(Icons.mail, size: 14, color: Colors.orange.shade700),
                            const SizedBox(width: 6),
                            Text('Einladung zur persönlichen Vorstellung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                          ]),
                          if ((b['einladung_datum']?.toString() ?? '').isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text('Am ${_formatDateDisplay(b['einladung_datum'].toString())}${(b['einladung_uhrzeit']?.toString() ?? '').isNotEmpty ? ' um ${b['einladung_uhrzeit']} Uhr' : ''}', style: TextStyle(fontSize: 12, color: Colors.orange.shade800)),
                            ),
                        ],
                      ),
                    ),
                  ],

                  if ((b['notiz']?.toString() ?? '').isNotEmpty) ...[
                    const SizedBox(height: 8),
                    _terminInfoRow(Icons.note, 'Notiz', b['notiz'].toString(), Colors.grey),
                  ],
                ],
              ),
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Schließen')),
          ],
        );
      },
    );
  }

  Widget _buildViewPhaseHeader(String title, IconData icon, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 15, color: color.shade700),
        const SizedBox(width: 6),
        Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade700)),
      ]),
    );
  }

  // ========== BEHÖRDE TERMINE SECTION ==========

  Widget _buildBehoerdeTermineSection({
    required String behoerdeType,
    required String behoerdeLabel,
    required List<Map<String, dynamic>> termine,
    required Map<String, dynamic> data,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required StateSetter setLocalState,
  }) {
    // Auto-update ort for existing termine from Dienststelle
    final dienststelle = data['dienststelle']?.toString() ?? '';
    if (dienststelle.isNotEmpty && termine.isNotEmpty) {
      final sel = _findSelectedStandort(behoerdeType, dienststelle);
      final correctOrt = sel != null
          ? '${sel['name']}, ${sel['strasse']}, ${sel['plz_ort']}'
          : dienststelle;
      bool needsSave = false;
      for (final t in termine) {
        final currentOrt = t['ort']?.toString() ?? '';
        if (currentOrt != correctOrt && (currentOrt.isEmpty || !currentOrt.contains(sel?['strasse']?.toString() ?? '___'))) {
          t['ort'] = correctOrt;
          needsSave = true;
        }
      }
      if (needsSave) {
        // Save async, don't block build
        Future.microtask(() {
          _autoSaveField(behoerdeType, 'termine', termine);
          setLocalState(() {});
        });
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildBehoerdeSectionHeader(Icons.event, 'Termine / Vorladungen', Colors.deepPurple),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: Text('${termine.length} Termin${termine.length == 1 ? '' : 'e'} erfasst', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
            FilledButton.icon(
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Neuer Termin', style: TextStyle(fontSize: 12)),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.deepPurple.shade600,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                minimumSize: Size.zero,
              ),
              onPressed: () => _showBehoerdeTerminDialog(
                behoerdeType: behoerdeType,
                behoerdeLabel: behoerdeLabel,
                termine: termine,
                data: data,
                onChanged: onChanged,
                setLocalState: setLocalState,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (termine.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Column(children: [
              Icon(Icons.event_busy, size: 32, color: Colors.grey.shade400),
              const SizedBox(height: 6),
              Text('Keine Termine vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]),
          )
        else
          ...termine.asMap().entries.map((entry) {
            final idx = entry.key;
            final t = entry.value;
            final datum = t['datum']?.toString() ?? '';
            final uhrzeit = t['uhrzeit']?.toString() ?? '';
            final grund = t['grund']?.toString() ?? '';
            final ort = t['ort']?.toString() ?? '';
            final terminId = t['termin_id'];
            final tArt = t['terminart']?.toString() ?? 'selbst';
            final isEinladung = tArt == 'einladung';
            final isPast = datum.isNotEmpty && (DateTime.tryParse(datum)?.isBefore(DateTime.now()) ?? false);
            return InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showBehoerdeTerminViewDialog(
                behoerdeType: behoerdeType,
                behoerdeLabel: behoerdeLabel,
                termine: termine,
                data: data,
                onChanged: onChanged,
                setLocalState: setLocalState,
                termin: t,
                terminIndex: idx,
              ),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isPast ? Colors.grey.shade50 : (isEinladung ? Colors.orange.shade50 : Colors.deepPurple.shade50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isPast ? Colors.grey.shade300 : (isEinladung ? Colors.orange.shade200 : Colors.deepPurple.shade200)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(isEinladung ? Icons.mail : Icons.event, size: 16, color: isPast ? Colors.grey : (isEinladung ? Colors.orange.shade700 : Colors.deepPurple.shade700)),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                            color: isEinladung ? Colors.orange.shade100 : Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            isEinladung ? 'Einladung' : 'Selbst',
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isEinladung ? Colors.orange.shade800 : Colors.blue.shade800),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            datum.isNotEmpty ? '${_formatDateDisplay(datum)}${uhrzeit.isNotEmpty ? ' um $uhrzeit Uhr' : ''}' : 'Kein Datum',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade600 : Colors.deepPurple.shade800),
                          ),
                        ),
                        if (terminId != null)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)),
                            child: Text('Im Kalender', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                          ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                      ],
                    ),
                    if (grund.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Row(children: [
                          Icon(Icons.subject, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(child: Text(grund, style: const TextStyle(fontSize: 11))),
                        ]),
                      ),
                    if (ort.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Row(children: [
                          Icon(Icons.place, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Expanded(child: Text(ort, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                        ]),
                      ),
                  ],
                ),
              ),
            );
          }),
        const SizedBox(height: 16),
      ],
    );
  }

  String _formatDateDisplay(String dateStr) {
    final d = DateTime.tryParse(dateStr);
    if (d == null) return dateStr;
    return DateFormat('dd.MM.yyyy').format(d);
  }

  void _showBehoerdeTerminViewDialog({
    required String behoerdeType,
    required String behoerdeLabel,
    required List<Map<String, dynamic>> termine,
    required Map<String, dynamic> data,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required StateSetter setLocalState,
    required Map<String, dynamic> termin,
    required int terminIndex,
  }) {
    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          final t = termin;
          final tArt = t['terminart']?.toString() ?? 'selbst';
          final isEinladung = tArt == 'einladung';
          final datum = t['datum']?.toString() ?? '';
          final uhrzeit = t['uhrzeit']?.toString() ?? '';
          final ansprechpartner = t['ansprechpartner']?.toString() ?? '';
          final grund = t['grund']?.toString() ?? '';
          final ort = t['ort']?.toString() ?? '';
          final notiz = t['notiz']?.toString() ?? '';
          final einladungDatum = t['einladung_datum']?.toString() ?? '';
          final briefErhalten = t['brief_erhalten']?.toString() ?? '';
          final terminId = t['termin_id'];
          final verlauf = (t['verlauf'] is List) ? List<Map<String, dynamic>>.from((t['verlauf'] as List).map((e) => Map<String, dynamic>.from(e as Map))) : <Map<String, dynamic>>[];
          int tabIndex = t['_viewTab'] as int? ?? 0;

          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(20, 16, 8, 0),
            title: Row(children: [
              Icon(isEinladung ? Icons.mail : Icons.event_note, size: 20, color: isEinladung ? Colors.orange.shade700 : Colors.deepPurple.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text('${isEinladung ? 'Einladung' : 'Termin'} \u2013 $behoerdeLabel', style: const TextStyle(fontSize: 15))),
              // Edit button
              IconButton(
                icon: Icon(Icons.edit, size: 18, color: Colors.blue.shade600),
                tooltip: 'Bearbeiten',
                onPressed: () {
                  Navigator.pop(dlgCtx);
                  _showBehoerdeTerminDialog(
                    behoerdeType: behoerdeType,
                    behoerdeLabel: behoerdeLabel,
                    termine: termine,
                    data: data,
                    onChanged: onChanged,
                    setLocalState: setLocalState,
                    existing: t,
                    editIndex: terminIndex,
                  );
                },
              ),
              // Delete button
              IconButton(
                icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                tooltip: 'Loschen',
                onPressed: () {
                  Navigator.pop(dlgCtx);
                  final updated = List<Map<String, dynamic>>.from(termine)..removeAt(terminIndex);
                  onChanged(updated);
                },
              ),
              IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx)),
            ]),
            content: SizedBox(
              width: 460,
              height: 420,
              child: Column(
                children: [
                  // Tab bar
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                            onTap: () => setDlgState(() { t['_viewTab'] = 0; }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: tabIndex == 0 ? Colors.deepPurple.shade600 : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.info_outline, size: 15, color: tabIndex == 0 ? Colors.white : Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text('Details', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tabIndex == 0 ? Colors.white : Colors.grey.shade600)),
                              ]),
                            ),
                          ),
                        ),
                        Expanded(
                          child: InkWell(
                            borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                            onTap: () => setDlgState(() { t['_viewTab'] = 1; }),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              decoration: BoxDecoration(
                                color: tabIndex == 1 ? Colors.deepPurple.shade600 : Colors.transparent,
                                borderRadius: const BorderRadius.horizontal(right: Radius.circular(8)),
                              ),
                              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.history, size: 15, color: tabIndex == 1 ? Colors.white : Colors.grey.shade600),
                                const SizedBox(width: 6),
                                Text('Verlauf (${verlauf.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: tabIndex == 1 ? Colors.white : Colors.grey.shade600)),
                              ]),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Tab content
                  Expanded(
                    child: tabIndex == 0
                      ? _buildTerminDetailsTab(tArt, datum, uhrzeit, ansprechpartner, grund, ort, notiz, einladungDatum, briefErhalten, terminId)
                      : _buildTerminVerlaufTab(verlauf, termin, termine, terminIndex, onChanged, setDlgState),
                  ),
                ],
              ),
            ),
            actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Schliessen')),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTerminDetailsTab(String terminart, String datum, String uhrzeit, String ansprechpartner, String grund, String ort, String notiz, String einladungDatum, String briefErhalten, dynamic terminId) {
    final isEinladung = terminart == 'einladung';
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Terminart badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isEinladung ? Colors.orange.shade100 : Colors.blue.shade100,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(isEinladung ? Icons.mail : Icons.event, size: 14, color: isEinladung ? Colors.orange.shade800 : Colors.blue.shade800),
              const SizedBox(width: 6),
              Text(isEinladung ? 'Einladung / Vorladung' : 'Selbst vereinbart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEinladung ? Colors.orange.shade800 : Colors.blue.shade800)),
            ]),
          ),
          const SizedBox(height: 12),
          // Postal tracking section (only for Einladung)
          if (isEinladung && (einladungDatum.isNotEmpty || briefErhalten.isNotEmpty)) ...[
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.local_post_office, size: 15, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Text('Postverkehr', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                  ]),
                  const SizedBox(height: 8),
                  if (einladungDatum.isNotEmpty)
                    _terminInfoRow(Icons.mail_outline, 'Einladung erstellt', _formatDateDisplay(einladungDatum), Colors.blue),
                  if (briefErhalten.isNotEmpty)
                    _terminInfoRow(Icons.mark_email_read, 'Brief erhalten', _formatDateDisplay(briefErhalten), Colors.green),
                  if (einladungDatum.isNotEmpty && briefErhalten.isNotEmpty) ...[
                    () {
                      final e = DateTime.tryParse(einladungDatum);
                      final b = DateTime.tryParse(briefErhalten);
                      if (e != null && b != null) {
                        final days = b.difference(e).inDays;
                        final color = days <= 2 ? Colors.green : (days <= 5 ? Colors.orange : Colors.red);
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Row(children: [
                            Icon(Icons.local_shipping, size: 14, color: color),
                            const SizedBox(width: 8),
                            Text('Postlaufzeit: $days Tag${days == 1 ? '' : 'e'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                          ]),
                        );
                      }
                      return const SizedBox.shrink();
                    }(),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          // Main termin details
          _terminInfoRow(Icons.calendar_today, 'Datum', datum.isNotEmpty ? _formatDateDisplay(datum) : '\u2013', Colors.deepPurple),
          _terminInfoRow(Icons.access_time, 'Uhrzeit', uhrzeit.isNotEmpty ? '$uhrzeit Uhr' : '\u2013', Colors.deepPurple),
          _terminInfoRow(Icons.person, 'Ansprechpartner', ansprechpartner.isNotEmpty ? ansprechpartner : '\u2013', Colors.deepPurple),
          _terminInfoRow(Icons.subject, 'Grund', grund.isNotEmpty ? grund : '\u2013', Colors.deepPurple),
          _terminInfoRow(Icons.place, 'Ort / Adresse', ort.isNotEmpty ? ort : '\u2013', Colors.deepPurple),
          if (notiz.isNotEmpty)
            _terminInfoRow(Icons.note, 'Notiz', notiz, Colors.grey),
          const SizedBox(height: 8),
          if (terminId != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.calendar_month, size: 14, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text('Im Kalender eingetragen', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _terminInfoRow(IconData icon, String label, String value, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color.shade600),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          ),
          Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
        ],
      ),
    );
  }

  Widget _buildTerminVerlaufTab(List<Map<String, dynamic>> verlauf, Map<String, dynamic> termin, List<Map<String, dynamic>> termine, int terminIndex, void Function(List<Map<String, dynamic>>) onChanged, StateSetter setDlgState) {
    final statusOptions = [
      {'value': 'bestaetigt', 'label': 'Bestatigt', 'icon': Icons.check_circle, 'color': Colors.green},
      {'value': 'verschoben', 'label': 'Verschoben', 'icon': Icons.schedule, 'color': Colors.orange},
      {'value': 'abgesagt', 'label': 'Abgesagt', 'icon': Icons.cancel, 'color': Colors.red},
      {'value': 'wahrgenommen', 'label': 'Wahrgenommen', 'icon': Icons.done_all, 'color': Colors.blue},
      {'value': 'nicht_erschienen', 'label': 'Nicht erschienen', 'icon': Icons.person_off, 'color': Colors.red},
      {'value': 'notiz', 'label': 'Notiz', 'icon': Icons.note_add, 'color': Colors.grey},
    ];
    final notizC = TextEditingController();
    String selectedStatus = 'bestaetigt';

    return StatefulBuilder(
      builder: (ctx, setVState) => Column(
        children: [
          // Add new entry
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Neuer Eintrag', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: statusOptions.map((opt) {
                    final sel = selectedStatus == opt['value'];
                    final c = opt['color'] as MaterialColor;
                    return ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(opt['icon'] as IconData, size: 13, color: sel ? Colors.white : c.shade700),
                        const SizedBox(width: 4),
                        Text(opt['label'] as String, style: TextStyle(fontSize: 10, color: sel ? Colors.white : c.shade700)),
                      ]),
                      selected: sel,
                      selectedColor: c.shade600,
                      backgroundColor: c.shade50,
                      side: BorderSide(color: sel ? c.shade600 : c.shade200),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      onSelected: (_) => setVState(() => selectedStatus = opt['value'] as String),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: notizC,
                        decoration: InputDecoration(
                          hintText: 'Bemerkung (optional)',
                          hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.add, size: 14),
                      label: const Text('Hinzufugen', style: TextStyle(fontSize: 11)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.deepPurple.shade600,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      onPressed: () {
                        final entry = <String, dynamic>{
                          'status': selectedStatus,
                          'notiz': notizC.text.trim(),
                          'datum': DateFormat('yyyy-MM-dd').format(DateTime.now()),
                          'zeit': DateFormat('HH:mm').format(DateTime.now()),
                        };
                        final updatedVerlauf = List<Map<String, dynamic>>.from(verlauf)..insert(0, entry);
                        termin['verlauf'] = updatedVerlauf;
                        final updatedTermine = List<Map<String, dynamic>>.from(termine);
                        updatedTermine[terminIndex] = Map<String, dynamic>.from(termin);
                        onChanged(updatedTermine);
                        notizC.clear();
                        setDlgState(() {});
                        setVState(() {});
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Verlauf list
          Expanded(
            child: verlauf.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history, size: 36, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Noch keine Eintrage', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ]))
              : ListView.builder(
                  itemCount: verlauf.length,
                  itemBuilder: (ctx, i) {
                    final v = verlauf[i];
                    final status = v['status']?.toString() ?? 'notiz';
                    final vNotiz = v['notiz']?.toString() ?? '';
                    final vDatum = v['datum']?.toString() ?? '';
                    final vZeit = v['zeit']?.toString() ?? '';
                    final opt = statusOptions.firstWhere((o) => o['value'] == status, orElse: () => statusOptions.last);
                    final c = opt['color'] as MaterialColor;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: c.shade50,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: c.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(opt['icon'] as IconData, size: 16, color: c.shade700),
                          const SizedBox(width: 8),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Text(opt['label'] as String, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: c.shade700)),
                                const Spacer(),
                                Text('${vDatum.isNotEmpty ? _formatDateDisplay(vDatum) : ''} ${vZeit.isNotEmpty ? '$vZeit Uhr' : ''}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                              ]),
                              if (vNotiz.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(vNotiz, style: const TextStyle(fontSize: 11)),
                              ],
                            ],
                          )),
                          InkWell(
                            onTap: () {
                              final updatedVerlauf = List<Map<String, dynamic>>.from(verlauf)..removeAt(i);
                              termin['verlauf'] = updatedVerlauf;
                              final updatedTermine = List<Map<String, dynamic>>.from(termine);
                              updatedTermine[terminIndex] = Map<String, dynamic>.from(termin);
                              onChanged(updatedTermine);
                              setDlgState(() {});
                              setVState(() {});
                            },
                            child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.close, size: 14, color: Colors.grey.shade400)),
                          ),
                        ],
                      ),
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }

  void _showBehoerdeTerminDialog({
    required String behoerdeType,
    required String behoerdeLabel,
    required List<Map<String, dynamic>> termine,
    required Map<String, dynamic> data,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required StateSetter setLocalState,
    Map<String, dynamic>? existing,
    int? editIndex,
  }) {
    String terminart = existing?['terminart']?.toString() ?? 'selbst';
    final einladungDatumC = TextEditingController(text: existing?['einladung_datum']?.toString() ?? '');
    final briefErhaltenC = TextEditingController(text: existing?['brief_erhalten']?.toString() ?? '');
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: existing?['uhrzeit']?.toString() ?? '');
    final ansprechpartnerC = TextEditingController(text: existing?['ansprechpartner']?.toString() ?? '');
    final grundC = TextEditingController(text: existing?['grund']?.toString() ?? '');
    // Auto-fill ort from zuständige Dienststelle or Krankenkasse name
    String defaultOrt = existing?['ort']?.toString() ?? '';
    if (defaultOrt.isEmpty) {
      final sel = _findSelectedStandort(behoerdeType, data['dienststelle']?.toString() ?? '');
      if (sel != null) {
        defaultOrt = '${sel['name']}, ${sel['strasse']}, ${sel['plz_ort']}';
      } else if ((data['dienststelle']?.toString() ?? '').isNotEmpty) {
        defaultOrt = data['dienststelle'].toString();
      } else if ((data['name']?.toString() ?? '').isNotEmpty) {
        // Fallback: use name field (e.g. Krankenkasse name)
        defaultOrt = data['name'].toString();
      }
    }
    final ortC = TextEditingController(text: defaultOrt);
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    bool addToCalendar = existing?['termin_id'] != null || editIndex == null;

    showDialog(
      context: context,
      builder: (dlgCtx) => StatefulBuilder(
        builder: (dlgCtx, setDlgState) {
          final isEinladung = terminart == 'einladung';
          return AlertDialog(
          title: Row(children: [
            Icon(Icons.event, size: 18, color: Colors.deepPurple.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text(editIndex != null ? 'Termin bearbeiten' : 'Neuer Termin \u2013 $behoerdeLabel', style: const TextStyle(fontSize: 15))),
          ]),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Terminart: Selbst oder Einladung
                  Row(children: [
                    Icon(Icons.category, size: 16, color: Colors.deepPurple.shade600),
                    const SizedBox(width: 8),
                    Text('Art:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.event, size: 13, color: terminart == 'selbst' ? Colors.white : Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text('Selbst', style: TextStyle(fontSize: 11, color: terminart == 'selbst' ? Colors.white : Colors.blue.shade700)),
                      ]),
                      selected: terminart == 'selbst',
                      selectedColor: Colors.blue.shade600,
                      backgroundColor: Colors.blue.shade50,
                      side: BorderSide(color: terminart == 'selbst' ? Colors.blue.shade600 : Colors.blue.shade200),
                      onSelected: (_) => setDlgState(() => terminart = 'selbst'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.mail, size: 13, color: terminart == 'einladung' ? Colors.white : Colors.orange.shade700),
                        const SizedBox(width: 4),
                        Text('Einladung/Vorladung', style: TextStyle(fontSize: 11, color: terminart == 'einladung' ? Colors.white : Colors.orange.shade700)),
                      ]),
                      selected: terminart == 'einladung',
                      selectedColor: Colors.orange.shade600,
                      backgroundColor: Colors.orange.shade50,
                      side: BorderSide(color: terminart == 'einladung' ? Colors.orange.shade600 : Colors.orange.shade200),
                      onSelected: (_) => setDlgState(() => terminart = 'einladung'),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  // AOK Online Terminvereinbarung link for Krankenkasse + Selbst
                  if (!isEinladung && behoerdeType == 'krankenkasse') ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.green.shade300),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.language, size: 20, color: Colors.green.shade700),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Online Terminvereinbarung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                                const SizedBox(height: 2),
                                Text('AOK Terminportal öffnen', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                              ],
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              final nav = Navigator.of(context);
                              Navigator.of(dlgCtx).pop(); // close dialog first
                              nav.push(MaterialPageRoute(
                                builder: (_) => const WebViewScreen(
                                  title: 'AOK Terminvereinbarung',
                                  url: 'https://www.aok.de/pk/kontakt/terminvereinbarung',
                                ),
                              ));
                            },
                            icon: const Icon(Icons.open_in_new, size: 14),
                            label: const Text('Öffnen', style: TextStyle(fontSize: 11)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade600,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              minimumSize: Size.zero,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  // Postal section only for Einladung/Vorladung
                  if (isEinladung) ...[
                  // Einladung erstellt (when authority generated the letter)
                  TextFormField(
                    controller: einladungDatumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Einladung erstellt am',
                      prefixIcon: Icon(Icons.mail_outline, size: 18, color: Colors.blue.shade600),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(einladungDatumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            setDlgState(() => einladungDatumC.text = DateFormat('yyyy-MM-dd').format(picked));
                          }
                        },
                      ),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      helperText: 'Datum auf dem Brief',
                      helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Brief erhalten (when client received the letter)
                  TextFormField(
                    controller: briefErhaltenC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Brief erhalten am',
                      prefixIcon: Icon(Icons.mark_email_read, size: 18, color: Colors.green.shade600),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(briefErhaltenC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            setDlgState(() => briefErhaltenC.text = DateFormat('yyyy-MM-dd').format(picked));
                          }
                        },
                      ),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      helperText: 'Wann hat der Klient den Brief bekommen?',
                      helperStyle: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Postlaufzeit info (rebuilds via setDlgState)
                  if (DateTime.tryParse(einladungDatumC.text) != null && DateTime.tryParse(briefErhaltenC.text) != null) ...[
                    () {
                      final days = DateTime.parse(briefErhaltenC.text).difference(DateTime.parse(einladungDatumC.text)).inDays;
                      final color = days <= 2 ? Colors.green : (days <= 5 ? Colors.orange : Colors.red);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(children: [
                          Icon(Icons.local_shipping, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text('Postlaufzeit: $days Tag${days == 1 ? '' : 'e'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
                        ]),
                      );
                    }(),
                  ],
                  ], // end isEinladung
                  // Termin datum
                  TextFormField(
                    controller: datumC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Termin am *',
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.edit_calendar, size: 16),
                        onPressed: () async {
                          final picked = await showDatePicker(context: dlgCtx, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
                          if (picked != null) {
                            datumC.text = DateFormat('yyyy-MM-dd').format(picked);
                          }
                        },
                      ),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: uhrzeitC,
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: 'Uhrzeit *',
                      prefixIcon: const Icon(Icons.access_time, size: 18),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.schedule, size: 16),
                        onPressed: () async {
                          final parts = uhrzeitC.text.split(':');
                          final initTime = parts.length == 2 ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0) : const TimeOfDay(hour: 9, minute: 0);
                          final picked = await showTimePicker(context: dlgCtx, initialTime: initTime);
                          if (picked != null) {
                            uhrzeitC.text = '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                          }
                        },
                      ),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: ansprechpartnerC,
                    decoration: InputDecoration(
                      labelText: 'Bei wem? (Ansprechpartner/Sachbearbeiter)',
                      prefixIcon: const Icon(Icons.person, size: 18),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: grundC,
                    decoration: InputDecoration(
                      labelText: 'Grund des Termins',
                      prefixIcon: const Icon(Icons.subject, size: 18),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Ort auto-filled from Zuständige Dienststelle
                  if (defaultOrt.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.deepPurple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.deepPurple.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.place, size: 18, color: Colors.deepPurple.shade600),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Ort / Adresse', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                                const SizedBox(height: 2),
                                Text(ortC.text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.deepPurple.shade800)),
                              ],
                            ),
                          ),
                          Text('aus Dienststelle', style: TextStyle(fontSize: 9, color: Colors.deepPurple.shade400)),
                        ],
                      ),
                    ),
                  ] else
                    TextFormField(
                      controller: ortC,
                      decoration: InputDecoration(
                        labelText: 'Ort / Adresse',
                        prefixIcon: const Icon(Icons.place, size: 18),
                        isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: notizC,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: 'Notiz (optional)',
                      prefixIcon: const Icon(Icons.note, size: 18),
                      isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    title: const Text('In Terminverwaltung eintragen', style: TextStyle(fontSize: 13)),
                    subtitle: const Text('Termin erscheint im Kalender', style: TextStyle(fontSize: 11)),
                    secondary: Icon(Icons.calendar_month, size: 20, color: Colors.green.shade600),
                    value: addToCalendar,
                    activeTrackColor: Colors.green.shade200,
                    activeThumbColor: Colors.green.shade700,
                    onChanged: (v) => setDlgState(() => addToCalendar = v),
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
              label: Text(editIndex != null ? 'Speichern' : 'Termin erstellen'),
              style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple.shade600),
              onPressed: () async {
                if (datumC.text.isEmpty || uhrzeitC.text.isEmpty) return;

                final entry = <String, dynamic>{
                  'terminart': terminart,
                  'einladung_datum': einladungDatumC.text.trim(),
                  'brief_erhalten': briefErhaltenC.text.trim(),
                  'datum': datumC.text,
                  'uhrzeit': uhrzeitC.text,
                  'ansprechpartner': ansprechpartnerC.text.trim(),
                  'grund': grundC.text.trim(),
                  'ort': ortC.text.trim(),
                  'notiz': notizC.text.trim(),
                  'behoerde': behoerdeLabel,
                };
                // Preserve verlauf if editing
                if (existing?['verlauf'] != null) {
                  entry['verlauf'] = existing!['verlauf'];
                }

                // Preserve existing termin_id if editing
                if (existing?['termin_id'] != null) {
                  entry['termin_id'] = existing!['termin_id'];
                }

                // Create/update in Terminverwaltung
                if (addToCalendar) {
                  try {
                    final timeParts = uhrzeitC.text.split(':');
                    final h = int.tryParse(timeParts[0]) ?? 9;
                    final m = timeParts.length > 1 ? int.tryParse(timeParts[1]) ?? 0 : 0;
                    final terminDate = DateTime.parse(datumC.text).add(Duration(hours: h, minutes: m));
                    final title = '$behoerdeLabel-Termin${ansprechpartnerC.text.trim().isNotEmpty ? ' bei ${ansprechpartnerC.text.trim()}' : ''}';
                    final desc = [
                      if (grundC.text.trim().isNotEmpty) 'Grund: ${grundC.text.trim()}',
                      if (ortC.text.trim().isNotEmpty) 'Ort: ${ortC.text.trim()}',
                      if (notizC.text.trim().isNotEmpty) 'Notiz: ${notizC.text.trim()}',
                      'Mitglied: ${widget.user.name} (${widget.user.mitgliedernummer})',
                    ].join('\n');

                    final result = await widget.terminService.createTermin(
                      title: title,
                      category: 'sonstiges',
                      description: desc,
                      terminDate: terminDate,
                      durationMinutes: 60,
                      location: ortC.text.trim(),
                      participantIds: [widget.user.id],
                    );
                    if (result.containsKey('termin')) {
                      entry['termin_id'] = result['termin']['id'];
                    }
                  } catch (e) {
                    debugPrint('Behoerde termin create error: $e');
                  }
                }

                final updated = List<Map<String, dynamic>>.from(termine);
                if (editIndex != null && editIndex < updated.length) {
                  updated[editIndex] = entry;
                } else {
                  updated.add(entry);
                }

                if (dlgCtx.mounted) Navigator.pop(dlgCtx);
                onChanged(updated);
              },
            ),
          ],
        );
        },
      ),
    );
  }

  List<Map<String, dynamic>> _getMeldungen(Map<String, dynamic> data) {
    if (data['meldungen'] is List && (data['meldungen'] as List).isNotEmpty) {
      return List<Map<String, dynamic>>.from(
        (data['meldungen'] as List).map((e) => Map<String, dynamic>.from(e as Map)),
      );
    }
    return [];
  }

  String _meldungStatusText(String status) {
    const map = {
      'gemeldet': 'Gemeldet',
      'bestaetigt': 'Bestaetigt',
      'termin_erhalten': 'Termin erhalten',
      'abgeschlossen': 'Abgeschlossen',
    };
    return map[status] ?? status;
  }

  Color _meldungStatusColor(String status) {
    switch (status) {
      case 'gemeldet': return Colors.blue;
      case 'bestaetigt': return Colors.orange;
      case 'termin_erhalten': return Colors.purple;
      case 'abgeschlossen': return Colors.green;
      default: return Colors.grey;
    }
  }

  Future<Map<String, dynamic>?> _showMeldungDialog({
    required BuildContext context,
    Map<String, dynamic>? existingMeldung,
    String autoSvNummer = '',
  }) async {
    final isEdit = existingMeldung != null;
    final datumController = TextEditingController(text: existingMeldung?['datum'] ?? '');
    final taetigkeitController = TextEditingController(text: existingMeldung?['letzte_taetigkeit'] ?? '');
    final taetigkeitEndeController = TextEditingController(text: existingMeldung?['taetigkeit_ende_datum'] ?? '');
    final svNrController = TextEditingController(
      text: (existingMeldung?['sv_nummer'] ?? '').toString().isNotEmpty
          ? existingMeldung!['sv_nummer']
          : autoSvNummer,
    );
    String status = existingMeldung?['status'] ?? 'gemeldet';
    String meldungsart = existingMeldung?['meldungsart'] ?? 'vor_ort';
    bool gesundheitlichFaehig = existingMeldung?['gesundheitlich_faehig'] ?? true;
    bool hasSchwerbehinderung = existingMeldung?['has_schwerbehinderung'] == true;
    bool krankengeldEnde = existingMeldung?['krankengeld_ende'] == true;
    String erreichbarkeit = existingMeldung?['erreichbarkeit'] ?? 'telefonisch';
    bool datenschutzKenntnisnahme = existingMeldung?['datenschutz_kenntnisnahme'] == true;

    return showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDlgState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(isEdit ? Icons.edit : Icons.assignment_ind, color: Colors.deepPurple),
                  const SizedBox(width: 8),
                  Text(isEdit ? 'Meldung bearbeiten' : 'Neue Arbeitsuchendmeldung', style: const TextStyle(fontSize: 16)),
                ],
              ),
              content: SizedBox(
                width: 550,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Datum
                      Text('Meldung am', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: datumController,
                        readOnly: true,
                        decoration: InputDecoration(
                          hintText: 'TT.MM.JJJJ',
                          prefixIcon: const Icon(Icons.calendar_today, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            locale: const Locale('de', 'DE'),
                          );
                          if (picked != null) {
                            datumController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                          }
                        },
                      ),
                      const SizedBox(height: 12),

                      // Status
                      Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: status,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'gemeldet', child: Text('Gemeldet', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'bestaetigt', child: Text('Bestaetigt', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'termin_erhalten', child: Text('Termin erhalten', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'abgeschlossen', child: Text('Abgeschlossen', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setDlgState(() => status = v ?? 'gemeldet'),
                      ),
                      const SizedBox(height: 12),

                      // Art der Meldung
                      Text('Art der Meldung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: meldungsart,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          prefixIcon: const Icon(Icons.how_to_reg, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'vor_ort', child: Text('Vor Ort (persoenlich)', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'online', child: Text('Online', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'telefonisch', child: Text('Telefonisch', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setDlgState(() => meldungsart = v ?? 'vor_ort'),
                      ),
                      const SizedBox(height: 16),

                      // Berufliche Situation
                      Text('Berufliche Situation', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                      const Divider(height: 16),
                      Text('Letzte Taetigkeit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: taetigkeitController,
                        decoration: InputDecoration(
                          hintText: 'z.B. Helfer/in - Chemie- und Pharmatechnik',
                          prefixIcon: const Icon(Icons.work, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text('Ende der Taetigkeit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: taetigkeitEndeController,
                        readOnly: true,
                        decoration: InputDecoration(
                          hintText: 'TT.MM.JJJJ',
                          prefixIcon: const Icon(Icons.calendar_today, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2035),
                            locale: const Locale('de', 'DE'),
                          );
                          if (picked != null) {
                            taetigkeitEndeController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                      Text('Sozialversicherungsnummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: svNrController,
                        decoration: InputDecoration(
                          hintText: '12 340567 A 890',
                          prefixIcon: const Icon(Icons.badge, size: 20),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: const Text('Gesundheitlich in der Lage, neue Arbeit aufzunehmen', style: TextStyle(fontSize: 12)),
                        value: gesundheitlichFaehig,
                        onChanged: (v) => setDlgState(() => gesundheitlichFaehig = v ?? true),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        title: const Text('Schwerbehinderung / Gleichstellung', style: TextStyle(fontSize: 12)),
                        value: hasSchwerbehinderung,
                        onChanged: (v) => setDlgState(() => hasSchwerbehinderung = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      CheckboxListTile(
                        title: const Text('Krankengeld-Hoechstanspruchsdauer erreicht', style: TextStyle(fontSize: 12)),
                        value: krankengeldEnde,
                        onChanged: (v) => setDlgState(() => krankengeldEnde = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                      ),
                      const SizedBox(height: 12),
                      Text('Erreichbarkeit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<String>(
                        initialValue: erreichbarkeit,
                        isExpanded: true,
                        decoration: InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          prefixIcon: const Icon(Icons.phone, size: 20),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'telefonisch', child: Text('Telefonisch erreichbar', style: TextStyle(fontSize: 13))),
                          DropdownMenuItem(value: 'postalisch', child: Text('Nur postalisch erreichbar', style: TextStyle(fontSize: 13))),
                        ],
                        onChanged: (v) => setDlgState(() => erreichbarkeit = v ?? 'telefonisch'),
                      ),
                      const SizedBox(height: 8),
                      CheckboxListTile(
                        title: Text(
                          'Kenntnisnahme Datenverarbeitung (par.67a SGB X, Art.6 DSGVO)',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                        ),
                        value: datenschutzKenntnisnahme,
                        onChanged: (v) => setDlgState(() => datenschutzKenntnisnahme = v ?? false),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
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
                  onPressed: () {
                    final now = DateTime.now();
                    final nowStr = '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
                    final Map<String, dynamic> result = {
                      'datum': datumController.text.trim().isNotEmpty ? datumController.text.trim() : nowStr,
                      'status': status,
                      'meldungsart': meldungsart,
                      'letzte_taetigkeit': taetigkeitController.text.trim(),
                      'taetigkeit_ende_datum': taetigkeitEndeController.text.trim(),
                      'sv_nummer': svNrController.text.trim(),
                      'gesundheitlich_faehig': gesundheitlichFaehig,
                      'has_schwerbehinderung': hasSchwerbehinderung,
                      'krankengeld_ende': krankengeldEnde,
                      'erreichbarkeit': erreichbarkeit,
                      'datenschutz_kenntnisnahme': datenschutzKenntnisnahme,
                    };

                    // Build verlauf
                    List<Map<String, dynamic>> verlauf = [];
                    if (isEdit) {
                      verlauf = List<Map<String, dynamic>>.from(
                        (existingMeldung['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
                      );
                      if (status != existingMeldung['status']) {
                        verlauf.add({
                          'datum': nowStr,
                          'aktion': 'Status geandert: ${_meldungStatusText(existingMeldung['status'] ?? '')} -> ${_meldungStatusText(status)}',
                          'status': status,
                        });
                      }
                    } else {
                      final artLabel = meldungsart == 'vor_ort' ? 'Vor Ort' : meldungsart == 'online' ? 'Online' : 'Telefonisch';
                      verlauf = [
                        {
                          'datum': datumController.text.trim().isNotEmpty ? datumController.text.trim() : nowStr,
                          'aktion': 'Arbeitsuchendmeldung erstellt ($artLabel)',
                          'status': status,
                        },
                      ];
                    }
                    result['verlauf'] = verlauf;

                    Navigator.pop(ctx, result);
                  },
                  icon: Icon(isEdit ? Icons.save : Icons.add, size: 18),
                  label: Text(isEdit ? 'Speichern' : 'Meldung erstellen'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildMeldungenSection({
    required List<Map<String, dynamic>> meldungen,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required BuildContext context,
    String autoSvNummer = '',
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 4),
          child: Row(
            children: [
              Icon(Icons.assignment_ind, size: 20, color: Colors.deepPurple),
              const SizedBox(width: 8),
              Text('Arbeitsuchendmeldungen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              const SizedBox(width: 8),
              if (meldungen.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('${meldungen.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
                ),
              const Spacer(),
              TextButton.icon(
                onPressed: () async {
                  final result = await _showMeldungDialog(context: context, autoSvNummer: autoSvNummer);
                  if (result != null) {
                    final updated = List<Map<String, dynamic>>.from(meldungen);
                    updated.add(result);
                    onChanged(updated);
                  }
                },
                icon: Icon(Icons.add_circle, size: 18, color: Colors.deepPurple),
                label: Text('Neue Meldung', style: TextStyle(fontSize: 12, color: Colors.deepPurple)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
              ),
              Expanded(child: Divider(color: Colors.deepPurple.shade200, thickness: 1)),
            ],
          ),
        ),
        const SizedBox(height: 8),

        if (meldungen.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              children: [
                Icon(Icons.assignment_ind_outlined, size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Keine Arbeitsuchendmeldungen vorhanden', style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ],
            ),
          )
        else
          ...meldungen.asMap().entries.map((entry) {
            final idx = entry.key;
            final m = entry.value;
            final datum = m['datum'] ?? '';
            final status = m['status'] ?? '';
            final mArt = m['meldungsart'] ?? '';
            final taetigkeit = m['letzte_taetigkeit'] ?? '';
            final verlauf = List<Map<String, dynamic>>.from(
              (m['verlauf'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
            );

            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                  childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  leading: Icon(Icons.assignment_ind, color: _meldungStatusColor(status), size: 22),
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Meldung vom $datum',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _meldungStatusColor(status).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _meldungStatusColor(status).withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          _meldungStatusText(status),
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: _meldungStatusColor(status)),
                        ),
                      ),
                    ],
                  ),
                  subtitle: (taetigkeit.isNotEmpty || mArt.isNotEmpty)
                      ? Text(
                          [
                            if (mArt.isNotEmpty) mArt == 'vor_ort' ? 'Vor Ort' : mArt == 'online' ? 'Online' : mArt == 'telefonisch' ? 'Telefonisch' : mArt,
                            if (taetigkeit.isNotEmpty) taetigkeit,
                          ].join(' · '),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        )
                      : null,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.edit, size: 18, color: Colors.deepPurple),
                        tooltip: 'Bearbeiten',
                        onPressed: () async {
                          final result = await _showMeldungDialog(
                            context: context,
                            existingMeldung: m,
                            autoSvNummer: autoSvNummer,
                          );
                          if (result != null) {
                            final updated = List<Map<String, dynamic>>.from(meldungen);
                            updated[idx] = result;
                            onChanged(updated);
                          }
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                        tooltip: 'Loschen',
                        onPressed: () async {
                          final confirm = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Meldung loschen?', style: TextStyle(fontSize: 16)),
                              content: Text('Meldung vom $datum wirklich loschen?'),
                              actions: [
                                TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                  child: const Text('Loschen'),
                                ),
                              ],
                            ),
                          );
                          if (confirm == true) {
                            final updated = List<Map<String, dynamic>>.from(meldungen);
                            updated.removeAt(idx);
                            onChanged(updated);
                          }
                        },
                      ),
                    ],
                  ),
                  children: [
                    // Details
                    if (m['sv_nummer'] != null && m['sv_nummer'].toString().isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.badge, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text('SV-Nr: ${m['sv_nummer']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (m['taetigkeit_ende_datum'] != null && m['taetigkeit_ende_datum'].toString().isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.event, size: 14, color: Colors.grey.shade600),
                          const SizedBox(width: 6),
                          Text('Ende Taetigkeit: ${m['taetigkeit_ende_datum']}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        ],
                      ),
                      const SizedBox(height: 4),
                    ],
                    Row(
                      children: [
                        Icon(m['gesundheitlich_faehig'] == true ? Icons.check_circle : Icons.cancel, size: 14, color: m['gesundheitlich_faehig'] == true ? Colors.green : Colors.red),
                        const SizedBox(width: 6),
                        Text('Gesundheitlich faehig: ${m['gesundheitlich_faehig'] == true ? "Ja" : "Nein"}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        const SizedBox(width: 16),
                        Icon(m['has_schwerbehinderung'] == true ? Icons.accessible : Icons.close, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text('Schwerbehinderung: ${m['has_schwerbehinderung'] == true ? "Ja" : "Nein"}', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Verlauf
                    if (verlauf.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(Icons.history, size: 16, color: Colors.blue.shade700),
                          const SizedBox(width: 6),
                          Text('Verlauf', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: Colors.blue.shade100),
                        ),
                        child: Column(
                          children: (verlauf.reversed.toList()..sort((a, b) {
                            final da = (a['datum'] ?? '').toString().split('.');
                            final db = (b['datum'] ?? '').toString().split('.');
                            if (da.length == 3 && db.length == 3) {
                              return '${db[2]}${db[1]}${db[0]}'.compareTo('${da[2]}${da[1]}${da[0]}');
                            }
                            return 0;
                          })).map((v) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 8, height: 8,
                                    margin: const EdgeInsets.only(top: 4, right: 8),
                                    decoration: BoxDecoration(
                                      color: _meldungStatusColor(v['status'] ?? ''),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  Text(v['datum'] ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                  const SizedBox(width: 8),
                                  Expanded(child: Text(v['aktion'] ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
      ],
    );
  }



  // Grundfreibetrag per year (Einzelveranlagung) - updated with each app release

  /// Get Grundfreibetrag for a given year (returns latest known if year not in table)



  /// Format number as German currency (e.g. 12.348 EUR)

  /// Format double as EUR with 2 decimals (e.g. "13,90 EUR")

  // ── FINANZAMT-DATENBANK (Kontaktdaten) ──








  /// NEW ANTRAG — opens form dialog, saves on Speichern

  /// EXISTING ANTRAG — 2 tabs: Details + Korrespondenz










  // Kindergeld per month per child (einheitlich since 2023)



  /// Parse German date format (DD.MM.YYYY) to DateTime

  /// Calculate age from German date string

  /// Check if a child is eligible for Kindergeld

  /// Get info text about Kindergeld eligibility for a child

  /// Toggle chip for Merkzeichen in Schwerbehindertenausweis

  /// Check if a child has a specific Merkzeichen









}

/// Upload progress dialog for Antrag documents
class _AntragUploadProgressDialog extends StatefulWidget {
  final List<PlatformFile> files;
  final ApiService apiService;
  final int userId;
  final String behoerdeType;
  final String antragId;
  final void Function(int successCount, String? errorMsg) onComplete;

  const _AntragUploadProgressDialog({
    required this.files,
    required this.apiService,
    required this.userId,
    required this.behoerdeType,
    required this.antragId,
    required this.onComplete,
  });

  @override
  State<_AntragUploadProgressDialog> createState() => _AntragUploadProgressDialogState();
}

class _AntragUploadProgressDialogState extends State<_AntragUploadProgressDialog> {
  int _uploaded = 0;
  int _total = 0;
  String _currentFile = '';
  String? _error;

  @override
  void initState() {
    super.initState();
    _total = widget.files.length;
    _startUpload();
  }

  Future<void> _startUpload() async {
    int successCount = 0;
    String? lastError;

    for (final file in widget.files) {
      if (file.path == null) continue;
      if (mounted) {
        setState(() => _currentFile = file.name);
      }
      try {
        final res = await widget.apiService.uploadAntragDokument(
          userId: widget.userId,
          behoerdeType: widget.behoerdeType,
          antragId: widget.antragId,
          filePath: file.path!,
          fileName: file.name,
        );
        if (res['success'] == true) {
          successCount++;
        } else {
          lastError = res['message'] ?? 'Upload fehlgeschlagen';
        }
      } catch (e) {
        lastError = e.toString();
      }
      if (mounted) {
        setState(() {
          _uploaded++;
          _error = lastError;
        });
      }
    }

    // Small delay so user sees 100%
    await Future.delayed(const Duration(milliseconds: 400));
    widget.onComplete(successCount, lastError);
  }

  @override
  Widget build(BuildContext context) {
    final progress = _total > 0 ? _uploaded / _total : 0.0;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.upload_file, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          const Text('Dokumente hochladen', style: TextStyle(fontSize: 15)),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('$_uploaded / $_total Dateien hochgeladen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.teal.shade800)),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.teal.shade100,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade600),
                minHeight: 10,
              ),
            ),
            const SizedBox(height: 8),
            if (_currentFile.isNotEmpty)
              Text(_currentFile, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(fontSize: 11, color: Colors.red)),
            ],
          ],
        ),
      ),
    );
  }
}
