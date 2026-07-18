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

/// Antragsarten des Versorgungsamts (Schwerbehindertenrecht SGB IX +
/// soziales Entschädigungsrecht SGB XIV). (key, langes Label, kurzes Label)
const List<(String, String, String)> kVaAntragsarten = [
  ('erstantrag', 'Erstantrag (Feststellung GdB, § 152 SGB IX)', 'Erstantrag'),
  ('neufeststellung', 'Neufeststellung / Verschlimmerung (GdB-Änderung)', 'Neufeststellung'),
  ('ausweis_verlaengerung', 'Verlängerung Schwerbehindertenausweis', 'Ausweis-Verlängerung'),
  ('ausweis_neu', 'Neuausstellung Ausweis (Verlust/Foto/Daten)', 'Ausweis-Neuausstellung'),
  ('wertmarke', 'Beiblatt mit Wertmarke (ÖPNV)', 'Wertmarke (ÖPNV)'),
  ('parkausweis', 'Parkausweis (aG / Bl)', 'Parkausweis'),
  ('merkzeichen', 'Merkzeichen-Antrag', 'Merkzeichen'),
  ('soziale_entschaedigung', 'Soziale Entschädigung (SGB XIV / OEG)', 'Soziale Entschädigung'),
  ('landesblindengeld', 'Landesblindengeld', 'Landesblindengeld'),
  ('sonstiges', 'Sonstiger Antrag', 'Sonstiges'),
];

String vaAntragsartLabel(String? key) {
  if (key == null || key.isEmpty) return '';
  for (final a in kVaAntragsarten) { if (a.$1 == key) return a.$2; }
  return key;
}

