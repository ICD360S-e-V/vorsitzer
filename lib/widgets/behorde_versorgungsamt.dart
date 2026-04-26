import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'file_viewer_dialog.dart';
import 'korrespondenz_attachments_widget.dart';
import '../services/termin_service.dart';

/// Versorgungsamt content with tabs similar to Arzt structure.
class BehordeVersorgungsamtContent extends StatefulWidget {
  final ApiService apiService;
  final TerminService terminService;
  final int userId;
  final User user;
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
    required this.user,
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

  /// Exhaustive Nachteilsausgleiche per GdB level (Stand 2025/2026).
  /// CUMULATIVE — higher GdB inherits all benefits from lower levels.
  /// Sources: betanet.de, familienratgeber.de, gegen-hartz.de, rehadat.de, SGB IX, § 33b EStG
  static const Map<int, List<String>> _gdbBenefits = {
    20: [
      'Behindertenpauschbetrag: 384 €/Jahr (§ 33b EStG, seit 2021 ohne Zusatz)',
      'Alternativ tatsächliche Kosten als außergewöhnliche Belastung (§ 33 EStG)',
      'Prüfungs-Nachteilsausgleich an Schulen/Hochschulen (verlängerte Fristen)',
      'In Berufsausbildung: automatische Gleichstellung (§ 151 Abs. 4 SGB IX)',
      'Oranger Parkausweis möglich (funktionsabhängig, nicht automatisch)',
      '⚠ KEIN Schwerbehindertenausweis, keine Gleichstellung für Berufstätige',
      '⚠ KEIN Kündigungsschutz, kein Zusatzurlaub, keine KFZ-Ermäßigung',
    ],
    30: [
      'Behindertenpauschbetrag: 620 €/Jahr',
      'Gleichstellung mit Schwerbehinderten möglich (§ 2 Abs. 3 SGB IX)',
      'Antrag bei Agentur für Arbeit — Voraussetzung: Arbeitsplatz gefährdet',
      'MIT Gleichstellung: Kündigungsschutz (§ 168 SGB IX) via Integrationsamt',
      'MIT Gleichstellung: Freistellung von Mehrarbeit (§ 207 SGB IX)',
      'Begleitende Hilfe im Arbeitsleben (§ 185 SGB IX): Arbeitsassistenz ~40 h/Mo',
      'Integrationsfachdienst (IFD) — Beratung für AN und AG',
      'Eingliederungszuschuss AG: bis 70 % / 24 Monate (§§ 88 ff. SGB III)',
      'Anrechnung auf Pflichtquote (AG spart Ausgleichsabgabe bis 815 €/Mo)',
      'Bevorzugte Einstellung im öffentl. Dienst bei gleicher Eignung',
      '⚠ KEIN Zusatzurlaub, kein Schwerbehindertenausweis',
      '⚠ KEIN ÖPNV-Freifahrt, keine KFZ-Steuerermäßigung',
      '⚠ KEINE vorzeitige Rente (erst ab GdB 50)',
    ],
    40: [
      'Behindertenpauschbetrag: 860 €/Jahr',
      'Gleichstellung wie GdB 30 — typischerweise leichter bewilligt',
      'Alle Gleichstellungs-Rechte wie GdB 30 (Kündigungsschutz, IFD, §185)',
      'Ab 2026: digitaler GdB-Nachweis in Pilotregionen',
      '⚠ KEIN Schwerbehindertenstatus (erst ab GdB 50)',
    ],
    50: [
      '✅ OFFIZIELLER Schwerbehindertenstatus + Schwerbehindertenausweis',
      'Behindertenpauschbetrag: 1.140 €/Jahr',
      'Besonderer Kündigungsschutz (§ 168 SGB IX) OHNE Gleichstellungsantrag',
      'Zusatzurlaub: 5 Arbeitstage/Jahr (§ 208 SGB IX)',
      'Freistellung von Mehrarbeit auf Verlangen (§ 207 SGB IX)',
      'Bevorzugte Einstellung bei öffentl. Arbeitgebern (§ 164 SGB IX)',
      'Kündigungsschutz erst nach 6 Monaten Betriebszugehörigkeit',
      'Prämien/Lohnkostenzuschuss für AG: bis 70 % / 24 Monate',
      'Altersrente für Schwerbehinderte: 2 Jahre früher abschlagsfrei',
      'Vorzeitige Rente bis 3 J. früher (max. −10,8 % Abschlag, 0,3 %/Monat)',
      'Wertmarke ÖPNV: 104 €/Jahr (kostenlos mit H/Bl/TBl oder Bürgergeld)',
      'Begleitperson fährt gratis ÖPNV/Fernverkehr mit Merkzeichen B',
      'KFZ-Steuer: −50 % mit Merkzeichen G',
      'KFZ-Steuer: 100 % Befreiung mit aG/H/Bl',
      'Zuzahlungsgrenze GKV: 1 % vom Bruttoeinkommen (schwerwiegend chron. krank)',
      'Erleichterter Zugang zu Rehabilitationsmaßnahmen',
      'Erweiterter Kündigungsschutz bei Mietwohnung',
      'WBS-Einkommensfreibetrag für sozialen Wohnungsbau',
      'Wohnraumanpassung via Pflegekasse/KfW: bis 4.180 €/Maßnahme',
      'KFZ-Hilfe bei Arbeit: bis 22.000 € Zuschuss (Reha-Träger)',
      'Blauer EU-Parkausweis mit Merkzeichen aG oder Bl',
      'Oranger Parkausweis mit G (gleichwertige Einschränkungen)',
      'Gebührenermäßigung Behörden, Kurtaxe, Museen, Zoos, Freibäder',
      'Hunde-Steuerbefreiung für Assistenzhunde (kommunal)',
    ],
    60: [
      'Behindertenpauschbetrag: 1.440 €/Jahr',
      'Rundfunkbeitrag: 6,12 €/Mo (statt 18,36 €) mit Merkzeichen RF',
      'RF bei Sehbehinderung: ab GdB 60 wegen Sehbehinderung (§ 4 RBStV)',
      'Oranger Parkausweis: Morbus Crohn/Colitis mit Einzel-GdB ≥ 60',
      'Erleichterte Anerkennung "schwerwiegend chronisch krank" (1 %-Grenze)',
      '✅ Alle Vorteile ab GdB 50',
    ],
    70: [
      'Behindertenpauschbetrag: 1.780 €/Jahr',
      'Behinderten-Fahrtkostenpauschale: 900 €/Jahr (+ Merkzeichen G)',
      'BahnCard 25 ermäßigt: 40,90 €/Jahr (2. Kl.)',
      'BahnCard 50 ermäßigt: 122 €/Jahr (2. Kl.) / 241 € (1. Kl.)',
      'Oranger Parkausweis mit G+B (untere Extremitäten / LWS)',
      '✅ Alle Vorteile ab GdB 60',
    ],
    80: [
      'Behindertenpauschbetrag: 2.120 €/Jahr',
      'Fahrtkostenpauschale: 900 €/Jahr (auch ohne Merkzeichen)',
      'Fahrtkostenpauschale: 4.500 €/Jahr mit aG/Bl/H/TBl oder PG 4/5',
      'RF-Ermäßigung allgemein: GdB ≥ 80 + dauerhafte Teilnahmeunfähigkeit',
      'Pflegepauschbetrag pflegende Angehörige: bis 1.800 €/J (PG 2-5)',
      'Höhere Freibeträge bei Wohngeld / Mietminderung',
      'Telekom-Sozialtarif mit Merkzeichen Bl/Gl: −8,72 €/Mo',
      '✅ Alle Vorteile ab GdB 70',
    ],
    90: [
      'Behindertenpauschbetrag: 2.460 €/Jahr',
      'Erhöhter Kinderfreibetrag möglich (mit H/Bl/TBl)',
      'Telekom-Sozialtarif (Merkzeichen Bl/Gl): bis 8,72 €/Mo Rabatt',
      '✅ Alle Vorteile ab GdB 80 (Pauschbetrag ist Hauptunterschied)',
    ],
    100: [
      'Behindertenpauschbetrag: 2.840 €/Jahr (Maximum)',
      'Vorzeitige Verfügung über Bausparkassen-Guthaben (ab GdB 95)',
      'Vermögenswirksame Leistungen: vorzeitige Auflösung ohne Sanktionen',
      'Wohngeld-Freibetrag: 1.800 €/Jahr (GdB 100 direkt)',
      'Sozialwohnung: 4.500 € Einkommensabzug im Haushalt',
      'Erhöhte Priorität bei Sozialwohnungsvergabe',
      'Pflege-Pauschbetrag zusätzlich bei Pflegegrad',
      'Erhöhte Fahrtkostenpauschale 4.500 €/J mit aG/Bl/H/TBl',
      'EU-Behindertenausweis ab 2026 kostenlos (alle GdB ≥ 50)',
      '✅ Alle Vorteile ab GdB 90',
    ],
  };

  /// Erhöhter Pauschbetrag: 7.400 €/Jahr bei Merkzeichen H, Bl, TBl oder Pflegegrad 4/5
  /// (gilt unabhängig vom GdB, ersetzt den Standard-Pauschbetrag)
  static const int _erhoehterPauschbetrag = 7400;

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