String vaAntragsartShort(String? key) {
  if (key == null || key.isEmpty) return 'Antrag';
  for (final a in kVaAntragsarten) { if (a.$1 == key) return a.$3; }
  return key;
}

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

  // Wertmarke flip state (front/back)
  bool _wm2Back = false;

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
  bool _dbLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadFromDBDedicated();
  }

  Future<void> _loadFromDBDedicated() async {
    try {
      final dR = await widget.apiService.getVersorgungsamtData(widget.userId);
      if (!mounted) return;
      if (dR['success'] == true && dR['data'] is Map) {
        _dbData = {};
        (dR['data'] as Map).forEach((k, v) { if (v is Map) _dbData[k.toString()] = Map<String, dynamic>.from(v); });
      }
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
      length: 4,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.indigo.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.indigo.shade700,
            isScrollable: true,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: ((_dbData['amt'] ?? {})['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.account_balance, size: 16), const SizedBox(width: 4), const Text('Amt')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: ((_dbData['ausweis'] ?? {})['ausweis_nr']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.badge, size: 16), const SizedBox(width: 4), const Text('SB-Ausweis')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: ((_dbData['gdb'] ?? {})['gdb_aktuell'] != null && (_dbData['gdb'] ?? {})['gdb_aktuell'] != 0) ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.accessible, size: 16), const SizedBox(width: 4), const Text('GdB')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _dbAntraege.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.description, size: 16), const SizedBox(width: 4), const Text('Antrag')])),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildAmtTab(data),
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
                      title: Text(vaAntragsartShort(a['art']?.toString()), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const SizedBox(height: 2),
                        Text('${a['datum'] ?? ''} — $methodeLabel${(a['aktenzeichen']?.toString() ?? '').isNotEmpty ? '  •  Az: ${a['aktenzeichen']}' : ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        Align(alignment: Alignment.centerLeft, child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(color: statusColor.shade100, borderRadius: BorderRadius.circular(8)),
                          child: Text(status.replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor.shade800)),
                        )),
                      ]),
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
    final now = DateTime.now();
    final datumC = TextEditingController(text: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}');
    final aktenzeichenC = TextEditingController(text: _joinAkt());
    String methode = '';
    String art = '';
    String? err;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: const Text('Neuer Antrag'),
      content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Align(alignment: Alignment.centerLeft, child: Text('Antragsart *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          initialValue: art.isEmpty ? null : art,
          isExpanded: true,
          decoration: InputDecoration(hintText: '— Art des Antrags wählen —', prefixIcon: const Icon(Icons.category, size: 18), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: kVaAntragsarten.map((a) => DropdownMenuItem(value: a.$1, child: Text(a.$2, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => art = v ?? ''),
        ),
        const SizedBox(height: 12),
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
        if (err != null) ...[
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: Row(children: [
            Icon(Icons.error_outline, size: 16, color: Colors.red.shade700), const SizedBox(width: 6),
            Expanded(child: Text(err!, style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w600))),
          ])),
        ],
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          final missing = <String>[
            if (art.isEmpty) 'Antragsart',
            if (datumC.text.isEmpty) 'Datum',
            if (methode.isEmpty) 'Methode',
          ];
          if (missing.isNotEmpty) { setD(() => err = 'Bitte ausfüllen: ${missing.join(', ')}'); return; }
          final res = await widget.apiService.saveVersorgungsamtAntrag(widget.userId, {'art': art, 'datum': datumC.text, 'aktenzeichen': aktenzeichenC.text.trim(), 'methode': methode, 'status': 'eingereicht'});
          if (res['success'] == true) {
            if (ctx.mounted) Navigator.pop(ctx);
            _loadAntraege();
          } else {
            setD(() => err = 'Speichern fehlgeschlagen: ${res['message'] ?? res['error'] ?? 'Serverfehler'}');
          }
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
        child: SizedBox(width: MediaQuery.of(context).size.width * 0.85, height: MediaQuery.of(context).size.height * 0.85, child: _VaAntragDetailView(
          apiService: widget.apiService, antragId: antragId, antrag: antrag, userId: widget.userId,
          onChanged: () => _loadAntraege(),
        )),
      ),
    );
  }

  // ============ TAB 3: KORRESPONDENZ ============


  Widget _buildAusweisTab(Map<String, dynamic> data) {
    final merkzeichenDefs = [('g', 'G'), ('ag', 'aG'), ('b', 'B'), ('h', 'H'), ('rf', 'RF'), ('bl', 'Bl'), ('gl', 'Gl'), ('tbl', 'TBl')];
    final allMz = merkzeichenDefs.where((m) => data['merkzeichen_${m.$1}'] == true || data['merkzeichen_${m.$1}'] == 'true').map((m) => m.$2).toList();
    final activeMz = allMz.where((m) => m != 'B').toList();
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
          final hasB = data['merkzeichen_b'] == true || data['merkzeichen_b'] == 'true';
          return GestureDetector(
            onTap: () => setCard(() => showBack = !showBack),
            child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: !showBack
              // ── VORDERSEITE (Front) ──
              ? Container(key: const ValueKey('front'), width: double.infinity, height: 300,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Stack(children: [
                  Row(children: [
                    Expanded(child: Container(color: const Color(0xFFD5EACC))),
                    if (hasB) Expanded(child: Container(color: const Color(0xFFF0C4B0))),
                  ]),
                  Column(children: [
                    // Title — full width
                    Padding(padding: const EdgeInsets.fromLTRB(14, 12, 14, 0), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Schwerbehindertenausweis', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.black87)),
                      Text('The holder of this card is severely disabled.', style: TextStyle(fontSize: 11, color: Colors.black54, fontStyle: FontStyle.italic)),
                    ])),
                    const SizedBox(height: 8),
                    // Body — Lichtbild+B left, data right
                    Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // Green side: Lichtbild + B
                      Padding(padding: const EdgeInsets.only(left: 14), child: Column(children: [
                        Container(width: 75, height: 90, decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade500), color: Colors.white),
                          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.person, size: 32, color: Colors.grey.shade400),
                            Text('Lichtbild', style: TextStyle(fontSize: 8, color: Colors.grey.shade500)),
                          ])),
                        if (hasB) const SizedBox(height: 4),
                        if (hasB) const Text('B', style: TextStyle(fontSize: 48, fontWeight: FontWeight.w900, color: Colors.black87)),
                      ])),
                      const SizedBox(width: 16),
                      // Salmon side: Name data
                      Expanded(child: Padding(padding: const EdgeInsets.only(right: 14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(nachname.isNotEmpty ? nachname : '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
                        const SizedBox(height: 4),
                        Text(vorname.isNotEmpty ? vorname : '—', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
                        const SizedBox(height: 10),
                        Text('Geschäftszeichen: ${aktenzeichen.isNotEmpty ? aktenzeichen : "—"}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                        if (hasB) ...[
                          const Spacer(),
                          const Text('Die Berechtigung zur Mitnahme einer\nBegleitperson ist nachgewiesen', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: Colors.black87, fontStyle: FontStyle.italic, height: 1.3)),
                        ],
                      ]))),
                    ])),
                    // Footer — on green
                    Padding(padding: const EdgeInsets.fromLTRB(14, 4, 14, 10), child: Row(children: [
                      Text('Gültig bis: ${gueltigBis.isNotEmpty ? gueltigBis : "—"}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87)),
                      const Spacer(),
                      Row(children: List.generate(6, (i) => Container(width: 5, height: 5, margin: const EdgeInsets.all(1.5),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle)))),
                    ])),
                  ]),
                ]))
              // ── RÜCKSEITE (Back) — Stack: top salmon bottom green ──
              : Container(key: const ValueKey('back'), width: double.infinity, height: 300, clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.grey.shade400),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))]),
                child: Stack(children: [
                  // Background — left salmon, right green
                  Row(children: [
                    Expanded(child: Container(color: hasB ? const Color(0xFFF0C4B0) : const Color(0xFFD5EACC))),
                    Expanded(child: Container(color: const Color(0xFFD5EACC))),
                  ]),
                  // Text overlay
                  Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    // Chenare: Merkzeichen (7 boxes) + GdB box — full width
                    Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      // Chenar 1: Merkzeichen
                      Expanded(child: Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.black45)),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(padding: const EdgeInsets.fromLTRB(4, 2, 4, 0), child: Text('Merkzeichen', style: TextStyle(fontSize: 9, color: Colors.black54))),
                          Row(children: List.generate(7, (i) {
                            final mz = i < activeMz.length ? activeMz[i] : '';
                            return Expanded(child: Container(height: 34,
                              decoration: BoxDecoration(border: Border(right: i < 6 ? const BorderSide(color: Colors.black26) : BorderSide.none)),
                              child: Center(child: mz.isNotEmpty
                                ? Text(mz, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87))
                                : Container(width: 1, height: 20, color: Colors.black26))));
                          })),
                        ]))),
                      // Chenar 2: GdB
                      Container(
                        decoration: BoxDecoration(border: Border.all(color: Colors.black45)),
                        child: Column(children: [
                          Padding(padding: const EdgeInsets.fromLTRB(8, 2, 8, 0), child: Text('GdB', style: TextStyle(fontSize: 9, color: Colors.black54))),
                          SizedBox(width: 56, height: 34,
                            child: Center(child: Text(gdb > 0 ? '$gdb' : '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)))),
                        ])),
                    ]),
                    const SizedBox(height: 8),
                    // Name data — on salmon
                    Text('Name', style: TextStyle(fontSize: 9, color: Colors.black45)),
                    Text(nachname.isNotEmpty ? nachname : '—', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: Colors.black87)),
                    Text('Vorname', style: TextStyle(fontSize: 9, color: Colors.black45)),
                    Text(vorname.isNotEmpty ? vorname : '—', style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.black87)),
                    Text('Geburtsdatum', style: TextStyle(fontSize: 9, color: Colors.black45)),
                    Text(gebDatum.isNotEmpty ? gebDatum : '—', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const Spacer(),
                    // Ausstellungsbehörde — starts on salmon, crosses to green
                    Text('Ausstellungsbehörde / Geschäftszeichen:', style: TextStyle(fontSize: 9, color: Colors.black45)),
                    Text('${amtName.isNotEmpty ? amtName : "—"} / ${aktenzeichen.isNotEmpty ? aktenzeichen : "—"}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text('Gültig ab: ${gueltigAb.isNotEmpty ? gueltigAb : "—"}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: Colors.black87)),
                  ])),
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
          return GestureDetector(onTap: () => setState(() => _wm2Back = !_wm2Back),
              child: AnimatedSwitcher(duration: const Duration(milliseconds: 400), child: !_wm2Back
                ? Container(key: const ValueKey('wm2_front'), width: double.infinity, height: 200, clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: const Color(0xFFF5F0EB),
                      border: Border.all(color: Colors.grey.shade400),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 4))]),
                  child: Row(children: [
                    // Left — text
                    Expanded(flex: 3, child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 8, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Beiblatt zum Ausweis', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black87)),
                      const Text('des Versorgungsamtes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.black87)),
                      const SizedBox(height: 10),
                      Text('Az.: ${azFmt.isNotEmpty ? azFmt : aktenzeichen.isNotEmpty ? aktenzeichen : "—"}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      const SizedBox(height: 4),
                      Text('Name: ${'$vorname $nachname'.trim().isNotEmpty ? '$vorname $nachname'.trim() : "—"}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                      const Spacer(),
                      Text('Gilt nur in Verbindung mit dem\ngültigen Ausweis', style: TextStyle(fontSize: 8, color: Colors.black54, height: 1.3)),
                    ]))),
                    // Right — stamp area
                    Container(width: 90, color: const Color(0xFFF5F0EB),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        if (wmAb.isNotEmpty) ...[
                          Text('Gültig ab:', style: TextStyle(fontSize: 8, color: Colors.black54)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), margin: const EdgeInsets.only(bottom: 6),
                            decoration: BoxDecoration(border: Border.all(color: Colors.green.shade400), color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text(wmAb, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
                        ],
                        if (wmBis.isNotEmpty) ...[
                          Text('Gültig bis:', style: TextStyle(fontSize: 8, color: Colors.black54)),
                          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(border: Border.all(color: Colors.green.shade400), color: Colors.green.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text(wmBis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
                        ],
                      ])),
                  ]))
                : Container(key: const ValueKey('wm2_back'), width: double.infinity, height: 200,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(10), color: Colors.white, border: Border.all(color: Colors.grey.shade300),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 8, offset: const Offset(0, 4))]),
                  child: Center(child: Text('Rückseite', style: TextStyle(fontSize: 14, color: Colors.grey.shade400)))),
            ));
        }),
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text('Alle Daten werden automatisch aus den Tabs Amt, GdB und Mitgliederprofil übernommen.', style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ]));
    });
  }

  // ============ TAB 5: GDB ============

  Widget _buildGdbTab(Map<String, dynamic> data) {

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
              initialValue: _gdbAktuell,
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
  List<Map<String, dynamic>> _termine = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final vR = await widget.apiService.listVaAntragVerlauf(widget.antragId);
    final dR = await widget.apiService.listVaAntragDocs(widget.antragId);
    final kR = await widget.apiService.listVaAntragKorr(widget.antragId);
    if (!mounted) return;
    final tR = await widget.apiService.listVersorgungsamtTermine(widget.userId);
    if (!mounted) return;
    setState(() {
      if (vR['success'] == true && vR['data'] is List) _verlauf = (vR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (dR['success'] == true && dR['data'] is List) _docs = (dR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (kR['success'] == true && kR['data'] is List) _korr = (kR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      if (tR['success'] == true && tR['data'] is List) _termine = (tR['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.antrag;
    final status = a['status']?.toString() ?? 'eingereicht';
    final methode = {'online': 'Online', 'postalisch': 'Postalisch', 'persoenlich': 'Persönlich', 'email': 'Per E-Mail'}[a['methode']?.toString() ?? ''] ?? '';
    final isOk = status == 'genehmigt';
    return DefaultTabController(length: 7, child: Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(color: isOk ? Colors.green.shade700 : Colors.indigo.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(14))),
        child: Row(children: [
          const Icon(Icons.description, color: Colors.white, size: 22), const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(vaAntragsartShort(a['art']?.toString()), style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
            Text('Antrag vom ${a['datum'] ?? ''} • $methode • ${status.replaceAll('_', ' ').toUpperCase()}', style: const TextStyle(color: Colors.white70, fontSize: 11)),
          ])),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
        ]),
      ),
      TabBar(labelColor: Colors.indigo.shade700, indicatorColor: Colors.indigo.shade700, isScrollable: true, tabs: const [
        Tab(icon: Icon(Icons.timeline, size: 18), text: 'Verlauf'),
        Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
        Tab(icon: Icon(Icons.calendar_month, size: 18), text: 'Termine'),
        Tab(icon: Icon(Icons.description, size: 18), text: 'Bescheid'),
        Tab(icon: Icon(Icons.folder, size: 18), text: 'Unterlagen'),
        Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
        Tab(icon: Icon(Icons.gavel, size: 18), text: 'Widerspruch'),
      ]),
      Expanded(child: !_loaded ? const Center(child: CircularProgressIndicator()) : TabBarView(children: [
        _buildVerlauf(), _buildDetails(a), _buildAntragTermine(), _buildBescheid(a), _buildDokumente(), _buildKorrespondenz(), _buildWiderspruch(a),
      ])),
    ]));
  }

  Widget _buildDetails(Map<String, dynamic> a) {
    final aid = widget.antragId;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Antrag', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      const SizedBox(height: 8),
      Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(children: [
        Icon(Icons.category, size: 16, color: (a['art']?.toString() ?? '').isEmpty ? Colors.grey.shade400 : Colors.indigo.shade600), const SizedBox(width: 8),
        SizedBox(width: 150, child: Text('Antragsart', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600))),
        Expanded(child: DropdownButton<String>(
          value: (a['art']?.toString().isNotEmpty ?? false) && kVaAntragsarten.any((e) => e.$1 == a['art']) ? a['art'].toString() : null,
          isExpanded: true, isDense: true, underline: const SizedBox.shrink(),
          hint: Text('— wählen —', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          items: kVaAntragsarten.map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) { if (v != null) _saveAntragField(a, 'art', v); },
        )),
      ])),
      _dRow(Icons.calendar_today, 'Antragsdatum', a['datum']),
      _dRow(Icons.send, 'Methode', {'online': 'Online', 'postalisch': 'Postalisch', 'persoenlich': 'Persönlich', 'email': 'Per E-Mail'}[a['methode']?.toString() ?? '']),
      _dRow(Icons.flag, 'Status', a['status']?.toString().replaceAll('_', ' ').toUpperCase()),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_antrag_$aid', korrespondenzId: 0),
      if ((a['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 8),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.yellow.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text(a['notiz'].toString(), style: const TextStyle(fontSize: 12))),
      ],
    ]));
  }

  Widget _buildBescheid(Map<String, dynamic> a) {
    final bescheidDatum = a['bescheid_datum']?.toString() ?? '';
    final bescheidErhalten = a['bescheid_erhalten']?.toString() ?? '';
    final aid = widget.antragId;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Bescheid', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
      const SizedBox(height: 12),
      _datePickerRow(Icons.description, 'Bescheid-Datum', bescheidDatum, (date) async {
        a['bescheid_datum'] = date;
        await _saveAntragField(a, 'bescheid_datum', date);
      }),
      const SizedBox(height: 8),
      _datePickerRow(Icons.local_post_office, 'Erhalten per Post am', bescheidErhalten, (date) async {
        a['bescheid_erhalten'] = date;
        await _saveAntragField(a, 'bescheid_erhalten', date);
      }),
      const SizedBox(height: 12),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_bescheid_$aid', korrespondenzId: 1),
      const SizedBox(height: 16),
      Text('Zuständige/r Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.teal.shade600)),
      const SizedBox(height: 6),
      _buildSbSection(a, 'bescheid_sb'),
      if (bescheidErhalten.isNotEmpty) ...[
        const SizedBox(height: 12),
        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
          child: Row(children: [
            Icon(Icons.timer, size: 16, color: Colors.amber.shade700), const SizedBox(width: 6),
            Expanded(child: Text('Widerspruchsfrist: 1 Monat ab $bescheidErhalten (§ 84 SGG)', style: TextStyle(fontSize: 11, color: Colors.amber.shade800))),
          ])),
      ],
    ]));
  }

  Widget _buildAntragTermine() {
    return FutureBuilder<Map<String, dynamic>>(
      future: widget.apiService.listVersorgungsamtTermine(widget.userId),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final termine = (snap.data?['data'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        return Column(children: [
          Padding(padding: const EdgeInsets.all(12), child: Row(children: [
            Text('Termine (${termine.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
            const Spacer(),
            FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
              onPressed: () async {
                final datumC = TextEditingController();
                final uhrzeitC = TextEditingController();
                final notizC = TextEditingController();
                await showDialog(context: ctx, builder: (dCtx) => AlertDialog(
                  title: const Text('Neuer Termin', style: TextStyle(fontSize: 15)),
                  content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      onTap: () async { final d = await showDatePicker(context: dCtx, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'; }),
                    const SizedBox(height: 8),
                    TextField(controller: uhrzeitC, decoration: InputDecoration(labelText: 'Uhrzeit', hintText: '10:00', isDense: true, prefixIcon: const Icon(Icons.access_time, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                    const SizedBox(height: 8),
                    TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                  ])),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('Abbrechen')),
                    FilledButton(onPressed: () async {
                      await widget.apiService.saveVersorgungsamtTermin(widget.userId, {'datum': datumC.text, 'uhrzeit': uhrzeitC.text, 'notiz': notizC.text});
                      if (dCtx.mounted) Navigator.pop(dCtx);
                    }, child: const Text('Speichern')),
                  ],
                ));
                setState(() {});
              }),
          ])),
          Expanded(child: termine.isEmpty
            ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade400)))
            : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: termine.length, itemBuilder: (_, i) {
                final t = termine[i];
                final onorat = (t['onorat'] is int ? t['onorat'] : int.tryParse(t['onorat']?.toString() ?? '0') ?? 0) == 1;
                final tColor = onorat ? Colors.green : Colors.indigo;
                return Card(child: ListTile(
                  onTap: () => _showTerminDetail(t),
                  leading: Icon(onorat ? Icons.check_circle : Icons.calendar_month, color: tColor.shade600),
                  title: Text('${t['datum'] ?? ''} ${t['uhrzeit'] ?? ''}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: tColor.shade800)),
                  subtitle: Row(children: [
                    if (t['notiz']?.toString().isNotEmpty == true) Expanded(child: Text(t['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                    if ((t['methode']?.toString() ?? '').isNotEmpty) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(6)),
                      child: Text(t['methode'].toString(), style: TextStyle(fontSize: 9, color: Colors.purple.shade700))),
                    if (onorat) Container(margin: const EdgeInsets.only(left: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(6)),
                      child: Text('Onorat', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
                  ]),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                    IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async {
                      final tid = t['id'];
                      if (tid != null) await widget.apiService.deleteVersorgungsamtTermin(tid is int ? tid : int.parse(tid.toString()));
                      setState(() {});
                    }),
                  ]),
                ));
              })),
        ]);
      },
    );
  }

  void _showTerminDetail(Map<String, dynamic> t) {
    final tid = t['id'] is int ? t['id'] as int : int.tryParse(t['id'].toString()) ?? 0;
    String methode = t['methode']?.toString() ?? '';
    bool onorat = (t['onorat'] is int ? t['onorat'] : int.tryParse(t['onorat']?.toString() ?? '0') ?? 0) == 1;
    final onoratDatumC = TextEditingController(text: t['onorat_datum']?.toString() ?? '');
    bool saved = false;

    showDialog(context: context, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(32),
      child: ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(
        width: MediaQuery.of(ctx).size.width * 0.65,
        height: MediaQuery.of(ctx).size.height * 0.65,
        child: DefaultTabController(length: 2, child: StatefulBuilder(builder: (ctx2, setDlg) => Column(children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: Colors.indigo.shade50),
            child: Row(children: [
              Icon(Icons.calendar_month, size: 22, color: Colors.indigo.shade700),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${t['datum'] ?? ''} — ${t['uhrzeit'] ?? ''}', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                if ((t['notiz']?.toString() ?? '').isNotEmpty) Text(t['notiz'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ])),
              IconButton(icon: const Icon(Icons.close), onPressed: () { if (saved) setState(() {}); Navigator.pop(ctx); }),
            ]),
          ),
          TabBar(labelColor: Colors.indigo.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.indigo.shade700, tabs: const [
            Tab(icon: Icon(Icons.info, size: 16), text: 'Details'),
            Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
          ]),
          Expanded(child: TabBarView(children: [
            // === DETAILS ===
            SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Art des Termins', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: ['Online', 'Persönlich', 'Telefon'].map((m) => ChoiceChip(
                label: Text(m), selected: methode == m, selectedColor: Colors.indigo.shade100,
                onSelected: (_) => setDlg(() => methode = m),
              )).toList()),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: onorat ? Colors.green.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: onorat ? Colors.green.shade200 : Colors.orange.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(onorat ? Icons.check_circle : Icons.schedule, size: 18, color: onorat ? Colors.green.shade700 : Colors.orange.shade700),
                    const SizedBox(width: 8),
                    Text(onorat ? 'Termin wurde wahrgenommen' : 'Termin noch offen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: onorat ? Colors.green.shade800 : Colors.orange.shade800)),
                  ]),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    title: const Text('Termin onorat (wahrgenommen)', style: TextStyle(fontSize: 13)),
                    value: onorat, dense: true, contentPadding: EdgeInsets.zero,
                    activeThumbColor: Colors.green,
                    onChanged: (v) => setDlg(() => onorat = v),
                  ),
                  if (onorat) ...[
                    const SizedBox(height: 8),
                    TextField(controller: onoratDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Onorat am (Datum)', isDense: true, prefixIcon: const Icon(Icons.event_available, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                      onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) setDlg(() => onoratDatumC.text = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}'); }),
                  ],
                ]),
              ),
              const SizedBox(height: 16),
              Align(alignment: Alignment.centerRight, child: FilledButton.icon(
                onPressed: () async {
                  await widget.apiService.saveVersorgungsamtTermin(widget.userId, {
                    'id': tid, 'datum': t['datum'], 'uhrzeit': t['uhrzeit'], 'notiz': t['notiz'] ?? '',
                    'methode': methode, 'onorat': onorat ? 1 : 0, 'onorat_datum': onoratDatumC.text,
                  });
                  saved = true;
                  if (ctx2.mounted) ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green, duration: Duration(seconds: 1)));
                },
                icon: const Icon(Icons.save, size: 16), label: const Text('Speichern', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
              )),
            ])),
            // === KORRESPONDENZ ===
            _TerminKorrTab(apiService: widget.apiService, terminId: tid),
          ])),
        ]))),
      )),
    ));
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

  /// Builds the COMPLETE antrag record so a partial edit never wipes other
  /// columns (the PHP UPDATE rewrites every column from the payload).
  Map<String, dynamic> _fullAntragPayload(Map<String, dynamic> a) => {
    'id': widget.antragId, 'art': a['art'] ?? '', 'datum': a['datum'], 'methode': a['methode'], 'status': a['status'],
    'notiz': a['notiz'] ?? '',
    'bescheid_datum': a['bescheid_datum'] ?? '', 'bescheid_erhalten': a['bescheid_erhalten'] ?? '',
    'widerspruch_datum': a['widerspruch_datum'] ?? '', 'widerspruch_methode': a['widerspruch_methode'] ?? '',
    'widerspruch_vorbereitet': a['widerspruch_vorbereitet'] ?? '', 'widerspruch_geliefert': a['widerspruch_geliefert'] ?? '', 'widerspruch_lieferung_methode': a['widerspruch_lieferung_methode'] ?? '',
    'widerspruch_eingang_bestaetigt_datum': a['widerspruch_eingang_bestaetigt_datum'] ?? '', 'widerspruch_eingang_bestaetigt_methode': a['widerspruch_eingang_bestaetigt_methode'] ?? '',
    'akteneinsicht_datum': a['akteneinsicht_datum'] ?? '', 'akteneinsicht_methode': a['akteneinsicht_methode'] ?? '',
    'akteneinsicht_erhalten': a['akteneinsicht_erhalten'] ?? '', 'akteneinsicht_erhalten_methode': a['akteneinsicht_erhalten_methode'] ?? '',
    'eingangsbestaetigung_datum': a['eingangsbestaetigung_datum'] ?? '', 'eingangsbestaetigung_erhalten': a['eingangsbestaetigung_erhalten'] ?? '',
    'wb_sb_anrede': a['wb_sb_anrede'] ?? '', 'wb_sb_name': a['wb_sb_name'] ?? '', 'wb_sb_telefon': a['wb_sb_telefon'] ?? '', 'wb_sb_email': a['wb_sb_email'] ?? '',
    'bescheid_sb_anrede': a['bescheid_sb_anrede'] ?? '', 'bescheid_sb_name': a['bescheid_sb_name'] ?? '', 'bescheid_sb_telefon': a['bescheid_sb_telefon'] ?? '', 'bescheid_sb_email': a['bescheid_sb_email'] ?? '',
  };

  Future<void> _saveAntragField(Map<String, dynamic> a, String field, String value) async {
    a[field] = value;
    await widget.apiService.saveVersorgungsamtAntrag(widget.userId, _fullAntragPayload(a));
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
    final result = await FilePickerHelper.pickFiles(type: FileType.any, allowMultiple: true);
    if (result == null || result.files.isEmpty) return;
    for (final file in result.files.where((f) => f.path != null)) {
      await widget.apiService.uploadVaAntragDoc(antragId: widget.antragId, filePath: file.path!, fileName: file.name);
    }
    _load();
  }

  Widget _buildVerlauf() {
    final a = widget.antrag;
    String fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    DateTime? parse(String? s) => (s != null && s.isNotEmpty) ? DateTime.tryParse(s) : null;

    final antragDatum = parse(a['datum']?.toString());
    final bescheidDatum = parse(a['bescheid_datum']?.toString());
    final bescheidErhalten = parse(a['bescheid_erhalten']?.toString());
    final widerspruchDatum = parse(a['widerspruch_datum']?.toString());
    final widerspruchVorbereitet = parse(a['widerspruch_vorbereitet']?.toString());
    final widerspruchGeliefert = parse(a['widerspruch_geliefert']?.toString());
    final akteneinsichtDatum = parse(a['akteneinsicht_datum']?.toString());
    final akteneinsichtErhalten = parse(a['akteneinsicht_erhalten']?.toString());
    final eingangsbestDatum = parse(a['eingangsbestaetigung_datum']?.toString());
    final eingangsbestErhalten = parse(a['eingangsbestaetigung_erhalten']?.toString());
    final heute = DateTime.now();

    final entries = <Map<String, dynamic>>[];
    void addE(DateTime? d, String text, MaterialColor color, IconData icon, {String? hint, bool warning = false, bool pending = false}) {
      if (d != null) entries.add({'datum': d, 'text': text, 'color': color, 'icon': icon, 'hint': hint, 'warning': warning, 'pending': pending, 'auto': true});
    }
    void addPending(String text, MaterialColor color, IconData icon, {String? hint}) {
      entries.add({'datum': heute, 'text': text, 'color': color, 'icon': icon, 'hint': hint, 'warning': true, 'pending': true, 'auto': true});
    }

    // ===== REGEL 1: ANTRAG =====
    if (antragDatum != null) {
      addE(antragDatum, '📤 AUSGANG: Antrag eingereicht', Colors.indigo, Icons.send);
      // Eingang: Bescheid
      if (bescheidErhalten != null) {
        final wartezeit = bescheidErhalten.difference(antragDatum).inDays;
        addE(bescheidErhalten, '📥 EINGANG: Bescheid erhalten (nach $wartezeit Tagen)', Colors.teal, Icons.markunread_mailbox);
      } else if (bescheidDatum == null) {
        final wartezeit = heute.difference(antragDatum).inDays;
        if (wartezeit > 49) { // > 7 Wochen
          addPending('⚠ Seit $wartezeit Tagen keine Antwort auf Antrag — nachhaken!', Colors.orange, Icons.warning,
            hint: 'Gesetzliche Bearbeitungsfrist: 3-7 Wochen');
        } else {
          addPending('⏳ Warte auf Bescheid (Tag $wartezeit von ca. 49)', Colors.grey, Icons.hourglass_top,
            hint: 'Bearbeitungszeit: 3-7 Wochen üblich');
        }
      }
    } else {
      addPending('→ SCHRITT 1: Antrag beim Versorgungsamt einreichen', Colors.indigo, Icons.arrow_forward);
    }

    // ===== REGEL 2: BESCHEID + FRIST =====
    if (bescheidDatum != null && bescheidErhalten == null) {
      addE(bescheidDatum, 'Bescheid erstellt vom Amt', Colors.teal, Icons.description);
      addPending('→ Wann wurde der Bescheid per Post erhalten? (Tab Bescheid eintragen)', Colors.orange, Icons.arrow_forward);
    }
    if (bescheidErhalten != null) {
      final frist = bescheidErhalten.add(const Duration(days: 30));
      if (widerspruchDatum != null) {
        final tageVorher = frist.difference(widerspruchDatum).inDays;
        addE(widerspruchDatum, '✓ REGEL ERFÜLLT: Widerspruch $tageVorher Tage vor Fristende eingelegt', Colors.green, Icons.check_circle);
      } else if (heute.isBefore(frist)) {
        addPending('🚨 FRIST: Widerspruch einlegen bis ${fmt(frist)} (noch ${frist.difference(heute).inDays} Tage!)', Colors.red, Icons.timer,
          hint: '§ 84 SGG: 1 Monat ab Zustellung');
      } else {
        entries.add({'datum': frist, 'text': '❌ FRIST ABGELAUFEN — Widerspruch nicht eingelegt', 'color': Colors.red, 'icon': Icons.cancel, 'auto': true, 'warning': true});
      }
    }

    // ===== REGEL 3: WIDERSPRUCH EINLEGEN =====
    if (widerspruchVorbereitet != null) addE(widerspruchVorbereitet, '📝 Widerspruch vorbereitet', Colors.purple, Icons.edit_note);
    if (widerspruchDatum != null) {
      addE(widerspruchDatum, '📤 AUSGANG: Widerspruch eingelegt (fristwahrend)', Colors.orange, Icons.gavel);
      if (widerspruchGeliefert != null) addE(widerspruchGeliefert, '📤 Widerspruch geliefert per ${a['widerspruch_lieferung_methode'] ?? ''}', Colors.deepPurple, Icons.send);
      // Eingang: Eingangsbestätigung
      if (eingangsbestErhalten != null) {
        addE(eingangsbestErhalten, '📥 EINGANG: Eingangsbestätigung vom Amt erhalten', Colors.teal, Icons.mark_email_read);
      } else if (eingangsbestDatum != null) {
        addE(eingangsbestDatum, 'Eingangsbestätigung ausgestellt', Colors.teal, Icons.description);
        addPending('→ Eingangsbestätigung noch nicht per Post erhalten', Colors.orange, Icons.arrow_forward);
      } else {
        final tage = heute.difference(widerspruchDatum).inDays;
        if (tage > 14) addPending('⚠ Seit $tage Tagen keine Eingangsbestätigung — nachhaken!', Colors.orange, Icons.warning);
      }
    }

    // ===== REGEL 4: AKTENEINSICHT =====
    if (widerspruchDatum != null && akteneinsichtDatum == null) {
      addPending('→ SCHRITT: Akteneinsicht beantragen nach § 25 SGB X', Colors.purple, Icons.arrow_forward,
        hint: 'Wichtig! Ohne Akteneinsicht keine fundierte Begründung möglich');
    }
    if (akteneinsichtDatum != null) {
      addE(akteneinsichtDatum, '📤 AUSGANG: Akteneinsicht beantragt (§ 25 SGB X)', Colors.purple, Icons.folder_open);
      // Eingang: Akten
      if (akteneinsichtErhalten != null) {
        final wartezeit = akteneinsichtErhalten.difference(akteneinsichtDatum).inDays;
        addE(akteneinsichtErhalten, '📥 EINGANG: Akteneinsicht erhalten (nach $wartezeit Tagen)', Colors.green, Icons.inbox,
          hint: '→ Jetzt Akten analysieren + Begründung mit ärztlichen Befunden erstellen');
      } else {
        final wartezeit = heute.difference(akteneinsichtDatum).inDays;
        if (wartezeit > 14) {
          addPending('⚠ Akteneinsicht seit $wartezeit Tagen ausstehend — nachhaken!', Colors.orange, Icons.warning);
        } else {
          addPending('⏳ Warte auf Akteneinsicht (Tag $wartezeit)', Colors.grey, Icons.hourglass_top);
        }
      }
    }

    // ===== REGEL 5: BEGRÜNDUNG (nach Akteneinsicht) =====
    if (akteneinsichtErhalten != null) {
      // Check if Begründung exists in manual verlauf
      final hasBeg = _verlauf.any((e) => (e['notiz']?.toString() ?? '').toLowerCase().contains('begründung'));
      if (!hasBeg) {
        addPending('→ SCHRITT: Begründung nachreichen (mit Aktenanalyse + ärztliche Befunde)', Colors.indigo, Icons.arrow_forward,
          hint: 'Begründung kann auch nach Widerspruchsfrist nachgereicht werden');
      }
    }

    // ===== REGEL 6: BEARBEITUNGSFRIST AMT (3 Monate) =====
    if (widerspruchDatum != null) {
      final bearbeitungFrist = widerspruchDatum.add(const Duration(days: 90));
      if (heute.isAfter(bearbeitungFrist)) {
        entries.add({'datum': bearbeitungFrist, 'text': '🚨 3 MONATE ÜBERSCHRITTEN — Untätigkeitsklage möglich (§ 88 SGG)', 'color': Colors.red, 'icon': Icons.gavel, 'auto': true, 'warning': true,
          'hint': 'Sozialgericht einschalten — Amt reagiert nicht'});
      } else {
        final restTage = bearbeitungFrist.difference(heute).inDays;
        entries.add({'datum': bearbeitungFrist, 'text': '⏳ Bearbeitungsfrist Amt: noch $restTage Tage (bis ${fmt(bearbeitungFrist)})', 'color': Colors.grey, 'icon': Icons.hourglass_top, 'auto': true,
          'hint': 'Nach 3 Monaten ohne Widerspruchsbescheid → Untätigkeitsklage § 88 SGG'});
      }
    }

    // Add Termine
    for (final t in _termine) {
      final d = parse(t['datum']?.toString());
      if (d != null) {
        final uhrzeit = t['uhrzeit']?.toString() ?? '';
        final notiz = t['notiz']?.toString() ?? '';
        entries.add({'datum': d, 'text': '📅 Termin${uhrzeit.isNotEmpty ? ' um $uhrzeit' : ''}${notiz.isNotEmpty ? ' — $notiz' : ''}', 'color': Colors.blue, 'icon': Icons.calendar_month, 'auto': true});
      }
    }

    // Add manual entries
    final manual = List<Map<String, dynamic>>.from(_verlauf);
    for (final e in manual) {
      final d = parse(e['datum']?.toString());
      if (d != null) entries.add({'datum': d, 'text': e['notiz']?.toString() ?? '', 'color': Colors.grey, 'icon': Icons.circle, 'auto': false, 'id': e['id'], 'status': e['status']});
    }

    entries.sort((a, b) => (a['datum'] as DateTime).compareTo(b['datum'] as DateTime));

    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Expanded(child: Text('${entries.length} Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(icon: const Icon(Icons.add, size: 14), label: const Text('Neuer Eintrag', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: _addVerlauf),
      ])),
      Expanded(child: entries.isEmpty ? Center(child: Text('Kein Verlauf', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: entries.length, itemBuilder: (_, i) {
            final e = entries[i];
            final isAuto = e['auto'] == true;
            final color = e['color'] as MaterialColor? ?? Colors.grey;
            final icon = e['icon'] as IconData? ?? Icons.circle;
            final isWarning = e['warning'] == true;
            final hint = e['hint']?.toString();
            return Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: isWarning ? color.shade100 : (isAuto ? color.shade50 : Colors.white),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isWarning ? color.shade400 : (isAuto ? color.shade300 : Colors.indigo.shade200), width: isWarning ? 2 : 1)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(icon, size: 16, color: color.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmt(e['datum'] as DateTime), style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                  if (!isAuto && (e['status']?.toString() ?? '').isNotEmpty) Container(margin: const EdgeInsets.only(top: 2), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(6)),
                    child: Text(e['status'].toString().replaceAll('_', ' ').toUpperCase(), style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.indigo.shade800))),
                  Padding(padding: const EdgeInsets.only(top: 2), child: Text(e['text']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: isAuto ? FontWeight.w600 : FontWeight.normal, color: isAuto ? color.shade800 : Colors.black87))),
                  if (hint != null) Padding(padding: const EdgeInsets.only(top: 3), child: Text(hint, style: TextStyle(fontSize: 10, fontStyle: FontStyle.italic, color: color.shade600))),
                ])),
                if (!isAuto) IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteVaAntragVerlauf(e['id'] as int); _load(); widget.onChanged(); },
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
          if (status.isNotEmpty) { widget.antrag['status'] = status; await widget.apiService.saveVersorgungsamtAntrag(widget.userId, _fullAntragPayload(widget.antrag)); }
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
            final kColor = isEin ? Colors.green : Colors.blue;
            return Card(margin: const EdgeInsets.only(bottom: 6), child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showKorrDetail(k),
              child: Padding(padding: const EdgeInsets.all(10), child: Row(children: [
                Icon(isEin ? Icons.call_received : Icons.call_made, size: 18, color: kColor.shade700), const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: kColor.shade800)),
                  Row(children: [
                    Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text({'email': 'E-Mail', 'post': 'Post', 'fax': 'Fax', 'persoenlich': 'Persönlich', 'online': 'Online'}[k['methode']?.toString()] ?? k['methode'].toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ],
                  ]),
                ])),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
                IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400), onPressed: () async { await widget.apiService.deleteVaAntragKorr(k['id'] as int); _load(); },
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28)),
              ])),
            ));
          })),
    ]);
  }

  void _showKorrDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang';
    final color = isEin ? Colors.green : Colors.blue;
    final kId = int.tryParse(k['id'].toString()) ?? 0;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: color.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '(kein Betreff)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800))),
      ]),
      content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800))),
          if ((k['methode']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(width: 8),
            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text({'email': 'E-Mail', 'post': 'Post', 'fax': 'Fax', 'persoenlich': 'Persönlich', 'online': 'Online'}[k['methode']?.toString()] ?? k['methode'].toString(), style: TextStyle(fontSize: 11, color: Colors.purple.shade700))),
          ],
          const Spacer(),
          Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
        ]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Inhalt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(k['notiz'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
        const SizedBox(height: 16),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'versorgungsamt_antrag', korrespondenzId: kId),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
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
    final aid = widget.antragId;

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      const SizedBox(height: 12),
      Text('Akteneinsicht', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
      const SizedBox(height: 8),
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
      const SizedBox(height: 12),
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
      const SizedBox(height: 12),
      Text('Ausgang Widerspruch von Mitglieder', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
      const SizedBox(height: 8),
      _datePickerRow(Icons.edit_note, 'Vorbereitet am', a['widerspruch_vorbereitet']?.toString() ?? '', (date) async {
        a['widerspruch_vorbereitet'] = date;
        await _saveAntragField(a, 'widerspruch_vorbereitet', date);
      }),
      const SizedBox(height: 6),
      _datePickerRow(Icons.send, 'Geliefert am', a['widerspruch_geliefert']?.toString() ?? '', (date) async {
        a['widerspruch_geliefert'] = date;
        await _saveAntragField(a, 'widerspruch_geliefert', date);
      }),
      const SizedBox(height: 6),
      _methodeRow('Geliefert per', a['widerspruch_lieferung_methode']?.toString() ?? '', (m) async {
        a['widerspruch_lieferung_methode'] = m;
        await _saveAntragField(a, 'widerspruch_lieferung_methode', m);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_widerspruch_ausgang_$aid', korrespondenzId: 6),

      const SizedBox(height: 12),
      Text('Eingang finaler Widerspruch an Behörde', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
      const SizedBox(height: 4),
      Text('Bestätigung der Behörde, dass der finale Widerspruch (nach Akteneinsicht, mit Begründung) eingegangen ist.',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
      const SizedBox(height: 8),
      _datePickerRow(Icons.mark_email_read, 'Eingang bestätigt am', a['widerspruch_eingang_bestaetigt_datum']?.toString() ?? '', (date) async {
        a['widerspruch_eingang_bestaetigt_datum'] = date;
        await _saveAntragField(a, 'widerspruch_eingang_bestaetigt_datum', date);
      }),
      const SizedBox(height: 6),
      _methodeRow('Bestätigt per', a['widerspruch_eingang_bestaetigt_methode']?.toString() ?? '', (m) async {
        a['widerspruch_eingang_bestaetigt_methode'] = m;
        await _saveAntragField(a, 'widerspruch_eingang_bestaetigt_methode', m);
      }),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_widerspruch_eingang_bestaetigt_$aid', korrespondenzId: 7),

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

  Widget _lawRow(String p, String t) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4)),
        child: Text(p, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
      const SizedBox(width: 8),
      Expanded(child: Text(t, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
    ]));
  }
}

// ===== TERMIN KORRESPONDENZ TAB =====
class _TerminKorrTab extends StatefulWidget {
  final ApiService apiService;
  final int terminId;
  const _TerminKorrTab({required this.apiService, required this.terminId});
  @override
  State<_TerminKorrTab> createState() => _TerminKorrTabState();
}

class _TerminKorrTabState extends State<_TerminKorrTab> {
  List<Map<String, dynamic>> _korr = [];
  bool _loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final res = await widget.apiService.saveVersorgungsamtTermin(0, {'action': 'list_korr', 'termin_id': widget.terminId});
      if (res['success'] == true && res['korrespondenz'] is List) {
        _korr = List<Map<String, dynamic>>.from((res['korrespondenz'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.email, size: 18, color: Colors.indigo.shade700),
        const SizedBox(width: 6),
        Text('Korrespondenz (${_loading ? '...' : _korr.length})', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const Spacer(),
        FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero)),
      ])),
      Expanded(child: _loading ? const Center(child: CircularProgressIndicator())
        : _korr.isEmpty ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade400)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _korr.length, itemBuilder: (_, i) {
            final k = _korr[i];
            final isEin = k['richtung'] == 'eingang';
            final color = isEin ? Colors.green : Colors.blue;
            return Card(child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showDetail(k),
              child: ListTile(
                leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: color.shade700, size: 18),
                title: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                subtitle: Text('${k['datum'] ?? ''} • ${isEin ? 'Eingang' : 'Ausgang'}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chevron_right, size: 16, color: Colors.grey.shade400),
                  IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () async { await widget.apiService.saveVersorgungsamtTermin(0, {'action': 'delete_korr', 'id': k['id']}); _load(); }),
                ]),
              ),
            ));
          })),
      const Divider(height: 1),
      Padding(padding: const EdgeInsets.all(12),
        child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_termin', korrespondenzId: widget.terminId)),
    ]);
  }

  void _add() {
    final betreffC = TextEditingController();
    final inhaltC = TextEditingController();
    String richtung = 'ausgang';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (_, setDlg) => AlertDialog(
      title: Row(children: [Icon(Icons.email, size: 18, color: Colors.indigo.shade700), const SizedBox(width: 8), const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15))]),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Ausgang'), avatar: const Icon(Icons.call_made, size: 14), selected: richtung == 'ausgang', selectedColor: Colors.blue.shade100, onSelected: (_) => setDlg(() => richtung = 'ausgang')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Eingang'), avatar: const Icon(Icons.call_received, size: 14), selected: richtung == 'eingang', selectedColor: Colors.green.shade100, onSelected: (_) => setDlg(() => richtung = 'eingang')),
        ]),
        const SizedBox(height: 12),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: inhaltC, maxLines: 6, decoration: InputDecoration(labelText: 'Inhalt / E-Mail-Text', hintText: 'Mail-Inhalt hier einfügen...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(onPressed: () async {
          final today = '${DateTime.now().day.toString().padLeft(2, '0')}.${DateTime.now().month.toString().padLeft(2, '0')}.${DateTime.now().year}';
          await widget.apiService.saveVersorgungsamtTermin(0, {'action': 'save_korr', 'termin_id': widget.terminId, 'korr': {'richtung': richtung, 'betreff': betreffC.text.trim(), 'inhalt': inhaltC.text.trim(), 'datum': today}});
          if (ctx.mounted) Navigator.pop(ctx);
          _load();
        }, child: const Text('Speichern')),
      ],
    )));
  }

  void _showDetail(Map<String, dynamic> k) {
    final isEin = k['richtung'] == 'eingang';
    final color = isEin ? Colors.green : Colors.blue;
    final kId = k['id'] is int ? k['id'] as int : int.tryParse(k['id'].toString()) ?? 0;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: color.shade700),
        const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: color.shade800))),
      ]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: color.shade800))),
          const Spacer(),
          Text(k['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        ]),
        if ((k['inhalt']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(k['inhalt'].toString(), style: const TextStyle(fontSize: 13, height: 1.4))),
        ],
        const SizedBox(height: 16),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'va_termin_korr', korrespondenzId: kId),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }
}