  Map<String, Map<String, dynamic>> _dbData = {};
  Map<String, dynamic> _currentData = {};
  List<Map<String, dynamic>> _dbTermine = [];
  List<Map<String, dynamic>> _dbKorr = [];
  bool _dbLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFromDBDedicated();
  }

  Future<void> _loadFromDBDedicated() async {
    try {
      final dR = await widget.apiService.getVersorgungsamtData(widget.userId);
      final tR = await widget.apiService.listVersorgungsamtTermine(widget.userId);
      final kR = await widget.apiService.listVersorgungsamtKorr(widget.userId);
      if (!mounted) return;
      if (dR['success'] == true && dR['data'] is Map) {
        _dbData = {};
        (dR['data'] as Map).forEach((k, v) { if (v is Map) _dbData[k.toString()] = Map<String, dynamic>.from(v); });
      }
      if (tR['success'] == true && tR['data'] is List) _dbTermine = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _dbKorr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (e) {
      debugPrint('[Versorgungsamt] Load error: $e');
    }
    if (!mounted) return;
    // Map DB bereich.field → flat keys expected by _initControllers
    // DB stores as bereich=sachbearbeiter, feld_name=sachbearbeiter (from migration)
    // OR bereich=sachbearbeiter, feld_name=name (from new save)
    // Support both formats
    final flat = <String, dynamic>{};
    final sb = _dbData['sachbearbeiter'] ?? {};
    flat['sachbearbeiter_anrede'] = sb['sachbearbeiter_anrede'] ?? sb['anrede'];
    flat['sachbearbeiter'] = sb['sachbearbeiter'] ?? sb['name'];
    flat['sachbearbeiter_telefon'] = sb['sachbearbeiter_telefon'] ?? sb['telefon'];
    flat['sachbearbeiter_fax'] = sb['sachbearbeiter_fax'] ?? sb['fax'];
    flat['aktenzeichen'] = sb['aktenzeichen'];
    flat['notizen'] = sb['notizen'];
    final aus = _dbData['ausweis'] ?? {};
    flat['ausweis_nr'] = aus['ausweis_nr'] ?? aus['nr'];
    flat['ausweis_ausgestellt_am'] = aus['ausweis_ausgestellt_am'] ?? aus['ausgestellt_am'];
    flat['ausweis_gueltig_bis'] = aus['ausweis_gueltig_bis'] ?? aus['gueltig_bis'];
    flat['ausweis_unbefristet'] = aus['ausweis_unbefristet'] == 'true' || aus['ausweis_unbefristet'] == true || aus['unbefristet'] == 'true' || aus['unbefristet'] == true;
    final gdb = _dbData['gdb'] ?? {};
    flat['gdb_aktuell'] = int.tryParse((gdb['gdb_aktuell'] ?? gdb['aktuell'])?.toString() ?? '') ?? 0;
    flat['gdb_feststellung_datum'] = gdb['gdb_feststellung_datum'] ?? gdb['feststellung_datum'];
    flat['gdb_bescheid_datum'] = gdb['gdb_bescheid_datum'] ?? gdb['bescheid_datum'];
    // Amt data — reconstruct selected_amt Map from DB fields
    final amt = _dbData['amt'] ?? {};
    if (amt.isNotEmpty && (amt['name']?.toString() ?? '').isNotEmpty) {
      flat['selected_amt'] = Map<String, dynamic>.from(amt);
    }
    final sonstige = _dbData['sonstige'] ?? {};
    if (sonstige['selected_amt_id'] != null) flat['selected_amt_id'] = sonstige['selected_amt_id'];
    // Merkzeichen
    for (final m in ['g', 'ag', 'b', 'h', 'rf', 'bl', 'gl', 'tbl']) {
      flat['merkzeichen_$m'] = gdb['merkzeichen_$m'] == 'true' || gdb['merkzeichen_$m'] == true;
    }
    if (!_controllersInit) _initControllers(flat);
    setState(() => _dbLoaded = true);
  }

  Map<String, dynamic> _db(String bereich) {
    _dbData[bereich] ??= {};
    return _dbData[bereich]!;
  }

  Future<void> _saveDbData() async {
    final sb = _db('sachbearbeiter');
    sb['sachbearbeiter_anrede'] = _sbAnrede;
    sb['sachbearbeiter'] = _sbNameC.text.trim();
    sb['sachbearbeiter_telefon'] = _sbTelC.text.trim();
    sb['sachbearbeiter_fax'] = _sbFaxC.text.trim();
    sb['aktenzeichen'] = _joinAkt();
    sb['notizen'] = _notizenC.text.trim();
    final aus = _db('ausweis');
    aus['ausweis_nr'] = _ausweisNrC.text.trim();
    aus['ausweis_ausgestellt_am'] = _ausweisAusgestelltC.text.trim();
    aus['ausweis_gueltig_bis'] = _ausweisUnbefristet ? '' : _ausweisGueltigBisC.text.trim();
    aus['ausweis_unbefristet'] = _ausweisUnbefristet.toString();
    final gdb = _db('gdb');
    gdb['gdb_aktuell'] = _gdbAktuell.toString();
    gdb['gdb_feststellung_datum'] = _gdbFeststellungC.text.trim();
    gdb['gdb_bescheid_datum'] = _gdbBescheidC.text.trim();
    // merkzeichen already in gdb via _db('gdb')[key] set in onSelected
    await widget.apiService.saveVersorgungsamtData(widget.userId, _dbData);
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
    _saveDbData();
  }

  Future<void> _pickVersorgungsamt(Map<String, dynamic> data) async {
    final result = await widget.apiService.searchVersorgungsaemter();
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
                            final sonstige = _db('sonstige');
                            sonstige['selected_amt_id'] = a['id']?.toString() ?? '';
                            sonstige['selected_amt'] = a.toString();
                            final amt = _db('amt');
                            amt['name'] = a['name']?.toString() ?? '';
                            amt['kurzname'] = a['kurzname']?.toString() ?? '';
                            amt['strasse'] = a['strasse']?.toString() ?? '';
                            amt['plz_ort'] = a['plz_ort']?.toString() ?? '';
                            amt['telefon'] = a['telefon']?.toString() ?? '';
                            amt['email'] = a['email']?.toString() ?? '';
                            amt['oeffnungszeiten'] = a['oeffnungszeiten']?.toString() ?? '';
                          });
                          _saveDbData();
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
    if (!_dbLoaded) return const Center(child: CircularProgressIndicator());
    final data = <String, dynamic>{}; // legacy compat — flat map from DB data
    _dbData.forEach((bereich, fields) => fields.forEach((k, v) => data[k] = v));
    _currentData = data;
    // Reconstruct selected_amt Map for UI
    final amt = _dbData['amt'] ?? {};
    if (amt.isNotEmpty && (amt['name']?.toString() ?? '').isNotEmpty) {
      data['selected_amt'] = Map<String, dynamic>.from(amt);
    }
    final sonstige = _dbData['sonstige'] ?? {};
    if (sonstige['selected_amt_id'] != null) data['selected_amt_id'] = sonstige['selected_amt_id'];

    return DefaultTabController(
      length: 6,
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
              Tab(icon: Icon(Icons.description, size: 16), text: 'Antrag'),
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
                _buildAntragTab(data),
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
    final termine = _dbTermine;
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
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(
                          icon: Icon(Icons.open_in_new, size: 18, color: Colors.indigo.shade400),
                          tooltip: 'Details',
                          onPressed: () => _showTerminDetailDialog(data, termine, i),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, size: 18, color: Colors.red.shade400),
                          onPressed: () {
                            final tid = int.tryParse(termine[i]['id']?.toString() ?? '');
                            if (tid != null) widget.apiService.deleteVersorgungsamtTermin(tid);
                            _loadFromDBDedicated();
                            widget.saveData(type, data);
                          },
                        ),
                      ]),
                      onTap: () => _showTerminDetailDialog(data, termine, i),
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
              await widget.apiService.saveVersorgungsamtTermin(widget.userId, {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'notiz': notizenC.text});
              _loadFromDBDedicated();
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

  void _showTerminDetailDialog(Map<String, dynamic> data, List<Map<String, dynamic>> termine, int index) {
    final t = Map<String, dynamic>.from(termine[index]);
    final datumC = TextEditingController(text: t['datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: t['uhrzeit']?.toString() ?? '');
    final ergebnisC = TextEditingController(text: t['ergebnis']?.toString() ?? '');
    String typ = t['typ']?.toString() ?? 'normal';
    bool editing = false;
    final typen = [('normal', 'Normal', Colors.teal), ('anfrage', 'Anfrage', Colors.orange), ('absage', 'Absage', Colors.red), ('verschoben', 'Verschoben', Colors.blue)];
    List<Map<String, dynamic>> eintraege = [];
    bool eintraegeLoaded = false;

    Future<void> loadEintraege(StateSetter setD) async {
      final r = await widget.apiService.listVersorgungsamtEintraege(widget.userId, terminDatum: datumC.text);
      if (r['success'] == true && r['data'] is List) {
        setD(() {
          eintraege = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          eintraegeLoaded = true;
        });
      } else {
        setD(() => eintraegeLoaded = true);
      }
    }

    void saveTermin(StateSetter setD) {
      setState(() {
        termine[index] = {
          ...t,
          'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'typ': typ,
          'ergebnis': ergebnisC.text,
          'notizen': eintraege.isNotEmpty ? eintraege.first['inhalt'] ?? eintraege.first['text'] ?? '' : '',
        };
        data['termine'] = termine;
      });
      _saveDbData();
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        if (!eintraegeLoaded) loadEintraege(setD);
        final typColor = typ == 'anfrage' ? Colors.orange : (typ == 'absage' ? Colors.red : (typ == 'verschoben' ? Colors.blue : Colors.teal));
        return Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          insetPadding: const EdgeInsets.all(16),
          child: SizedBox(
            width: 580, height: 620,
            child: Column(children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: typColor.shade700,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                ),
                child: Row(children: [
                  Icon(Icons.event, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('${datumC.text}${uhrzeitC.text.isNotEmpty ? ' um ${uhrzeitC.text}' : ''}', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    Text(typ.toUpperCase(), style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  IconButton(icon: Icon(editing ? Icons.check : Icons.edit, color: Colors.white, size: 20), tooltip: editing ? 'Fertig' : 'Bearbeiten', onPressed: () {
                    if (editing) saveTermin(setD);
                    setD(() => editing = !editing);
                  }),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () { saveTermin(setD); Navigator.pop(ctx); }),
                ]),
              ),
              // Details (readonly or edit)
              if (editing)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Wrap(spacing: 6, children: typen.map((tp) {
                      final sel = typ == tp.$1;
                      return ChoiceChip(label: Text(tp.$2, style: TextStyle(fontSize: 10, color: sel ? Colors.white : tp.$3.shade700)), selected: sel, selectedColor: tp.$3.shade600, onSelected: (_) => setD(() => typ = tp.$1));
                    }).toList()),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                        final p = await showDatePicker(context: ctx2, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
                        if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
                      })),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(controller: uhrzeitC, readOnly: true, decoration: InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), onTap: () async {
                        final p = await showTimePicker(context: ctx2, initialTime: TimeOfDay.now());
                        if (p != null) setD(() => uhrzeitC.text = '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}');
                      })),
                    ]),
                    const SizedBox(height: 8),
                    TextField(controller: ergebnisC, maxLines: 2, decoration: InputDecoration(labelText: 'Ergebnis', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                  ]),
                )
              else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    if ((ergebnisC.text).isNotEmpty)
                      Expanded(child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Icon(Icons.assignment_turned_in, size: 14, color: Colors.amber.shade800),
                          const SizedBox(width: 6),
                          Expanded(child: Text(ergebnisC.text, style: const TextStyle(fontSize: 12))),
                        ]),
                      ))
                    else
                      Expanded(child: Text('Kein Ergebnis eingetragen. Auf ✏️ tippen um zu bearbeiten.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic))),
                  ]),
                ),
              const Divider(height: 1),
              // Einträge header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Row(children: [
                  Icon(Icons.list_alt, size: 18, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Text('Einträge & Notizen (${eintraege.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                  const Spacer(),
                  PopupMenuButton<String>(
                    icon: Icon(Icons.add_circle, color: Colors.indigo.shade700, size: 22),
                    tooltip: 'Neuer Eintrag',
                    onSelected: (eTyp) => _addEintrag(ctx2, setD, eintraege, eTyp, datumC.text, uhrzeitC.text, () { saveTermin(setD); loadEintraege(setD); }),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'notiz', child: Row(children: [Icon(Icons.note, size: 16, color: Colors.teal), SizedBox(width: 8), Text('Notiz')])),
                      const PopupMenuItem(value: 'email_eingang', child: Row(children: [Icon(Icons.call_received, size: 16, color: Colors.green), SizedBox(width: 8), Text('E-Mail Eingang')])),
                      const PopupMenuItem(value: 'email_ausgang', child: Row(children: [Icon(Icons.call_made, size: 16, color: Colors.blue), SizedBox(width: 8), Text('E-Mail Ausgang')])),
                      const PopupMenuItem(value: 'telefonat', child: Row(children: [Icon(Icons.phone, size: 16, color: Colors.orange), SizedBox(width: 8), Text('Telefonat')])),
                      const PopupMenuItem(value: 'dokument', child: Row(children: [Icon(Icons.description, size: 16, color: Colors.purple), SizedBox(width: 8), Text('Dokument / Brief')])),
                    ],
                  ),
                ]),
              ),
              // Einträge list
              Expanded(
                child: eintraege.isEmpty
                    ? Center(child: Text('Noch keine Einträge. Tippen Sie auf + um einen hinzuzufügen.', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: eintraege.length,
                        itemBuilder: (_, i) {
                          final e = eintraege[i];
                          final eTyp = e['typ']?.toString() ?? 'notiz';
                          final eIcon = switch (eTyp) { 'email_eingang' => Icons.call_received, 'email_ausgang' => Icons.call_made, 'telefonat' => Icons.phone, 'dokument' => Icons.description, _ => Icons.note };
                          final eColor = switch (eTyp) { 'email_eingang' => Colors.green, 'email_ausgang' => Colors.blue, 'telefonat' => Colors.orange, 'dokument' => Colors.purple, _ => Colors.teal };
                          final eLabel = switch (eTyp) { 'email_eingang' => 'E-Mail Eingang', 'email_ausgang' => 'E-Mail Ausgang', 'telefonat' => 'Telefonat', 'dokument' => 'Dokument', _ => 'Notiz' };
                          return InkWell(
                            onTap: () => _viewEintrag(ctx2, e, eLabel, eColor),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: eColor.shade200)),
                              child: Row(children: [
                                Icon(eIcon, size: 18, color: eColor.shade700),
                                const SizedBox(width: 8),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      decoration: BoxDecoration(color: eColor.shade100, borderRadius: BorderRadius.circular(6)),
                                      child: Text(eLabel, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: eColor.shade800)),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(e['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                  ]),
                                  if ((e['betreff']?.toString() ?? '').isNotEmpty)
                                    Text(e['betreff'].toString(), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: eColor.shade800)),
                                  Text(e['inhalt']?.toString() ?? e['text']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade700), maxLines: 2, overflow: TextOverflow.ellipsis),
                                ])),
                                IconButton(
                                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                                  onPressed: () async {
                                    final eid = int.tryParse(e['id']?.toString() ?? '');
                                    if (eid != null) await widget.apiService.deleteVersorgungsamtEintrag(eid);
                                    loadEintraege(setD);
                                  },
                                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                ),
                              ]),
                            ),
                          );
                        },
                      ),
              ),
              // Footer
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Colors.grey.shade300))),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton.icon(
                    icon: Icon(Icons.delete, size: 16, color: Colors.red.shade400),
                    label: Text('Termin löschen', style: TextStyle(fontSize: 12, color: Colors.red.shade400)),
                    onPressed: () {
                      final tid = int.tryParse(termine[index]['id']?.toString() ?? '');
                      if (tid != null) widget.apiService.deleteVersorgungsamtTermin(tid);
                      Navigator.pop(ctx);
                      _loadFromDBDedicated();
                    },
                  ),
                ]),
              ),
            ]),
          ),
        );
      }),
    );
  }

  void _addEintrag(BuildContext parentCtx, StateSetter setD, List<Map<String, dynamic>> eintraege, String eTyp, String terminDatum, String terminUhrzeit, VoidCallback onSave) {
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final betreffC = TextEditingController();
    final textC = TextEditingController();
    final isEmail = eTyp.startsWith('email');
    final eLabel = switch (eTyp) { 'email_eingang' => 'E-Mail Eingang', 'email_ausgang' => 'E-Mail Ausgang', 'telefonat' => 'Telefonat', 'dokument' => 'Dokument / Brief', _ => 'Notiz' };

    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        title: Text(eLabel),
        content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: datumC, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          if (isEmail || eTyp == 'dokument') ...[
            const SizedBox(height: 8),
            TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          ],
          const SizedBox(height: 8),
          TextField(controller: textC, maxLines: 6, decoration: InputDecoration(labelText: isEmail ? 'E-Mail Inhalt' : 'Text / Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton(onPressed: () async {
            await widget.apiService.saveVersorgungsamtEintrag({
              'user_id': widget.userId,
              'termin_datum': terminDatum,
              'termin_uhrzeit': terminUhrzeit,
              'eintrag_typ': eTyp,
              'datum': datumC.text.trim(),
              'betreff': betreffC.text.trim(),
              'inhalt': textC.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            onSave();
          }, child: const Text('Hinzufügen')),
        ],
      ),
    );
  }

  void _viewEintrag(BuildContext parentCtx, Map<String, dynamic> e, String label, MaterialColor color) {
    showDialog(
      context: parentCtx,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Row(children: [
          Icon(Icons.article, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: TextStyle(color: color.shade800))),
        ]),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.calendar_today, size: 12, color: Colors.grey.shade600),
                const SizedBox(width: 4),
                Text(e['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              ]),
            ),
            if ((e['betreff']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Betreff', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text(e['betreff'].toString(), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
            ],
            const SizedBox(height: 12),
            Text('Inhalt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(minHeight: 150),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
              child: SelectableText(
                (e['inhalt']?.toString() ?? e['text']?.toString() ?? '').isEmpty ? '(kein Inhalt)' : (e['inhalt'] ?? e['text']).toString(),
                style: TextStyle(fontSize: 13, height: 1.6, color: (e['inhalt']?.toString() ?? e['text']?.toString() ?? '').isEmpty ? Colors.grey.shade400 : Colors.black87),
              ),
            ),
          ])),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
      ),
    );
  }

  // ============ TAB 6: ANTRAG ============

  List<Map<String, dynamic>> _dbAntraege = [];
  bool _antraegeLoaded = false;

  Future<void> _loadAntraege() async {
    final r = await widget.apiService.listVersorgungsamtAntraege(widget.userId);
    if (!mounted) return;
    setState(() {
      if (r['success'] == true && r['data'] is List) _dbAntraege = (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _antraegeLoaded = true;
    });
  }

  Widget _buildAntragTab(Map<String, dynamic> data) {
    if (!_antraegeLoaded) { _loadAntraege(); return const Center(child: CircularProgressIndicator()); }
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Row(children: [
          Icon(Icons.description, size: 20, color: Colors.indigo.shade700),
          const SizedBox(width: 8),
          Text('Anträge (${_dbAntraege.length})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: () => _showNewAntragDialog(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Neuer Antrag'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo, foregroundColor: Colors.white),
          ),
        ]),
      ),
      Expanded(
        child: _dbAntraege.isEmpty
            ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.description, size: 48, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Anträge vorhanden', style: TextStyle(color: Colors.grey.shade500)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _dbAntraege.length,
                itemBuilder: (_, i) {
                  final a = _dbAntraege[i];
                  final methode = a['methode']?.toString() ?? '';
                  final methodeLabel = switch (methode) { 'online' => 'Online', 'postalisch' => 'Postalisch', 'persoenlich' => 'Persönlich', 'email' => 'Per E-Mail', _ => methode };
                  final status = a['status']?.toString() ?? '';
                  final statusColor = switch (status) { 'eingereicht' => Colors.orange, 'in_bearbeitung' => Colors.blue, 'genehmigt' => Colors.green, 'abgelehnt' => Colors.red, 'widerspruch' => Colors.purple, _ => Colors.grey };
                  return Card(
                    child: ListTile(
                      leading: Icon(status == 'genehmigt' ? Icons.check_circle : status == 'abgelehnt' ? Icons.cancel : Icons.hourglass_top, color: statusColor, size: 28),
                      title: Text('${a['datum'] ?? ''} — $methodeLabel${(a['aktenzeichen']?.toString() ?? '').isNotEmpty ? '  •  Az: ${a['aktenzeichen']}' : ''}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: Container(
                        margin: const EdgeInsets.only(top: 4),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
                        child: Text(status.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                      ),
                      onTap: () {
                        final aid = int.tryParse(a['id']?.toString() ?? '');
                        if (aid != null) _showAntragDetailDialog(aid, a);
                      },
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
                          final aid = int.tryParse(a['id']?.toString() ?? '');
                          if (aid != null) await widget.apiService.deleteVersorgungsamtAntrag(aid);
                          _loadAntraege();
                        }),
                        Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      ]),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _showNewAntragDialog() {
    final datumC = TextEditingController();
    final aktenzeichenC = TextEditingController(text: _joinAkt());
    String methode = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Antrag'),
      content: SizedBox(width: 460, child: Column(mainAxisSize: MainAxisSize.min, children: [
        _datePicker(ctx2, datumC, 'Datum der Antragstellung *', () => setD(() {})),
        const SizedBox(height: 12),
        TextField(controller: aktenzeichenC, decoration: InputDecoration(labelText: 'Aktenzeichen', prefixIcon: const Icon(Icons.folder, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 12),
        Text('Methode *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: [('online', 'Online', Icons.language), ('postalisch', 'Postalisch', Icons.local_post_office), ('persoenlich', 'Persönlich', Icons.person), ('email', 'Per E-Mail', Icons.email)].map((m) {
          final sel = methode == m.$1;
          return ChoiceChip(
            label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 14, color: sel ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.black87))]),
            selected: sel, selectedColor: Colors.indigo.shade600,
            onSelected: (_) => setD(() => methode = m.$1),
          );
        }).toList()),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          if (datumC.text.isEmpty || methode.isEmpty) return;
          await widget.apiService.saveVersorgungsamtAntrag(widget.userId, {'datum': datumC.text, 'aktenzeichen': aktenzeichenC.text.trim(), 'methode': methode, 'status': 'eingereicht'});
          if (ctx.mounted) Navigator.pop(ctx);
          _loadAntraege();
        }, child: const Text('Antrag stellen')),
      ],
    )));
  }

  void _showAntragDetailDialog(int antragId, Map<String, dynamic> antrag) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(width: 600, height: 560, child: _VaAntragDetailView(
          apiService: widget.apiService, antragId: antragId, antrag: antrag, userId: widget.userId,
          onChanged: () => _loadAntraege(),
        )),
      ),
    );
  }

  // ============ TAB 3: KORRESPONDENZ ============

  Widget _buildKorrespondenzTab(Map<String, dynamic> data) {
    final korr = _dbKorr;
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
                      subtitle: Text('${k['datum'] ?? ''} • ${richt.toUpperCase()}${methodLabel.isNotEmpty ? ' • $methodLabel' : ''}${docs > 0 ? ' • 📎 $docs' : ''}', style: const TextStyle(fontSize: 11)),
                      trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                      onTap: () => _showKorrDetailDialog(k, i, korr, data),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  void _showKorrDetailDialog(Map<String, dynamic> k, int index, List<Map<String, dynamic>> korr, Map<String, dynamic> data) {
    final isEin = (k['richtung']?.toString() ?? 'eingehend') == 'eingehend';
    final color = isEin ? Colors.green : Colors.blue;
    final methodLabel = {'post': 'Post', 'email': 'E-Mail', 'online': 'Online', 'persoenlich': 'Persönlich', 'fax': 'Fax'}[k['methode']?.toString() ?? ''] ?? k['methode']?.toString() ?? '';
    final docs = k['dokumente'] is List ? List<Map<String, dynamic>>.from((k['dokumente'] as List).whereType<Map>()) : <Map<String, dynamic>>[];

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(16),
        child: SizedBox(
          width: 540, height: 500,
          child: DefaultTabController(
            length: 2,
            child: Column(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: color.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
                child: Row(children: [
                  Icon(isEin ? Icons.inbox : Icons.outbox, color: Colors.white, size: 22),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(k['betreff']?.toString() ?? '', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                    Text('${k['datum'] ?? ''} • ${isEin ? 'Eingang' : 'Ausgang'} • $methodLabel', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ])),
                  IconButton(icon: const Icon(Icons.delete, color: Colors.white70, size: 20), onPressed: () {
                    setState(() => korr.removeAt(index));
                    data['korrespondenz'] = korr;
                    widget.saveData(type, data);
                    Navigator.pop(ctx);
                  }),
                  IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              TabBar(
                labelColor: color.shade700,
                indicatorColor: color.shade700,
                tabs: const [
                  Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
                  Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
                ],
              ),
              Expanded(child: TabBarView(children: [
                // Details tab
                SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8)),
                      child: Row(children: [
                        Icon(isEin ? Icons.inbox : Icons.outbox, size: 14, color: color.shade700),
                        const SizedBox(width: 6),
                        Text(isEin ? 'Eingang (vom Amt)' : 'Ausgang (ans Amt)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color.shade800)),
                        const Spacer(),
                        Text(methodLabel, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      ]),
                    ),
                    const SizedBox(height: 16),
                    Text('Betreff', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    Text('Inhalt / Zusammenfassung', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(minHeight: 120),
                      decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
                      child: SelectableText(
                        (k['inhalt']?.toString() ?? '').isEmpty ? '(kein Inhalt)' : k['inhalt'].toString(),
                        style: TextStyle(fontSize: 13, height: 1.5, color: (k['inhalt']?.toString() ?? '').isEmpty ? Colors.grey.shade400 : Colors.black87),
                      ),
                    ),
                  ]),
                ),
                // Dokumente tab
                StatefulBuilder(builder: (ctx2, setDocState) {
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        Expanded(child: Text('${docs.length} Dokumente', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
                        FilledButton.icon(
                          icon: const Icon(Icons.upload_file, size: 14),
                          label: const Text('Hochladen', style: TextStyle(fontSize: 11)),
                          style: FilledButton.styleFrom(backgroundColor: Colors.indigo.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                          onPressed: () async {
                            final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
                            if (result == null) return;
                            for (final f in result.files) {
                              if (f.path == null) continue;
                              try {
                                final res = await widget.apiService.uploadVersorgungsamtKorrDoc(
                                  userId: widget.userId,
                                  korrIndex: index,
                                  korrDatum: k['datum']?.toString() ?? '',
                                  filePath: f.path!,
                                  fileName: f.name,
                                );
                                if (res['success'] == true) {
                                  docs.add({'name': f.name, 'id': res['id']});
                                }
                              } catch (_) {}
                            }
                            k['dokumente'] = docs;
                            data['korrespondenz'] = korr;
                            widget.saveData(type, data);
                            setDocState(() {});
                            setState(() {});
                          },
                        ),
                      ]),
                    ),
                    Expanded(
                      child: docs.isEmpty
                          ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.folder_open, size: 48, color: Colors.grey.shade300),
                              const SizedBox(height: 6),
                              Text('Keine Dokumente', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                            ]))
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: docs.length,
                              itemBuilder: (_, di) {
                                final doc = docs[di];
                                final docId = int.tryParse(doc['id']?.toString() ?? '');
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 6),
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                                  child: Row(children: [
                                    Icon(Icons.description, size: 18, color: Colors.indigo.shade600),
                                    const SizedBox(width: 8),
                                    Expanded(child: Text(doc['name']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.indigo.shade700))),
                                    if (docId != null) ...[
                                      IconButton(
                                        icon: Icon(Icons.visibility, size: 16, color: Colors.indigo.shade600),
                                        onPressed: () async {
                                          try {
                                            final resp = await widget.apiService.downloadVersorgungsamtKorrDoc(docId);
                                            if (resp.statusCode == 200 && ctx2.mounted) {
                                              final dir = await getTemporaryDirectory();
                                              final file = File('${dir.path}/${doc['name']}');
                                              await file.writeAsBytes(resp.bodyBytes);
                                              if (ctx2.mounted) await FileViewerDialog.show(ctx2, file.path, doc['name']?.toString() ?? '');
                                            }
                                          } catch (e) {
                                            if (ctx2.mounted) ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                                          }
                                        },
                                        padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      ),
                                      IconButton(
                                        icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                                        onPressed: () async {
                                          await widget.apiService.deleteVersorgungsamtKorrDoc(docId);
                                          setDocState(() => docs.removeAt(di));
                                          k['dokumente'] = docs;
                                          data['korrespondenz'] = korr;
                                          widget.saveData(type, data);
                                          setState(() {});
                                        },
                                        padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                      ),
                                    ],
                                  ]),
                                );
                              },
                            ),
                    ),
                  ]);
                }),
              ])),
            ]),
          ),
        ),
      ),
    );
  }

  void _showKorrDialog(Map<String, dynamic> data) {
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final inhaltC = TextEditingController();
    String richt = 'eingehend';
    String methode = '';
    final dokumente = <Map<String, dynamic>>[];

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
                  final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
                  if (result == null) return;
                  for (final f in result.files) {
                    if (f.path == null) continue;
                    dokumente.add({'name': f.name, 'path': f.path!, 'size': f.size.toString()});
                    setD(() {});
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
            onPressed: () async {
              if (datumC.text.isEmpty || betreffC.text.isEmpty || methode.isEmpty) return;
              final korr = List<Map<String, dynamic>>.from(data['korrespondenz'] ?? []);
              final korrIndex = korr.length;
              // Upload files to server (encrypted)
              final uploadedDocs = <Map<String, dynamic>>[];
              for (final doc in dokumente) {
                if (doc['path'] == null) continue;
                try {
                  final res = await widget.apiService.uploadVersorgungsamtKorrDoc(
                    userId: widget.userId,
                    korrIndex: korrIndex,
                    korrDatum: datumC.text,
                    filePath: doc['path'],
                    fileName: doc['name'],
                  );
                  if (res['success'] == true) {
                    uploadedDocs.add({'name': doc['name'], 'id': res['id']});
                  }
                } catch (_) {}
              }
              korr.add({
                'datum': datumC.text,
                'richtung': richt,
                'methode': methode,
                'betreff': betreffC.text,
                'inhalt': inhaltC.text,
                'dokumente': uploadedDocs,
              });
              korr.sort((a, b) => (b['datum'] ?? '').toString().compareTo((a['datum'] ?? '').toString()));
              setState(() => data['korrespondenz'] = korr);
              widget.saveData(type, data);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Speichern'),
          ),
        ],
      )),
    );
  }

  // ============ TAB 4: SB-AUSWEIS ============

  // ============ TAB 7: WERTMARKE ============

  Widget _buildWertmarkeTab(Map<String, dynamic> data) {
    final user = widget.user;
    final nachname = user.nachname ?? '';
    final vorname = user.vorname ?? '';
    final fullName = '$vorname $nachname'.trim();
    final aktenzeichen = _joinAkt();
    String azFormatted = '';
    if (aktenzeichen.isNotEmpty) {
      final digits = aktenzeichen.replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 8) { azFormatted = '${digits.substring(0, 2)}/${digits.substring(2, 5)} ${digits.substring(5, 8)}'; }
      else { azFormatted = aktenzeichen; }
    }
    final wmAbMonat = data['wertmarke_ab_monat']?.toString() ?? '';
    final wmAbJahr = data['wertmarke_ab_jahr']?.toString() ?? '';
    final wmBisMonat = data['wertmarke_bis_monat']?.toString() ?? '';
    final wmBisJahr = data['wertmarke_bis_jahr']?.toString() ?? '';
    final wmAb = wmAbMonat.isNotEmpty && wmAbJahr.isNotEmpty ? '$wmAbMonat/$wmAbJahr' : '';
    final wmBis = wmBisMonat.isNotEmpty && wmBisJahr.isNotEmpty ? '$wmBisMonat/$wmBisJahr' : '';

    return StatefulBuilder(builder: (ctx, setLocal) {
      bool showBack = false;
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Wertmarke', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 4),
        Text('Tippen Sie auf die Karte um sie zu drehen', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),

        // ── CARD ──
        StatefulBuilder(builder: (_, setCard) {
          return GestureDetector(onTap: () => setCard(() => showBack = !showBack),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: !showBack
              // ── VORDERSEITE ──
              ? Container(key: const ValueKey('wm_front'), width: double.infinity, height: 200,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade400, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))]),
                child: Row(children: [
                  // Left side — logo + dates
                  Container(width: 120, padding: const EdgeInsets.all(12), color: Colors.amber.shade100,
                    child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Icon(Icons.directions_bus, size: 36, color: Colors.amber.shade800),
                      Icon(Icons.train, size: 24, color: Colors.amber.shade700),
                      const Spacer(),
                      if (wmAb.isNotEmpty) ...[
                        Text('Gültig ab:', style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
                        Text(wmAb, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                      ],
                      if (wmBis.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text('Gültig bis:', style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
                        Text(wmBis, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                      ],
                      const SizedBox(height: 6),
                      Text('Gültig in Verbindung\nmit dem gültigen\nAusweis', textAlign: TextAlign.center, style: TextStyle(fontSize: 7, color: Colors.grey.shade600, height: 1.3)),
                    ])),
                  // Right side — data
                  Expanded(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Beiblatt zum Ausweis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    Text('des Versorgungsamtes', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
                    const SizedBox(height: 10),
                    if (azFormatted.isNotEmpty) ...[
                      Text('AZ:', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                      Text(azFormatted, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber.shade900, letterSpacing: 1.0)),
                    ],
                    const SizedBox(height: 8),
                    Text('Name:', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
                    Text(fullName.isNotEmpty ? fullName : '—', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                  ]))),
                ]))
              // ── RÜCKSEITE (weiß) ──
              : Container(key: const ValueKey('wm_back'), width: double.infinity, height: 200,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white,
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))]),
                child: Center(child: Text('Rückseite', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)))),
          ));
        }),
        const SizedBox(height: 20),

        // ── SETTINGS ──
        Text('Wertmarke Einstellungen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: InkWell(
            onTap: () async {
              final p = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) { data['wertmarke_ab_monat'] = '${p.month}'.padLeft(2, '0'); data['wertmarke_ab_jahr'] = '${p.year}'; _db('gdb')['wertmarke_ab_monat'] = data['wertmarke_ab_monat']; _db('gdb')['wertmarke_ab_jahr'] = data['wertmarke_ab_jahr']; _saveAll(data); setLocal(() {}); }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.calendar_today, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gültig ab', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text(wmAb.isNotEmpty ? wmAb : '— wählen —', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: wmAb.isNotEmpty ? Colors.amber.shade900 : Colors.grey.shade400)),
                ]),
              ])),
          )),
          const SizedBox(width: 12),
          Expanded(child: InkWell(
            onTap: () async {
              final p = await showDatePicker(context: ctx, initialDate: DateTime.now().add(const Duration(days: 180)), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) { data['wertmarke_bis_monat'] = '${p.month}'.padLeft(2, '0'); data['wertmarke_bis_jahr'] = '${p.year}'; _db('gdb')['wertmarke_bis_monat'] = data['wertmarke_bis_monat']; _db('gdb')['wertmarke_bis_jahr'] = data['wertmarke_bis_jahr']; _saveAll(data); setLocal(() {}); }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [
                Icon(Icons.event, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gültig bis', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text(wmBis.isNotEmpty ? wmBis : '— wählen —', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: wmBis.isNotEmpty ? Colors.amber.shade900 : Colors.grey.shade400)),
                ]),
              ])),
          )),
        ]),
      ]));
    });
  }

  Widget _buildAusweisTab(Map<String, dynamic> data) {
    final merkzeichenDefs = [('g', 'G'), ('ag', 'aG'), ('b', 'B'), ('h', 'H'), ('rf', 'RF'), ('bl', 'Bl'), ('gl', 'Gl'), ('tbl', 'TBl')];
    final merkzeichenFull = [('g', 'G – Erhebliche Gehbehinderung'), ('ag', 'aG – Außergewöhnliche Gehbehinderung'), ('b', 'B – Begleitperson erforderlich'), ('h', 'H – Hilflos'), ('rf', 'RF – Rundfunkbeitragsermäßigung'), ('bl', 'Bl – Blind'), ('gl', 'Gl – Gehörlos'), ('tbl', 'TBl – Taubblind')];
    final activeMz = merkzeichenDefs.where((m) => data['merkzeichen_${m.$1}'] == true).map((m) => m.$2).toList();
    final user = widget.user;
    final nachname = user.nachname ?? '';
    final vorname = user.vorname ?? '';
    final gebDatum = user.geburtsdatum ?? '';
    final amtMap = data['selected_amt'] is Map ? data['selected_amt'] as Map : {};
    final amtName = amtMap['name']?.toString() ?? data['selected_amt_name']?.toString() ?? '';
    final aktenzeichen = _joinAkt().isNotEmpty ? _joinAkt() : _ausweisNrC.text;
    final gueltigAb = _ausweisAusgestelltC.text;
    final gueltigBis = _ausweisUnbefristet ? 'Unbefristet' : _ausweisGueltigBisC.text;
    final gdb = _gdbAktuell;

    return StatefulBuilder(builder: (ctx, setLocal) {
      bool showBack = false;
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Schwerbehindertenausweis', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 4),
        Text('Tippen Sie auf den Ausweis um ihn zu drehen', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),

        // ── CARD ──
        StatefulBuilder(builder: (_, setCard) {
          final hasB = data['merkzeichen_b'] == true;
          return GestureDetector(
            onTap: () => setCard(() => showBack = !showBack),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: !showBack
              // ── VORDERSEITE (Front) — matches official Muster 5 ──
              ? Container(key: const ValueKey('front'), width: double.infinity, height: 220,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade400),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 8, offset: const Offset(0, 4))]),
                child: Column(children: [
                  // Header — light green
                  Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(14, 8, 14, 4), color: const Color(0xFFD4E8C2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Schwerbehindertenausweis', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87, letterSpacing: -0.3)),
                      Text('The holder of this card is severely disabled.', style: TextStyle(fontSize: 9, color: Colors.black54)),
                    ])),
                  // Main body
                  Expanded(child: Row(children: [
                    // Left — Lichtbild (green)
                    Container(width: 90, color: const Color(0xFFD4E8C2), padding: const EdgeInsets.all(8),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Container(width: 65, height: 80, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(2), border: Border.all(color: Colors.grey.shade400)),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.person, size: 30, color: Colors.grey.shade400),
                            Text('Lichtbild', style: TextStyle(fontSize: 8, color: Colors.grey.shade500)),
                          ])),
                      ])),
                    // Center — B letter (green)
                    if (hasB) Container(width: 50, color: const Color(0xFFD4E8C2),
                      child: Center(child: Text('B', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: Colors.black87)))),
                    // Right half — personal data (orange/salmon when B, green when not)
                    Expanded(child: Container(color: hasB ? const Color(0xFFF5C5B3) : const Color(0xFFD4E8C2),
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.start, children: [
                        const SizedBox(height: 4),
                        Text(nachname.isNotEmpty ? nachname : 'Nachname', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(vorname.isNotEmpty ? vorname : 'Vorname', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 6),
                        Text('Geschäftszeichen: ${aktenzeichen.isNotEmpty ? aktenzeichen : "—"}', style: TextStyle(fontSize: 10, color: Colors.black87)),
                        if (hasB) ...[
                          const Spacer(),
                          Text('Die Berechtigung zur Mitnahme einer', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black87)),
                          Text('Begleitperson ist nachgewiesen', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.black87)),
                          const SizedBox(height: 4),
                        ],
                      ]))),
                  ])),
                  // Bottom bar
                  Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    color: const Color(0xFFD4E8C2),
                    child: Row(children: [
                      Text('Gültig bis: $gueltigBis', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const Spacer(),
                      // Braille dots placeholder
                      Row(children: List.generate(6, (i) => Container(width: 5, height: 5, margin: const EdgeInsets.all(1.5),
                        decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle)))),
                    ])),
                ]))
              // ── RÜCKSEITE (Back) — matches official Muster 5 back ──
              : Container(key: const ValueKey('back'), width: double.infinity, height: 220, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade400),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))]),
                child: Column(children: [
                  // Top half — salmon/pink
                  Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(10, 8, 10, 6), color: const Color(0xFFF5C5B3),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Merkzeichen row + GdB
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Merkzeichen label + 7 boxes
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Merkzeichen', style: TextStyle(fontSize: 9, color: Colors.black54)),
                          const SizedBox(height: 2),
                          Row(children: List.generate(7, (i) {
                            final mz = i < activeMz.length ? activeMz[i] : '';
                            return Container(width: 28, height: 28, margin: const EdgeInsets.only(right: 2),
                              decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black54)),
                              child: Center(child: Text(mz, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87))));
                          })),
                        ])),
                        // GdB box
                        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text('GdB', style: TextStyle(fontSize: 9, color: Colors.black54)),
                          const SizedBox(height: 2),
                          Container(width: 44, height: 28, decoration: BoxDecoration(color: Colors.white, border: Border.all(color: Colors.black54)),
                            child: Center(child: Text(gdb > 0 ? '$gdb' : '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)))),
                        ]),
                      ]),
                      const SizedBox(height: 6),
                      // Name
                      Text('Name', style: TextStyle(fontSize: 8, color: Colors.black54)),
                      Text(nachname.isNotEmpty ? nachname : '—', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 2),
                      // Vorname
                      Text('Vorname', style: TextStyle(fontSize: 8, color: Colors.black54)),
                      Text(vorname.isNotEmpty ? vorname : '—', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 2),
                      // Geburtsdatum
                      Text('Geburtsdatum', style: TextStyle(fontSize: 8, color: Colors.black54)),
                      Text(gebDatum.isNotEmpty ? gebDatum : '—', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ])),
                  // Bottom half — green
                  Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.fromLTRB(10, 6, 10, 6), color: const Color(0xFFD4E8C2),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('Ausstellungsbehörde / Geschäftszeichen:', style: TextStyle(fontSize: 8, color: Colors.black54)),
                      Text('${amtName.isNotEmpty ? amtName : "—"} / ${aktenzeichen.isNotEmpty ? aktenzeichen : "—"}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text('Gültig ab: ${gueltigAb.isNotEmpty ? gueltigAb : "—"}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.black87)),
                    ]))),
                ])),
          ));
        }),
        const SizedBox(height: 20),
        Text('Wertmarke', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
        const SizedBox(height: 4),
        Text('Tippen Sie auf die Karte um sie zu drehen', style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
        const SizedBox(height: 8),
        Builder(builder: (_) {
          final wmAbMonat = data['wertmarke_ab_monat']?.toString() ?? '';
          final wmAbJahr = data['wertmarke_ab_jahr']?.toString() ?? '';
          final wmBisMonat = data['wertmarke_bis_monat']?.toString() ?? '';
          final wmBisJahr = data['wertmarke_bis_jahr']?.toString() ?? '';
          final wmAb = wmAbMonat.isNotEmpty && wmAbJahr.isNotEmpty ? '$wmAbMonat/$wmAbJahr' : '';
          final wmBis = wmBisMonat.isNotEmpty && wmBisJahr.isNotEmpty ? '$wmBisMonat/$wmBisJahr' : '';
          final azRaw = aktenzeichen;
          String azFmt = '';
          if (azRaw.isNotEmpty) { final d = azRaw.replaceAll(RegExp(r'[^0-9]'), ''); azFmt = d.length >= 8 ? '${d.substring(0, 2)}/${d.substring(2, 5)} ${d.substring(5, 8)}' : azRaw; }
          return StatefulBuilder(builder: (_, setWm) {
            bool wmBack = false;
            return GestureDetector(onTap: () => setWm(() => wmBack = !wmBack),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: !wmBack
                ? Container(key: const ValueKey('wm2_front'), width: double.infinity, height: 180, clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.amber.shade50, border: Border.all(color: Colors.amber.shade400, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))]),
                  child: Row(children: [
                    Container(width: 110, padding: const EdgeInsets.all(10), color: Colors.amber.shade100,
                      child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
                        Icon(Icons.directions_bus, size: 30, color: Colors.amber.shade800),
                        Icon(Icons.train, size: 20, color: Colors.amber.shade700),
                        const Spacer(),
                        if (wmAb.isNotEmpty) ...[Text('Gültig ab:', style: TextStyle(fontSize: 8, color: Colors.grey.shade700)), Text(wmAb, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900))],
                        if (wmBis.isNotEmpty) ...[const SizedBox(height: 2), Text('Gültig bis:', style: TextStyle(fontSize: 8, color: Colors.grey.shade700)), Text(wmBis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900))],
                        const SizedBox(height: 4),
                        Text('Gültig in Verbindung\nmit dem gültigen\nAusweis', textAlign: TextAlign.center, style: TextStyle(fontSize: 6, color: Colors.grey.shade600, height: 1.3)),
                      ])),
                    Expanded(child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Beiblatt zum Ausweis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                      Text('des Versorgungsamtes', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.amber.shade800)),
                      const SizedBox(height: 8),
                      if (azFmt.isNotEmpty) ...[Text('AZ:', style: TextStyle(fontSize: 8, color: Colors.grey.shade600)), Text(azFmt, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade900, letterSpacing: 1.0))],
                      const SizedBox(height: 6),
                      Text('Name:', style: TextStyle(fontSize: 8, color: Colors.grey.shade600)),
                      Text('$vorname $nachname'.trim().isNotEmpty ? '$vorname $nachname'.trim() : '—', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.amber.shade900)),
                    ]))),
                  ]))
                : Container(key: const ValueKey('wm2_back'), width: double.infinity, height: 180,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.white, border: Border.all(color: Colors.grey.shade300, width: 2),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))]),
                  child: Center(child: Text('Rückseite', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)))),
            ));
          });
        }),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text('Alle Daten werden automatisch aus den Tabs Amt, GdB und Mitgliederprofil übernommen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ]));
    });
  }

  Widget _cardRow(String label, String value) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
      SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
      Expanded(child: Text(value.isNotEmpty ? value : '—', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: value.isNotEmpty ? Colors.green.shade900 : Colors.grey.shade400))),
    ]));
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
        const SizedBox(height: 12),
        Row(children: [
          ChoiceChip(label: const Text('Befristet', style: TextStyle(fontSize: 12)), selected: !_ausweisUnbefristet, selectedColor: Colors.orange.shade200,
            onSelected: (_) { setState(() => _ausweisUnbefristet = false); _saveAll(data); }),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Unbefristet', style: TextStyle(fontSize: 12)), selected: _ausweisUnbefristet, selectedColor: Colors.green.shade200,
            onSelected: (_) { setState(() => _ausweisUnbefristet = true); _saveAll(data); }),
          if (!_ausweisUnbefristet) ...[
            const SizedBox(width: 12),
            Expanded(child: _datePicker(context, _ausweisGueltigBisC, 'Gültig bis', () => _saveAll(data))),
          ],
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

        // ── MERKZEICHEN ──
        const SizedBox(height: 20),
        Text('Merkzeichen', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 4, children: [
          ('g', 'G – Gehbehinderung'), ('ag', 'aG – Außergewöhnliche Gehbehinderung'), ('b', 'B – Begleitperson'),
          ('h', 'H – Hilflos'), ('rf', 'RF – Rundfunkbeitragsermäßigung'), ('bl', 'Bl – Blind'), ('gl', 'Gl – Gehörlos'), ('tbl', 'TBl – Taubblind'),
        ].map((m) {
          final key = 'merkzeichen_${m.$1}'; final sel = data[key] == true || data[key] == 'true';
          return FilterChip(label: Text(m.$2, style: TextStyle(fontSize: 11, color: sel ? Colors.white : Colors.indigo.shade700)),
            selected: sel, selectedColor: Colors.indigo.shade600, backgroundColor: Colors.indigo.shade50, checkmarkColor: Colors.white,
            side: BorderSide(color: sel ? Colors.indigo.shade600 : Colors.indigo.shade200),
            onSelected: (v) { setState(() { data[key] = v; _currentData[key] = v; _db('gdb')[key] = v ? 'true' : 'false'; }); _saveAll(data); });
        }).toList()),

        // ── WERTMARKE GÜLTIGKEIT ──
        const SizedBox(height: 20),
        Text('Wertmarke Gültigkeit', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: InkWell(
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) { setState(() { data['wertmarke_ab_monat'] = '${p.month}'.padLeft(2, '0'); data['wertmarke_ab_jahr'] = '${p.year}'; _db('gdb')['wertmarke_ab_monat'] = data['wertmarke_ab_monat']; _db('gdb')['wertmarke_ab_jahr'] = data['wertmarke_ab_jahr']; }); _saveAll(data); }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [Icon(Icons.calendar_today, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gültig ab', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text((data['wertmarke_ab_monat']?.toString() ?? '').isNotEmpty ? '${data['wertmarke_ab_monat']}/${data['wertmarke_ab_jahr']}' : '— wählen —',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (data['wertmarke_ab_monat']?.toString() ?? '').isNotEmpty ? Colors.amber.shade900 : Colors.grey.shade400)),
                ])])),
          )),
          const SizedBox(width: 12),
          Expanded(child: InkWell(
            onTap: () async {
              final p = await showDatePicker(context: context, initialDate: DateTime.now().add(const Duration(days: 180)), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
              if (p != null) { setState(() { data['wertmarke_bis_monat'] = '${p.month}'.padLeft(2, '0'); data['wertmarke_bis_jahr'] = '${p.year}'; _db('gdb')['wertmarke_bis_monat'] = data['wertmarke_bis_monat']; _db('gdb')['wertmarke_bis_jahr'] = data['wertmarke_bis_jahr']; }); _saveAll(data); }
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
              child: Row(children: [Icon(Icons.event, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Gültig bis', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  Text((data['wertmarke_bis_monat']?.toString() ?? '').isNotEmpty ? '${data['wertmarke_bis_monat']}/${data['wertmarke_bis_jahr']}' : '— wählen —',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: (data['wertmarke_bis_monat']?.toString() ?? '').isNotEmpty ? Colors.amber.shade900 : Colors.grey.shade400)),
                ])])),
          )),
        ]),
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
    // Does the user qualify for erhöhter Pauschbetrag?
    final hasH = _gdbBenefitsQualifiesErhoeht();
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
          Text('Vorteile bei GdB $_gdbAktuell (Stand 2025/2026)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
        ]),
        const SizedBox(height: 8),
        ...benefits.map((b) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(b.startsWith('⚠') ? Icons.warning_amber : Icons.check_circle, size: 13, color: b.startsWith('⚠') ? Colors.orange.shade700 : color.shade600),
            const SizedBox(width: 6),
            Expanded(child: Text(b.replaceFirst('⚠ ', ''), style: const TextStyle(fontSize: 11, height: 1.35))),
          ]),
        )),
        if (hasH) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.amber.shade100, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade400)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.stars, size: 14, color: Colors.amber.shade800),
              const SizedBox(width: 6),
              Expanded(child: Text('Erhöhter Pauschbetrag: $_erhoehterPauschbetrag €/Jahr (wegen Merkzeichen H/Bl/TBl) — ersetzt den Standard-Pauschbetrag', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade900))),
            ]),
          ),
        ],
        const SizedBox(height: 4),
        Text('Quellen: familienratgeber.de, SGB IX (Stand 2026)', style: TextStyle(fontSize: 9, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
      ]),
    );
  }

  bool _gdbBenefitsQualifiesErhoeht() {
    final data = widget.getData(type);
    return data['merkzeichen_h'] == true || data['merkzeichen_bl'] == true || data['merkzeichen_tbl'] == true;
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

// ═══════════════════════════════════════════════════════
// VERSORGUNGSAMT ANTRAG DETAIL
// ═══════════════════════════════════════════════════════
class _VaAntragDetailView extends StatefulWidget {
  final ApiService apiService;
  final int antragId;
  final Map<String, dynamic> antrag;
  final int userId;
  final VoidCallback onChanged;
  const _VaAntragDetailView({required this.apiService, required this.antragId, required this.antrag, required this.userId, required this.onChanged});
  @override
  State<_VaAntragDetailView> createState() => _VaAntragDetailViewState();
}

class _VaAntragDetailViewState extends State<_VaAntragDetailView> {
  List<Map<String, dynamic>> _verlauf = [];
  List<Map<String, dynamic>> _docs = [];
  List<Map<String, dynamic>> _korr = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listVaAntragVerlauf(widget.antragId);
    final dR = await widget.apiService.listVaAntragDocs(widget.antragId);
    final kR = await widget.apiService.listVaAntragKorr(widget.antragId);
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.antrag;
    final status = a['status']?.toString() ?? 'eingereicht';
    final methode = {'online': 'Online', 'postalisch': 'Postalisch', 'persoenlich': 'Persönlich', 'email': 'Per E-Mail'}[a['methode']?.toString() ?? ''] ?? '';
    final isOk = status == 'genehmigt';
    return DefaultTabController(length: 5, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isOk ? Colors.green.shade700 : Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          const Icon(Icons.description, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Antrag vom ${a['datum'] ?? ''}', style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('$methode • ${status.replaceAll('_', ' ').toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.indigo.shade700, indicatorColor: Colors.indigo.shade700, isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
        Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
        Tab(icon: Icon(Icons.gavel, size: 18), text: 'Widerspruch'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildDetails(a), _buildDokumente(), _buildVerlauf(), _buildKorrespondenz(), _buildWiderspruch(a),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> a) {
    final bescheidDatum = a['bescheid_datum']?.toString() ?? '';
    final bescheidErhalten = a['bescheid_erhalten']?.toString() ?? '';
    final aid = widget.antragId;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Antrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      const SizedBox(height: 8),
      _dRow(Icons.calendar_today, 'Antragsdatum', a['datum']),
      _dRow(Icons.send, 'Methode', {'online': 'Online', 'postalisch': 'Postalisch', 'persoenlich': 'Persönlich', 'email': 'Per E-Mail'}[a['methode']?.toString() ?? '']),
      _dRow(Icons.flag, 'Status', a['status']?.toString().replaceAll('_', ' ').toUpperCase()),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_antrag_$aid', korrespondenzId: 0),
      const Divider(height: 20),
      Text('Bescheid', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      const SizedBox(height: 8),
      _datePickerRow(Icons.description, 'Bescheid-Datum', bescheidDatum, (date) async {
        a['bescheid_datum'] = date;
        await _saveAntragField(a, 'bescheid_datum', date);
      }),
      const SizedBox(height: 6),
      _datePickerRow(Icons.local_post_office, 'Erhalten per Post am', bescheidErhalten, (date) async {
        a['bescheid_erhalten'] = date;
        await _saveAntragField(a, 'bescheid_erhalten', date);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_bescheid_$aid', korrespondenzId: 1),
      const SizedBox(height: 8),
      Text('Zuständige/r Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.indigo.shade600)),
      const SizedBox(height: 6),
      _buildSbSection(a, 'bescheid_sb'),
      if (bescheidErhalten.isNotEmpty) ...[
        const SizedBox(height: 4),
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
          child: Row(children: [
            Icon(Icons.timer, size: 16, color: Colors.amber.shade700), const SizedBox(width: 6),
            Expanded(child: Text('Widerspruchsfrist: 1 Monat ab $bescheidErhalten (§ 84 SGG)', style: TextStyle(fontSize: 11, color: Colors.amber.shade800))),
          ])),
      ],
      const Divider(height: 20),
      Text('Widerspruch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
      const SizedBox(height: 8),
      _datePickerRow(Icons.gavel, 'Widerspruch eingelegt am', a['widerspruch_datum']?.toString() ?? '', (date) async {
        a['widerspruch_datum'] = date;
        await _saveAntragField(a, 'widerspruch_datum', date);
      }),
      const SizedBox(height: 6),
      _methodeRow('Widerspruch per', a['widerspruch_methode']?.toString() ?? '', (m) async {
        a['widerspruch_methode'] = m;
        await _saveAntragField(a, 'widerspruch_methode', m);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_widerspruch_$aid', korrespondenzId: 2),
      const SizedBox(height: 6),
      _datePickerRow(Icons.folder_open, 'Akteneinsicht beantragt am', a['akteneinsicht_datum']?.toString() ?? '', (date) async {
        a['akteneinsicht_datum'] = date;
        await _saveAntragField(a, 'akteneinsicht_datum', date);
      }),
      const SizedBox(height: 6),
      _methodeRow('Akteneinsicht per', a['akteneinsicht_methode']?.toString() ?? '', (m) async {
        a['akteneinsicht_methode'] = m;
        await _saveAntragField(a, 'akteneinsicht_methode', m);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_akteneinsicht_$aid', korrespondenzId: 3),
      const SizedBox(height: 6),
      _datePickerRow(Icons.inbox, 'Akteneinsicht erhalten am', a['akteneinsicht_erhalten']?.toString() ?? '', (date) async {
        a['akteneinsicht_erhalten'] = date;
        await _saveAntragField(a, 'akteneinsicht_erhalten', date);
      }),
      const SizedBox(height: 6),
      _methodeRow('Akten erhalten per', a['akteneinsicht_erhalten_methode']?.toString() ?? '', (m) async {
        a['akteneinsicht_erhalten_methode'] = m;
        await _saveAntragField(a, 'akteneinsicht_erhalten_methode', m);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_akten_erhalten_$aid', korrespondenzId: 4),
      const Divider(height: 20),
      Text('Eingangsbestätigung Widerspruch vom Amt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 8),
      _datePickerRow(Icons.mark_email_read, 'Eingangsbestätigung vom', a['eingangsbestaetigung_datum']?.toString() ?? '', (date) async {
        a['eingangsbestaetigung_datum'] = date;
        await _saveAntragField(a, 'eingangsbestaetigung_datum', date);
      }),
      const SizedBox(height: 6),
      _datePickerRow(Icons.local_post_office, 'Erhalten per Post am', a['eingangsbestaetigung_erhalten']?.toString() ?? '', (date) async {
        a['eingangsbestaetigung_erhalten'] = date;
        await _saveAntragField(a, 'eingangsbestaetigung_erhalten', date);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_eingangsbestaetigung_$aid', korrespondenzId: 5),
      const SizedBox(height: 12),
      Text('Zuständige/r Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal.shade600)),
      const SizedBox(height: 6),
      _buildSachbearbeiterSection(a),
      if ((a['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(a['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  final Map<String, bool> _sbEditing = {};

  Widget _buildSachbearbeiterSection(Map<String, dynamic> a) => _buildSbSection(a, 'wb_sb');

  Widget _buildSbSection(Map<String, dynamic> a, String prefix) {
    final anrede = a['${prefix}_anrede']?.toString() ?? '';
    final name = a['${prefix}_name']?.toString() ?? '';
    final telefon = a['${prefix}_telefon']?.toString() ?? '';
    final email = a['${prefix}_email']?.toString() ?? '';
    final hasData = name.isNotEmpty;
    final editing = _sbEditing[prefix] == true;
    final readOnly = hasData && !editing;

    if (readOnly) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade300)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.person, size: 16, color: Colors.grey.shade700), const SizedBox(width: 6),
            Expanded(child: Text('${anrede.isNotEmpty ? '$anrede ' : ''}$name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade900))),
            IconButton(icon: Icon(Icons.edit, size: 16, color: Colors.grey.shade500), tooltip: 'Bearbeiten', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: () => setState(() => _sbEditing[prefix] = true)),
          ]),
          if (telefon.isNotEmpty) _dRow(Icons.phone, 'Telefon', telefon),
          if (email.isNotEmpty) _dRow(Icons.email, 'E-Mail', email),
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, children: ['Frau', 'Herr'].map((an) => ChoiceChip(
        label: Text(an, style: TextStyle(fontSize: 11, color: anrede == an ? Colors.white : Colors.black87)),
        selected: anrede == an, selectedColor: Colors.indigo, visualDensity: VisualDensity.compact,
        onSelected: (_) { a['${prefix}_anrede'] = an; _saveAntragField(a, '${prefix}_anrede', an); },
      )).toList()),
      const SizedBox(height: 6),
      TextField(controller: TextEditingController(text: name), onChanged: (v) => a['${prefix}_name'] = v,
        decoration: InputDecoration(labelText: 'Name', prefixIcon: const Icon(Icons.person, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 6),
      Row(children: [
        Expanded(child: TextField(controller: TextEditingController(text: telefon), onChanged: (v) => a['${prefix}_telefon'] = v,
          decoration: InputDecoration(labelText: 'Telefon', prefixIcon: const Icon(Icons.phone, size: 14), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 12))),
        const SizedBox(width: 6),
        Expanded(child: TextField(controller: TextEditingController(text: email), onChanged: (v) => a['${prefix}_email'] = v,
          decoration: InputDecoration(labelText: 'E-Mail', prefixIcon: const Icon(Icons.email, size: 14), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), style: const TextStyle(fontSize: 12))),
      ]),
      const SizedBox(height: 6),
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(
        icon: const Icon(Icons.save, size: 14), label: const Text('Speichern', style: TextStyle(fontSize: 11)),
        style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
        onPressed: () async {
          await _saveAntragField(a, '${prefix}_name', a['${prefix}_name'] ?? '');
          setState(() => _sbEditing[prefix] = false);
        },
      )),
    ]);
  }

  Future<void> _saveAntragField(Map<String, dynamic> a, String field, String value) async {
    await widget.apiService.saveVersorgungsamtAntrag(widget.userId, {
      'id': widget.antragId, 'datum': a['datum'], 'methode': a['methode'], 'status': a['status'],
      'bescheid_datum': a['bescheid_datum'] ?? '', 'bescheid_erhalten': a['bescheid_erhalten'] ?? '',
      'widerspruch_datum': a['widerspruch_datum'] ?? '', 'widerspruch_methode': a['widerspruch_methode'] ?? '',
      'akteneinsicht_datum': a['akteneinsicht_datum'] ?? '', 'akteneinsicht_methode': a['akteneinsicht_methode'] ?? '',
      'akteneinsicht_erhalten': a['akteneinsicht_erhalten'] ?? '', 'akteneinsicht_erhalten_methode': a['akteneinsicht_erhalten_methode'] ?? '',
      'eingangsbestaetigung_datum': a['eingangsbestaetigung_datum'] ?? '', 'eingangsbestaetigung_erhalten': a['eingangsbestaetigung_erhalten'] ?? '',
      'wb_sb_anrede': a['wb_sb_anrede'] ?? '', 'wb_sb_name': a['wb_sb_name'] ?? '', 'wb_sb_telefon': a['wb_sb_telefon'] ?? '', 'wb_sb_email': a['wb_sb_email'] ?? '',
      'bescheid_sb_anrede': a['bescheid_sb_anrede'] ?? '', 'bescheid_sb_name': a['bescheid_sb_name'] ?? '', 'bescheid_sb_telefon': a['bescheid_sb_telefon'] ?? '', 'bescheid_sb_email': a['bescheid_sb_email'] ?? '',
    });
    setState(() {});
  }

  Widget _methodeRow(String label, String value, Function(String) onChanged) {
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(Icons.send, size: 16, color: value.isEmpty ? Colors.grey.shade400 : Colors.indigo.shade600), const SizedBox(width: 8),
      SizedBox(width: 150, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
      Expanded(child: Wrap(spacing: 6, children: [('online', 'Online'), ('post', 'Post'), ('fax', 'Fax'), ('persoenlich', 'Persönlich'), ('email', 'E-Mail')].map((m) => ChoiceChip(
        label: Text(m.$2, style: TextStyle(fontSize: 10, color: value == m.$1 ? Colors.white : Colors.black87)),
        selected: value == m.$1, selectedColor: Colors.indigo,
        onSelected: (_) => onChanged(m.$1),
        visualDensity: VisualDensity.compact,
      )).toList())),
    ]));
  }

  DateTime _addMonths(DateTime d, int months) {
    var y = d.year; var m = d.month + months;
    while (m > 12) { y++; m -= 12; }
    var day = d.day;
    final maxDay = DateTime(y, m + 1, 0).day;
    if (day > maxDay) day = maxDay;
    var result = DateTime(y, m, day);
    while (result.weekday == DateTime.saturday || result.weekday == DateTime.sunday) result = result.add(const Duration(days: 1));
    return result;
  }

  Widget _datePickerRow(IconData icon, String label, String value, Function(String) onPicked) {
    return InkWell(
      onTap: () async {
        final p = await showDatePicker(context: context, initialDate: DateTime.tryParse(value) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
        if (p != null) onPicked('${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
      },
      child: Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
        Icon(icon, size: 16, color: value.isEmpty ? Colors.grey.shade400 : Colors.indigo.shade600), const SizedBox(width: 8),
        SizedBox(width: 150, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
        Expanded(child: Text(value.isEmpty ? 'Datum eintragen...' : value, style: TextStyle(fontSize: 13, color: value.isEmpty ? Colors.grey.shade400 : Colors.black87, fontStyle: value.isEmpty ? FontStyle.italic : FontStyle.normal))),
        Icon(Icons.edit_calendar, size: 16, color: Colors.indigo.shade400),
      ])),
    );
  }

  Widget _dRow(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? ''; if (s.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
    ]));
  }

  Widget _buildDokumente() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 12, 16, 8), child: Row(children: [
        Icon(Icons.folder, size: 20, color: Colors.green.shade700), const SizedBox(width: 8),
        Expanded(child: Text('Unterlagen (${_docs.length})', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        ElevatedButton.icon(onPressed: _uploadDoc, icon: const Icon(Icons.upload_file, size: 16), label: const Text('Hochladen', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white)),
      ])),
      Expanded(child: _docs.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.cloud_upload, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8), Text('Keine Unterlagen', style: TextStyle(color: Colors.grey.shade500))]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16), itemCount: _docs.length, itemBuilder: (_, i) {
            final d = _docs[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
              child: Row(children: [
                Icon(Icons.attach_file, size: 18, color: Colors.green.shade700), const SizedBox(width: 8),
                Expanded(child: Text(d['datei_name']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
                IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600), onPressed: () async {
                  try { final resp = await widget.apiService.downloadVaAntragDoc(d['id'] as int); if (resp.statusCode == 200 && mounted) { final dir = await getTemporaryDirectory(); final file = File('${dir.path}/${d['datei_name']}'); await file.writeAsBytes(resp.bodyBytes); if (mounted) await FileViewerDialog.show(context, file.path, d['datei_name']?.toString() ?? ''); }} catch (_) {}
                }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                IconButton(icon: Icon(Icons.download, size: 18, color: Colors.green.shade700), onPressed: () async {
                  try { final resp = await widget.apiService.downloadVaAntragDoc(d['id'] as int); if (resp.statusCode == 200 && mounted) { final dir = await getTemporaryDirectory(); final file = File('${dir.path}/${d['datei_name']}'); await file.writeAsBytes(resp.bodyBytes); await OpenFilex.open(file.path); }} catch (_) {}
                }, padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteVaAntragDoc(d['id'] as int); _load(); },
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
              ]));
          })),
    ]);
  }

  Future<void> _uploadDoc() async {
    final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files.where((f) => f.path != null)) {
      await widget.apiService.uploadVaAntragDoc(antragId: widget.antragId, filePath: file.path!, fileName: file.name);
    }
    _load();
  }

  Widget _buildVerlauf() {
    // Sort chronologically old → new
    final sorted = List<Map<String, dynamic>>.from(_verlauf);
    sorted.sort((a, b) => (a['datum']?.toString() ?? '').compareTo(b['datum']?.toString() ?? ''));
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${sorted.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addVerlauf),
      ])),
      Expanded(child: sorted.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: sorted.length, itemBuilder: (_, i) {
            final e = sorted[i];
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
              child: Row(children: [
                Icon(Icons.circle, size: 10, color: Colors.indigo.shade400), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(e['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                  if ((e['status']?.toString() ?? '').isNotEmpty) Container(margin: const EdgeInsets.only(top: 2), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(6)),
                    child: Text(e['status'].toString().replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
                  if ((e['notiz']?.toString() ?? '').isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(e['notiz'].toString(), style: const TextStyle(fontSize: 12))),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteVaAntragVerlauf(e['id'] as int); _load(); widget.onChanged(); },
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24)),
              ]));
          })),
    ]);
  }

  void _addVerlauf() {
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController(); String status = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setD) => AlertDialog(title: const Text('Verlauf-Eintrag'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
          final p = await showDatePicker(context: ctx, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
          if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }))), const SizedBox(height: 8),
        Wrap(spacing: 6, children: ['eingereicht', 'in_bearbeitung', 'genehmigt', 'abgelehnt', 'widerspruch'].map((s) => ChoiceChip(
          label: Text(s.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 10, color: status == s ? Colors.white : Colors.black87)),
          selected: status == s, selectedColor: Colors.indigo, onSelected: (_) => setD(() => status = s))).toList()), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.addVaAntragVerlauf(widget.antragId, {'datum': datumC.text, 'status': status, 'notiz': notizC.text});
          if (status.isNotEmpty) await widget.apiService.saveVersorgungsamtAntrag(widget.userId, {'id': widget.antragId, 'status': status, 'datum': widget.antrag['datum'], 'methode': widget.antrag['methode']});
          if (ctx.mounted) Navigator.pop(ctx); _load(); widget.onChanged();
        }, child: const Text('Hinzufügen'))],
    )));
  }

  Widget _buildKorrespondenz() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${_korr.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.call_received, size: 14), label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('eingang')),
        const SizedBox(width: 6),
        FilledButton.icon(icon: const Icon(Icons.call_made, size: 14), label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorr('ausgang')),
      ])),
      Expanded(child: _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i]; final isEin = k['richtung'] == 'eingang';
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEin ? Colors.green.shade200 : Colors.blue.shade200)),
              child: Row(children: [
                Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: isEin ? Colors.green.shade700 : Colors.blue.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: isEin ? Colors.green.shade800 : Colors.blue.shade800)),
                  Row(children: [
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon({'email': Icons.email, 'post': Icons.local_post_office, 'fax': Icons.fax, 'persoenlich': Icons.person}[k['methode']] ?? Icons.send, size: 12, color: Colors.grey.shade500),
                      const SizedBox(width: 2),
                      Text({'email': 'E-Mail', 'post': 'Post', 'fax': 'Fax', 'persoenlich': 'Persönlich'}[k['methode']?.toString()] ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ]),
                  if (k['id'] != null) Padding(padding: const EdgeInsets.only(top: 4),
                    child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'versorgungsamt_antrag', korrespondenzId: int.tryParse(k['id'].toString()) ?? 0)),
                ])),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteVaAntragKorr(k['id'] as int); _load(); },
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              ]));
          })),
    ]);
  }

  void _addKorr(String richtung) {
    final betreffC = TextEditingController();
    final datumC = TextEditingController(text: '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().day.toString().padLeft(2, '0')}');
    final notizC = TextEditingController();
    String methode = '';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(title: Text(richtung == 'eingang' ? 'Eingang' : 'Ausgang'),
      content: SizedBox(width: 440, child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: const OutlineInputBorder(), suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
          final p = await showDatePicker(context: ctx2, initialDate: DateTime.tryParse(datumC.text) ?? DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de'));
          if (p != null) setD(() => datumC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}');
        }))), const SizedBox(height: 8),
        Text('Methode', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        Wrap(spacing: 6, children: [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.local_post_office), ('fax', 'Fax', Icons.fax), ('persoenlich', 'Persönlich', Icons.person)].map((m) => ChoiceChip(
          label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 14, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 11, color: methode == m.$1 ? Colors.white : Colors.black87))]),
          selected: methode == m.$1, selectedColor: Colors.indigo, onSelected: (_) => setD(() => methode = m.$1),
        )).toList()),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())), const SizedBox(height: 8),
        TextField(controller: notizC, maxLines: 3, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          await widget.apiService.saveVaAntragKorr(widget.antragId, {'richtung': richtung, 'methode': methode, 'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'notiz': notizC.text.trim()});
          if (ctx.mounted) Navigator.pop(ctx); _load();
        }, child: const Text('Speichern'))],
    )));
  }

  // Widerspruch GdB — chronologisch basiert auf Verlauf-Einträgen
  Widget _buildWiderspruch(Map<String, dynamic> a) {
    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

    // Parse Verlauf entries by type
    Map<String, dynamic>? findEntry(String keyword) => _verlauf.where((e) => (e['notiz']?.toString() ?? '').toLowerCase().contains(keyword)).firstOrNull;
    DateTime? parseEntry(Map<String, dynamic>? e) => e != null ? DateTime.tryParse(e['datum']?.toString() ?? '') : null;

    // First check bescheid_erhalten field on antrag, then fallback to Verlauf
    final bescheidErhaltenDirekt = DateTime.tryParse(a['bescheid_erhalten']?.toString() ?? '');
    final bescheidEntry = bescheidErhaltenDirekt == null ? findEntry('bescheid') : null;
    final bescheidDatum = bescheidErhaltenDirekt ?? parseEntry(bescheidEntry);
    final widerspruchVorbereitet = findEntry('vorbereitet');
    final widerspruchVorbereitetDatum = parseEntry(widerspruchVorbereitet);
    // Widerspruch: direct from antrag fields first, then Verlauf
    final widerspruchDirekt = DateTime.tryParse(a['widerspruch_datum']?.toString() ?? '');
    final widerspruchGesendet = widerspruchDirekt == null ? (findEntry('widerspruch eingelegt') ?? findEntry('widerspruch gesendet') ?? findEntry('widerspruch per')) : null;
    final widerspruchGesendetDatum = widerspruchDirekt ?? parseEntry(widerspruchGesendet);
    final widerspruchMethode = a['widerspruch_methode']?.toString() ?? widerspruchGesendet?['notiz']?.toString() ?? '';
    final begruendungEntry = findEntry('begründung');
    final begruendungDatum = parseEntry(begruendungEntry);
    final widerspruchsbescheidEntry = findEntry('widerspruchsbescheid');
    final widerspruchsbescheidDatum = parseEntry(widerspruchsbescheidEntry);
    final antragDatum = DateTime.tryParse(a['datum']?.toString() ?? '');

    // Frist: 1 Monat ab Bescheid-Zustellung
    final fristStart = bescheidDatum;
    final fristEnde = fristStart != null ? _addMonths(fristStart, 1) : null;
    final heute = DateTime.now();
    final heute0 = DateTime(heute.year, heute.month, heute.day);
    final restTage = fristEnde != null ? fristEnde.difference(heute0).inDays : null;
    final abgelaufen = fristEnde != null && heute0.isAfter(fristEnde);
    final hatW = widerspruchGesendetDatum != null;

    // Begründungsfrist: +1 Monat nach Widerspruch (Frist für endgültige Begründung)
    final begruendungFrist = widerspruchGesendetDatum != null ? _addMonths(widerspruchGesendetDatum, 1) : null;
    // Bearbeitungsfrist Amt: 3 Monate nach Widerspruch
    final bearbeitungFrist = widerspruchGesendetDatum != null ? _addMonths(widerspruchGesendetDatum, 3) : null;

    final statusColor = hatW ? Colors.blue : bescheidDatum == null ? Colors.grey : abgelaufen == true ? Colors.red : (restTage != null && restTage <= 7) ? Colors.orange : Colors.green;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Status Banner
      Container(width: double.infinity, padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: statusColor.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: statusColor.shade300, width: 2)),
        child: Row(children: [
          Icon(hatW ? Icons.gavel : bescheidDatum == null ? Icons.info : abgelaufen == true ? Icons.cancel : Icons.timer, size: 28, color: statusColor.shade700),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(hatW ? 'Widerspruch eingelegt${widerspruchGesendetDatum != null ? ' am ${fmt(widerspruchGesendetDatum)}' : ''}'
                : bescheidDatum == null ? 'Bescheid-Datum fehlt — bitte im Verlauf eintragen'
                : abgelaufen == true ? 'Frist abgelaufen seit ${-(restTage ?? 0)} Tagen'
                : '${restTage ?? 0} Tage verbleibend',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: statusColor.shade800)),
            if (fristEnde != null && !hatW && abgelaufen != true) Text('Fristende: ${fmt(fristEnde)}', style: TextStyle(fontSize: 12, color: statusColor.shade700)),
          ])),
        ]),
      ),
      const SizedBox(height: 16),

      // Chronologie
      Text('Chronologie', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
      const SizedBox(height: 12),

      // 1. Antrag gestellt
      if (antragDatum != null)
        _tlItem(Icons.send, 'Antrag gestellt', fmt(antragDatum), Colors.indigo, true, subtitle: 'Antrag auf GdB-Feststellung beim Versorgungsamt'),

      // 2. Bescheid erhalten
      if (bescheidDatum != null)
        _tlItem(Icons.local_post_office, 'Bescheid per Post erhalten', fmt(bescheidDatum), Colors.teal, true, subtitle: bescheidEntry?['notiz']?.toString())
      else
        _tlItem(Icons.help_outline, 'Bescheid erhalten — Datum fehlt', '?', Colors.grey, true, subtitle: 'Im Verlauf eintragen: "Bescheid erhalten am ..." mit Datum'),

      // 3. Fristende
      if (fristEnde != null)
        _tlItem(abgelaufen == true && !hatW ? Icons.cancel : Icons.timer, 'Widerspruchsfrist endet', fmt(fristEnde), abgelaufen == true && !hatW ? Colors.red : Colors.orange, true, subtitle: '§ 84 SGG: 1 Monat nach Bekanntgabe'),

      // 4. Widerspruch vorbereitet
      if (widerspruchVorbereitetDatum != null)
        _tlItem(Icons.edit_document, 'Widerspruch vorbereitet', fmt(widerspruchVorbereitetDatum), Colors.purple, true, subtitle: widerspruchVorbereitet?['notiz']?.toString()),

      // 5. Widerspruch gesendet
      if (widerspruchGesendetDatum != null)
        _tlItem(Icons.gavel, 'Widerspruch eingelegt${widerspruchMethode.isNotEmpty ? ' per ${{'online': 'Online', 'post': 'Post', 'fax': 'Fax', 'persoenlich': 'persönlich', 'email': 'E-Mail'}[widerspruchMethode] ?? widerspruchMethode}' : ''}', fmt(widerspruchGesendetDatum), Colors.blue, true),

      // 5b. Akteneinsicht
      if ((a['akteneinsicht_datum']?.toString() ?? '').isNotEmpty && DateTime.tryParse(a['akteneinsicht_datum'].toString()) != null)
        _tlItem(Icons.folder_open, 'Akteneinsicht beantragt${(a['akteneinsicht_methode']?.toString() ?? '').isNotEmpty ? ' per ${{'online': 'Online', 'post': 'Post', 'fax': 'Fax', 'persoenlich': 'persönlich', 'email': 'E-Mail'}[a['akteneinsicht_methode']] ?? a['akteneinsicht_methode']}' : ''}', fmt(DateTime.parse(a['akteneinsicht_datum'].toString())), Colors.purple, true),

      // 5c. Akteneinsicht erhalten
      if ((a['akteneinsicht_erhalten']?.toString() ?? '').isNotEmpty && DateTime.tryParse(a['akteneinsicht_erhalten'].toString()) != null)
        _tlItem(Icons.inbox, 'Akten erhalten${(a['akteneinsicht_erhalten_methode']?.toString() ?? '').isNotEmpty ? ' per ${{'online': 'Online', 'post': 'Post', 'fax': 'Fax', 'persoenlich': 'persönlich', 'email': 'E-Mail'}[a['akteneinsicht_erhalten_methode']] ?? a['akteneinsicht_erhalten_methode']}' : ''}', fmt(DateTime.parse(a['akteneinsicht_erhalten'].toString())), Colors.purple, true),

      // 5d. Eingangsbestätigung
      if ((a['eingangsbestaetigung_datum']?.toString() ?? '').isNotEmpty) ...[
        if (DateTime.tryParse(a['eingangsbestaetigung_datum'].toString()) != null)
          _tlItem(Icons.mark_email_read, 'Eingangsbestätigung vom Amt', fmt(DateTime.parse(a['eingangsbestaetigung_datum'].toString())), Colors.teal, true),
        if ((a['eingangsbestaetigung_erhalten']?.toString() ?? '').isNotEmpty && DateTime.tryParse(a['eingangsbestaetigung_erhalten'].toString()) != null)
          _tlItem(Icons.local_post_office, 'Eingangsbestätigung erhalten', fmt(DateTime.parse(a['eingangsbestaetigung_erhalten'].toString())), Colors.teal, true),
      ],

      // 6. Begründung nachgereicht
      if (begruendungDatum != null)
        _tlItem(Icons.article, 'Begründung nachgereicht', fmt(begruendungDatum), Colors.indigo, true, subtitle: begruendungEntry?['notiz']?.toString())
      else if (hatW && begruendungFrist != null)
        _tlItem(Icons.article, 'Begründung nachreichen bis', fmt(begruendungFrist), Colors.orange, true, subtitle: 'Begründung kann bis 1 Monat nach Widerspruch nachgereicht werden'),

      // 7. Bearbeitungsfrist Amt
      if (hatW && bearbeitungFrist != null && widerspruchsbescheidEntry == null)
        _tlItem(Icons.hourglass_top, 'Bearbeitungsfrist Amt endet', fmt(bearbeitungFrist), Colors.grey, true, subtitle: '3 Monate — danach Untätigkeitsklage möglich (§ 88 SGG)'),

      // 8. Widerspruchsbescheid
      if (widerspruchsbescheidDatum != null)
        _tlItem(Icons.description, 'Widerspruchsbescheid erhalten', fmt(widerspruchsbescheidDatum), Colors.deepPurple, true, subtitle: widerspruchsbescheidEntry?['notiz']?.toString()),

      // Heute
      if (!hatW && bescheidDatum != null && abgelaufen != true)
        _tlItem(Icons.today, 'Heute', fmt(heute0), Colors.blue, false, subtitle: '${restTage ?? 0} Tage verbleibend'),

      const SizedBox(height: 16),

      // Hinweise
      if (hatW && widerspruchsbescheidEntry == null)
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.blue.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.lightbulb, size: 18, color: Colors.blue.shade700), const SizedBox(width: 8),
              Text('Nächste Schritte', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800))]),
            const SizedBox(height: 6),
            if (begruendungEntry == null) Text('• Begründung nachreichen (ärztliche Befunde, Atteste)', style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
            Text('• Versorgungsamt hat 3 Monate Bearbeitungszeit', style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
            Text('• Nach 3 Monaten ohne Antwort: Untätigkeitsklage (§ 88 SGG)', style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
            Text('• Bei Ablehnung: Klage beim Sozialgericht (1 Monat Frist)', style: TextStyle(fontSize: 11, color: Colors.blue.shade900)),
          ]),
        ),

      // Verlauf Einträge als Tipp
      if (bescheidDatum == null) ...[
        const SizedBox(height: 12),
        Container(width: double.infinity, padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [Icon(Icons.info, size: 18, color: Colors.amber.shade700), const SizedBox(width: 8),
              Text('So funktioniert es', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.amber.shade800))]),
            const SizedBox(height: 6),
            Text('1. Im Verlauf-Tab eintragen: "Bescheid erhalten" mit Datum der Post-Zustellung', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('2. Widerspruch vorbereiten (Verlauf: "Widerspruch vorbereitet")', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('3. Widerspruch senden (Verlauf: "Widerspruch eingelegt per Post/Fax")', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('4. Begründung nachreichen (Verlauf: "Begründung nachgereicht")', style: TextStyle(fontSize: 11, color: Colors.amber.shade900)),
            Text('\nDie Chronologie wird automatisch aus dem Verlauf erstellt.', style: TextStyle(fontSize: 10, color: Colors.amber.shade700, fontStyle: FontStyle.italic)),
          ]),
        ),
      ],

      const SizedBox(height: 16),
      // Rechtsgrundlage
      Container(width: double.infinity, padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Rechtsgrundlage', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          _lawRow('§ 84 SGG', 'Widerspruchsfrist: 1 Monat nach Bekanntgabe des Bescheids'),
          _lawRow('§ 84 SGG', 'Begründung: kann bis 1 Monat nach Widerspruch nachgereicht werden'),
          _lawRow('§ 88 SGG', 'Untätigkeitsklage: nach 3 Monaten ohne Antwort vom Amt'),
          _lawRow('§ 87 SGG', 'Klagefrist: 1 Monat nach Zustellung Widerspruchsbescheid'),
          _lawRow('§ 66 SGG', 'Ohne Rechtsbehelfsbelehrung im Bescheid: Frist 1 Jahr'),
        ]),
      ),
    ]));
  }

  Widget _tlItem(IconData icon, String title, String date, Color color, bool hasLine, {String? subtitle}) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Column(children: [
        Container(width: 32, height: 32, decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle, border: Border.all(color: color, width: 2)),
          child: Icon(icon, size: 16, color: color)),
        if (hasLine) Container(width: 2, height: 28, color: Colors.grey.shade300),
      ]),
      const SizedBox(width: 12),
      Expanded(child: Padding(padding: const EdgeInsets.only(bottom: 8), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [Expanded(child: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color))), Text(date, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700))]),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text(subtitle, style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ]))),
    ]);
  }

  Widget _lawRow(String p, String t) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
        child: Text(p, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
    ]));
  }
}
