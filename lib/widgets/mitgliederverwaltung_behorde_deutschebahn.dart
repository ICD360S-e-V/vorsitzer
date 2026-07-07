import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/external_browser_service.dart';
import '../utils/clipboard_helper.dart';

/// Deutsche Bahn — Mobilitätsservice-Zentrale (MSZ)
///
/// Two sub-tabs:
///   • "Zuständige Deutsche Bahn" — MSZ contact card + optional selection
///   • "Vorfall" — list of Hilfeleistung-Anmeldungen (Ein-/Aus-/Umsteigehilfe)
///     with journey details (Reiseverbindung: von/nach, Datum, Uhrzeit, Zug).
///
/// Der Vorfall-Dialog bildet die 4 Schritte des MSZ-Portals
/// (msz.bahnhof.de/reiseverbindung) ab:
///   1. Reiseverbindung  (Von/Nach, Datum, Uhrzeit, Zug)
///   2. Reisender        (Hilfsmittel, Begleitperson)
///   3. Unterstützungsbedarf (Hilfe-Typ)
///   4. Kontakt          (autofilled aus Stufe 1 der Verifizierung —
///                         Name, Vorname, E-Mail, Telefon/Handy)
///
/// Der „E-Mail an MSZ senden"-Button generiert einen mailto: Link mit
/// allen 4 Schritten strukturiert im Body — MSZ akzeptiert Anfragen per
/// E-Mail an msz@deutschebahn.com.
class MitgliederverwaltungBehordeDeutscheBahn extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final User user;

  const MitgliederverwaltungBehordeDeutscheBahn({
    super.key,
    required this.apiService,
    required this.userId,
    required this.user,
  });

  @override
  State<MitgliederverwaltungBehordeDeutscheBahn> createState() => _State();
}

class _State extends State<MitgliederverwaltungBehordeDeutscheBahn> with TickerProviderStateMixin {
  late final TabController _tabCtrl;
  bool _loaded = false, _loading = false, _saving = false;

  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _vorfaelle = [];
  List<Map<String, dynamic>> _institutionen = [];
  List<Map<String, dynamic>> _dticketVertraege = [];
  bool _gesundheitHoergeraete = false;
  String _gesundheitHoergeraeteSeite = '';
  /// Hilfsmittel-Rezepte des Mitglieds (mitglied_rezepte, alle Arzt-Typen) —
  /// Quelle für die automatische MSZ-Online-Auswahl (E-Rollstuhl etc.).
  List<Map<String, dynamic>> _hilfsmittelRezepte = [];

  static const _hilfeTypen = [
    'Einsteigehilfe',
    'Aussteigehilfe',
    'Umsteigehilfe',
    'Ein-, Um- und Aussteigehilfe (kombiniert)',
    'Nur Beratung / Auskunft',
    'Sonstiges',
  ];

  static const _zugTypen = ['ICE', 'IC/EC', 'RE/RB', 'S-Bahn', 'Sonstiges'];

  static const _hilfsmittel = [
    'Keine',
    'Rollstuhl (manuell)',
    'Rollstuhl (elektrisch)',
    'Rollator',
    'Blindenstock',
    'Blindenführhund',
    'Sonstige',
  ];

  static const _statusList = ['geplant', 'angemeldet', 'bestätigt', 'wahrgenommen', 'nicht wahrgenommen', 'storniert', 'abgelehnt'];

  /// Fahrkarte-Auswahl im Vorfall-Dialog. „Deutschland Ticket" zieht die Daten
  /// (Abo-Nr., Preis, Gültigkeit) aus dem Deutschlandticket-Vertrag des Mitglieds
  /// (Behörde → Deutschlandticket → Vertrag).
  static const _ticketArten = ['Deutschland Ticket', 'Kein / Sonstiges'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() { _tabCtrl.dispose(); super.dispose(); }

  String _v(String f) => _data[f]?.toString() ?? '';

  Future<void> _load() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.getDeutscheBahnData(widget.userId);
      if (res['success'] == true && mounted) {
        final raw = res['data'];
        if (raw is Map) {
          _data = {};
          for (final e in raw.entries) {
            final parts = e.key.toString().split('.');
            _data[parts.length == 2 ? parts[1] : e.key.toString()] = e.value;
          }
        }
        _vorfaelle = (res['vorfaelle'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      final inst = await widget.apiService.listDeutscheBahnInstitutionen();
      if (inst['success'] == true && mounted) {
        _institutionen = (inst['institutionen'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      // Deutschlandticket-Verträge des Mitglieds — Quelle für Fahrkarte-Autofill.
      final dt = await widget.apiService.getDticketData(widget.userId);
      if (dt['success'] == true && mounted) {
        _dticketVertraege = (dt['vertraege'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      // Gesundheitsprofil — Hörgeräte-Flag markiert Schwerhörigkeit für die MSZ-Anmeldung.
      final gp = await widget.apiService.getGesundheitsProfil(widget.userId);
      if (gp['success'] == true && mounted) {
        _gesundheitHoergeraete = gp['hoergeraete']?.toString() == '1';
        _gesundheitHoergeraeteSeite = gp['hoergeraete_seite']?.toString() ?? '';
      }
      // Hilfsmittel-Rezepte (alle Arzt-Typen, kein arzt_type-Filter) — für die
      // automatische Auswahl auf dem MSZ-Portal (z. B. E-Rollstuhl → Elektrorollstuhl).
      final rz = await widget.apiService.rezeptAction({'action': 'list', 'user_id': widget.userId});
      if (rz['rezepte'] is List && mounted) {
        _hilfsmittelRezepte = (rz['rezepte'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (_) {}
    if (mounted) setState(() { _loading = false; _loaded = true; });
  }

  Future<void> _saveFields(Map<String, dynamic> fields) async {
    setState(() => _saving = true);
    try {
      final mapped = <String, dynamic>{};
      for (final e in fields.entries) {
        mapped['stammdaten.${e.key}'] = e.value?.toString() ?? '';
      }
      await widget.apiService.saveDeutscheBahnData(widget.userId, mapped);
      for (final e in fields.entries) { _data[e.key] = e.value; }
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && !_loading) _load();
    if (_loading || !_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      TabBar(
        controller: _tabCtrl,
        labelColor: Colors.red.shade700,
        unselectedLabelColor: Colors.grey.shade500,
        indicatorColor: Colors.red.shade700,
        tabs: [
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _v('institution_id').isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.train, size: 16),
            const SizedBox(width: 4), const Text('Zuständige Deutsche Bahn'),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _vorfaelle.isNotEmpty ? Colors.green : Colors.red),
            const SizedBox(width: 4), const Icon(Icons.accessible, size: 16),
            const SizedBox(width: 4), const Text('Vorfall'),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildInstitutionTab(), _buildVorfallTab()])),
    ]);
  }

  // ────────────────────────── Tab 1: Zuständige Deutsche Bahn ──────────────────────────
  Widget _buildInstitutionTab() {
    final selId = int.tryParse(_v('institution_id'));
    Map<String, dynamic>? selected;
    if (selId != null) {
      selected = _institutionen.firstWhere(
        (i) => (i['id'] as int?) == selId || int.tryParse(i['id'].toString()) == selId,
        orElse: () => {},
      );
    }
    // Auto-select MSZ (only entry today) — nothing to search for.
    if (selected == null && _institutionen.length == 1) {
      final auto = _institutionen.first;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_v('institution_id').isEmpty) {
          _saveFields({
            'institution_id': auto['id']?.toString() ?? '',
            'institution_name': auto['name']?.toString() ?? '',
          });
        }
      });
      selected = auto;
    }

    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Zuständige Stelle für Mobilitätshilfe', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
      const SizedBox(height: 4),
      Text('Die Mobilitätsservice-Zentrale (MSZ) der Deutschen Bahn organisiert '
           'Ein-, Aus- und Umsteigehilfen an ca. 300 Bahnhöfen bundesweit.',
           style: TextStyle(fontSize: 11, color: Colors.grey.shade700, height: 1.4)),
      const SizedBox(height: 12),
      if (selected != null && selected.isNotEmpty) _buildInstitutionCard(selected),
      const SizedBox(height: 12),
      Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
        Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500), const SizedBox(width: 6),
        Expanded(child: Text(
          'Anmeldung bis spätestens 20 Uhr am Vortag der Reise. Bei Auslandsreisen 24 Stunden Vorlauf.',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ])),
    ]));
  }

  Widget _buildInstitutionCard(Map<String, dynamic> inst) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade300),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.train, size: 28, color: Colors.red.shade700),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(inst['name']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade900)),
          if ((inst['abteilung']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 2),
              child: Text(inst['abteilung'].toString(), style: TextStyle(fontSize: 12, color: Colors.red.shade700, fontWeight: FontWeight.w500))),
          const SizedBox(height: 8),
          if ((inst['telefon']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.phone, 'Telefon', inst['telefon'].toString(), copyable: true),
          if ((inst['email']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.email, 'E-Mail', inst['email'].toString(), copyable: true, copyLabel: 'E-Mail'),
          if ((inst['website']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.language, 'Website', inst['website'].toString(), copyable: true),
          if ((inst['oeffnungszeiten']?.toString() ?? '').isNotEmpty)
            _infoRow(Icons.schedule, 'Öffnungszeiten', inst['oeffnungszeiten'].toString()),
          if ((inst['zustaendig_fuer']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 8),
              child: Text(inst['zustaendig_fuer'].toString(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontStyle: FontStyle.italic))),
          if ((inst['notiz']?.toString() ?? '').isNotEmpty)
            Padding(padding: const EdgeInsets.only(top: 6),
              child: Text(inst['notiz'].toString(),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        ])),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String label, String value, {bool copyable = false, String? copyLabel}) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
      Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 11))),
      if (copyable) InkWell(
        onTap: () => ClipboardHelper.copy(context, value, copyLabel ?? label),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(Icons.copy, size: 14, color: Colors.blue.shade600),
        ),
      ),
    ]));
  }

  // ────────────────────────── Tab 2: Vorfall / Hilfeleistung ──────────────────────────
  Widget _buildVorfallTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.accessible, size: 18, color: Colors.red.shade700), const SizedBox(width: 8),
        Text('${_vorfaelle.length} Hilfeleistungen', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Neue Hilfeleistung', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
          onPressed: () => _showVorfallDialog(),
        ),
      ])),
      Expanded(child: _vorfaelle.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.accessible, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Hilfeleistungen erfasst', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('(Ein-/Aus-/Umsteigehilfe im Zug)', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _vorfaelle.length, itemBuilder: (_, i) {
            final v = _vorfaelle[i];
            final status = v['status']?.toString() ?? 'angemeldet';
            final sc = status == 'wahrgenommen' ? Colors.green
                : status == 'bestätigt' ? Colors.blue
                : status == 'storniert' || status == 'abgelehnt' || status == 'nicht wahrgenommen' ? Colors.red
                : status == 'geplant' ? Colors.grey
                : Colors.orange;
            final von = v['von_bahnhof']?.toString() ?? '';
            final nach = v['nach_bahnhof']?.toString() ?? '';
            final route = [von, nach].where((s) => s.isNotEmpty).join(' → ');
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: sc.shade50, child: Icon(Icons.accessible, size: 18, color: sc.shade700)),
                title: Text(v['hilfe_typ']?.toString().isNotEmpty == true ? v['hilfe_typ'].toString() : (v['typ']?.toString() ?? '—'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (route.isNotEmpty) Text(route, style: const TextStyle(fontSize: 11)),
                  if ((v['reise_datum']?.toString() ?? '').isNotEmpty || (v['reise_uhrzeit']?.toString() ?? '').isNotEmpty)
                    Text('Hin: ${v['reise_datum'] ?? ''} ${v['reise_uhrzeit'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11)),
                  if ((v['rueck_datum']?.toString() ?? '').isNotEmpty || (v['rueck_uhrzeit']?.toString() ?? '').isNotEmpty)
                    Text('Rück: ${v['rueck_datum'] ?? ''} ${v['rueck_uhrzeit'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11)),
                  if ((v['zug_typ']?.toString() ?? '').isNotEmpty || (v['zug_nummer']?.toString() ?? '').isNotEmpty)
                    Text('Zug: ${v['zug_typ'] ?? ''} ${v['zug_nummer'] ?? ''}'.trim(), style: const TextStyle(fontSize: 11)),
                  if ((v['ticket_art']?.toString() ?? '').isNotEmpty && v['ticket_art'].toString() != 'Kein / Sonstiges')
                    Text('Ticket: ${v['ticket_art']}${(v['ticket_abo_nr']?.toString() ?? '').isNotEmpty ? ' (${v['ticket_abo_nr']})' : ''}', style: const TextStyle(fontSize: 11)),
                  if ((v['schwerhoerig']?.toString() ?? '') == 'ja')
                    Text('Hörbehinderung: schwerhörig${(v['hoergeraete_seite']?.toString() ?? '').isNotEmpty ? ' (${v['hoergeraete_seite']})' : ''}', style: const TextStyle(fontSize: 11)),
                  Text('Status: $status', style: TextStyle(fontSize: 11, color: sc.shade700, fontWeight: FontWeight.w500)),
                ]),
                trailing: PopupMenuButton<String>(
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Bearbeiten')])),
                    const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red))])),
                  ],
                  onSelected: (a) {
                    if (a == 'edit') _showVorfallDialog(existing: v);
                    if (a == 'delete') _deleteVorfall(v);
                  },
                ),
                onTap: () => _showVorfallDialog(existing: v),
              ),
            );
          })),
    ]);
  }

  Future<void> _deleteVorfall(Map<String, dynamic> v) async {
    final c = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Hilfeleistung löschen?'),
      content: Text(v['hilfe_typ']?.toString() ?? v['typ']?.toString() ?? ''),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (c != true) return;
    await widget.apiService.deleteDeutscheBahnVorfall(widget.userId, int.tryParse(v['id'].toString()) ?? 0);
    _load();
  }

  /// Full display name: Vorname + Nachname (or fallback to name).
  String get _userFullName {
    final vor = (widget.user.vorname ?? '').trim();
    final nach = (widget.user.nachname ?? '').trim();
    if (vor.isNotEmpty || nach.isNotEmpty) return '$vor $nach'.trim();
    return widget.user.name;
  }

  /// Best available phone: Handy > Festnetz.
  String get _userBestPhone {
    final mob = (widget.user.telefonMobil ?? '').trim();
    if (mob.isNotEmpty) return mob;
    return (widget.user.telefonFix ?? '').trim();
  }

  /// Aktiver (nicht gekündigter) Deutschlandticket-Vertrag des Mitglieds —
  /// Quelle für den Fahrkarte-Autofill. Fällt auf den neuesten Vertrag zurück.
  Map<String, dynamic>? get _activeDticket {
    if (_dticketVertraege.isEmpty) return null;
    return _dticketVertraege.firstWhere(
      (v) => (v['status']?.toString() ?? '') != 'gekündigt',
      orElse: () => _dticketVertraege.first,
    );
  }

  /// Read-only Info-Karte mit den aus dem Deutschlandticket-Vertrag
  /// übernommenen Daten (Abo-Nr., Preis, Gültigkeit).
  Widget _dticketInfoCard(Map<String, dynamic>? dt) {
    if (dt == null) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
          const SizedBox(width: 6),
          Expanded(child: Text('Kein Deutschland-Ticket-Vertrag hinterlegt (Behörde → Deutschlandticket → Vertrag).',
            style: TextStyle(fontSize: 11, color: Colors.orange.shade900))),
        ]),
      );
    }
    final abo = dt['abo_nr']?.toString() ?? '';
    final preis = dt['preis']?.toString() ?? '';
    final ab = dt['gueltig_ab']?.toString() ?? '';
    final bis = dt['gueltig_bis']?.toString() ?? '';
    final gek = (dt['status']?.toString() ?? '') == 'gekündigt';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.confirmation_number, size: 14, color: Colors.green.shade700),
          const SizedBox(width: 6),
          Text('Deutschland Ticket — aus Vertrag übernommen', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.green.shade900)),
          const Spacer(),
          if (gek) Text('gekündigt', style: TextStyle(fontSize: 10, color: Colors.red.shade700, fontStyle: FontStyle.italic)),
        ]),
        const SizedBox(height: 6),
        Text('Abo-Nr.: ${abo.isNotEmpty ? abo : '—'}', style: const TextStyle(fontSize: 11)),
        Text('Preis: ${preis.isNotEmpty ? '$preis €/Mo' : '—'}', style: const TextStyle(fontSize: 11)),
        if (ab.isNotEmpty || bis.isNotEmpty)
          Text('Gültig: ${ab.isNotEmpty ? ab : '—'}${bis.isNotEmpty ? ' bis $bis' : ''}', style: const TextStyle(fontSize: 11)),
      ]),
    );
  }

  // ────────────────────────── MSZ Online-Anmeldung (Chromium extern + Auto-Fill) ──────────────────────────
  static const _mszOnlineUrl = 'https://msz.bahnhof.de/unterstuetzungsbedarf';

  /// Leitet aus den vorhandenen Daten (Hilfsmittel-Rezepte + Dialog-Eingaben)
  /// die auf dem MSZ-Portal anzuklickenden Optionen ab. Rückgabe: Liste
  /// sichtbarer Options-Texte, die das Auto-Fill-JS auf msz.bahnhof.de anklickt.
  /// checks = Checkbox-Kategorien (per Klick auf sichtbaren Text), combo =
  /// Optionen der react-select-Hilfsmittel-Combobox (öffnen → <li> anklicken).
  /// Labels exakt aus dem MSZ-Bundle (index-*.js): „Elektrorollstuhl, Elektromobil",
  /// „Manueller Rollstuhl", „Rollator".
  ({List<String> checks, List<String> combo}) _computeMszPicks({required String hilfsmittel, required bool schwerhoerig, required String begleit}) {
    final sources = <String>[
      ..._hilfsmittelRezepte.map((r) => (r['hilfsmittel'] ?? '').toString().toLowerCase()),
      hilfsmittel.toLowerCase(),
    ];
    bool has(List<String> needles) => sources.any((s) => needles.any((n) => s.contains(n)));
    final eRoll      = has(['e-roll', 'elektroroll', 'elektro-roll', 'elektromobil', 'elektrisch']);
    final rollator   = has(['rollator']);
    final manualRoll = has(['rollstuhl']) && !eRoll;
    final blindfuehr = has(['blindenführhund', 'führhund', 'assistenzhund']);
    final blindstock = has(['blindenstock', 'langstock']);

    final checks = <String>[];
    final combo = <String>[];
    if (eRoll || rollator || manualRoll) {
      checks.add('reise mit einem Hilfsmittel');
      if (eRoll) {
        combo.add('Elektrorollstuhl, Elektromobil');
      } else if (rollator) {
        combo.add('Rollator');
      } else if (manualRoll) {
        combo.add('Manueller Rollstuhl');
      }
    }
    if (blindstock || blindfuehr) checks.add('blind oder sehbeeinträchtigt');
    if (schwerhoerig) checks.add('Andere Einschränkungen');
    if (begleit == 'ja') checks.add('Begleitperson');
    if (blindfuehr) checks.add('Assistenzhund');
    return (checks: checks, combo: combo);
  }

  Future<void> _launchMszOnline({required String hilfsmittel, required bool schwerhoerig, required String begleit}) async {
    final picks = _computeMszPicks(hilfsmittel: hilfsmittel, schwerhoerig: schwerhoerig, begleit: begleit);
    final weitere = schwerhoerig
        ? 'Schwerhörig / Hörbehinderung${_gesundheitHoergeraeteSeite.isNotEmpty ? " (Hörgerät: $_gesundheitHoergeraeteSeite)" : ""}'
        : '';
    final all = [...picks.checks, ...picks.combo];
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(all.isEmpty
            ? 'MSZ-Portal wird geöffnet (keine Auto-Auswahl — keine passenden Daten hinterlegt)'
            : 'MSZ-Portal wird geöffnet — Auto-Auswahl: ${all.join(", ")}'),
        backgroundColor: Colors.blue,
      ));
    }
    final err = await ExternalBrowserService.openWithAutoFill(
      url: _mszOnlineUrl,
      autoFillJs: _buildMszAutoFillJs(picks.checks, picks.combo, weitere),
    );
    if (err != null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err), backgroundColor: Colors.red, duration: const Duration(seconds: 8)));
    }
  }

  /// Auto-Fill-JS für das MSZ-Portal (msz.bahnhof.de, Vite/React-SPA).
  ///
  /// Struktur laut Bundle:
  ///   • Unterstützungsbedarf-Kategorien + Begleitung/Assistenzhund = Checkboxen
  ///     → per sichtbarem Text anklicken (nur wenn nicht bereits gesetzt).
  ///   • Hilfsmittel = react-select-Multiselect (Combobox + <li>-Optionen)
  ///     → Combobox öffnen/filtern, dann das passende <li> anklicken.
  /// Polling deckt gestufte Reveals ab. Alle Aktionen loggen als [ICD-MSZ]
  /// in die Browser-Konsole (CSP blockt nur manuelles Konsolen-Einfügen,
  /// nicht die per CDP injizierten Skripte).
  String _buildMszAutoFillJs(List<String> checks, List<String> combo, String weitere) {
    final checksJson = jsonEncode(checks);
    final comboJson = jsonEncode(combo);
    final weitereJson = jsonEncode(weitere);
    return '''
(() => {
  // Gemeinsamer Zustand pro Frame — überlebt Re-Injektionen (evaluateOnNewDocument
  // + onLoad + evaluate feuern das Skript mehrfach). Damit klickt KEINE zweite
  // Skript-Instanz eine schon gesetzte Option erneut → kein Umschalten (Toggle).
  const S = (window.__icd_msz = window.__icd_msz || { acted: {}, comboOpened: 0 });
  const log = (...a) => { try { console.warn('[ICD-MSZ]', ...a); } catch (_) {} };
  if (S.loopRunning) { log('loop läuft bereits in diesem Frame — skip'); return; }
  S.loopRunning = true;

  const CHECKS = $checksJson;
  const COMBO  = $comboJson;
  const WEITERE = $weitereJson;
  const norm = (s) => (s || '').replace(/\\s+/g, ' ').trim().toLowerCase();

  const isUsable = (el) => {
    if (!el) return false;
    const st = window.getComputedStyle(el);
    if (st.display === 'none' || st.visibility === 'hidden' || st.opacity === '0') return false;
    const r = el.getBoundingClientRect();
    return !(r.width === 0 && r.height === 0);
  };

  const setNativeValue = (el, value) => {
    const proto = el.tagName === 'TEXTAREA' ? window.HTMLTextAreaElement.prototype : window.HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
    if (setter) setter.call(el, value); else el.value = value;
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };

  // Kleinstes sichtbares Element, dessen Text `needle` enthält (= spezifischste Option).
  const findByText = (needle, selector) => {
    const n = norm(needle);
    let best = null, bestLen = Infinity;
    for (const el of document.querySelectorAll(selector)) {
      if (!isUsable(el)) continue;
      const t = norm(el.innerText || el.textContent || '');
      if (!t || !t.includes(n)) continue;
      if (t.length < bestLen) { best = el; bestLen = t.length; }
    }
    return best;
  };

  // Findet die Checkbox zu einem Label-Element (Kind, label[for] oder im Container).
  const checkboxFor = (el) => {
    if (!el) return null;
    if (el.matches && el.matches('input[type=checkbox]')) return el;
    let cb = el.querySelector && el.querySelector('input[type=checkbox]');
    if (cb) return cb;
    const forId = el.getAttribute && el.getAttribute('for');
    if (forId) { const t = document.getElementById(forId); if (t && t.type === 'checkbox') return t; }
    let p = el;
    for (let i = 0; i < 4 && p; i++) { p = p.parentElement; if (p) { cb = p.querySelector('input[type=checkbox]'); if (cb) return cb; } }
    return null;
  };

  // Checkbox EINMALIG setzen — nie erneut klicken, nie eine bereits gesetzte umschalten.
  const ensureChecked = (text) => {
    if (S.acted['c:' + text]) return true;
    const el = findByText(text, 'label,[role=checkbox],[role=switch],button,li,div,span,p');
    if (!el) return false;
    const cb = checkboxFor(el);
    if (cb && cb.checked) { S.acted['c:' + text] = 1; log('bereits gesetzt', JSON.stringify(text)); return true; }
    const target = cb || el;
    target.scrollIntoView({ block: 'center' });
    target.click();
    S.acted['c:' + text] = 1;   // EGAL was passiert: genau EIN Klick, nie wieder → kein Toggle
    log('geklickt', JSON.stringify(text), (el.outerHTML || '').slice(0, 140));
    return true;
  };

  // Sucht das <input> der Hilfsmittel-Combobox (Abschnitt enthält "Hilfsmittel").
  const findAidInput = () => {
    for (const inp of document.querySelectorAll('input')) {
      if (!isUsable(inp)) continue;
      const box = inp.closest('div,section,fieldset');
      if (box && /hilfsmittel/i.test(box.innerText || '')) return inp;
    }
    return null;
  };

  // Combobox öffnen + nach dem ersten Wort der Option filtern (max. 4×, damit sie
  // nicht im Loop auf/zu klappt).
  const openAidCombo = (optText) => {
    if (S.comboOpened >= 4) return false;
    const inp = findAidInput();
    if (!inp) return false;
    inp.focus();
    try { inp.click(); } catch (_) {}
    const f = (optText || '').split(/[ ,]/)[0];
    if (f) setNativeValue(inp, f);
    S.comboOpened++;
    log('Combobox geöffnet #' + S.comboOpened, 'filter=', JSON.stringify(f));
    return true;
  };

  // Offene <li>/Option der Combobox EINMALIG anklicken.
  const pickCombo = (text) => {
    if (S.acted['o:' + text]) return true;
    const el = findByText(text, 'li,[role=option],[role=menuitem]');
    if (!el) return false;
    el.scrollIntoView({ block: 'center' });
    el.click();
    S.acted['o:' + text] = 1;
    log('Combo gewählt', JSON.stringify(text));
    return true;
  };

  const start = Date.now();
  let n = 0;
  const tick = () => {
    n++;
    if (Date.now() - start > 45000) { S.loopRunning = false; log('timeout', JSON.stringify(S.acted)); return; }
    let remaining = 0;
    for (const c of CHECKS) if (!ensureChecked(c)) remaining++;
    for (const o of COMBO) {
      if (S.acted['o:' + o]) continue;
      if (!pickCombo(o)) { remaining++; if (n % 3 === 0) openAidCombo(o); }
    }
    if (WEITERE && !S.acted.weitere) {
      const ta = [...document.querySelectorAll('textarea')].filter(isUsable)[0];
      if (ta) { setNativeValue(ta, WEITERE); S.acted.weitere = 1; log('Weitere Hilfe gefüllt'); }
    }
    if (n === 1 || n % 5 === 0) log('tick', n, 'remaining', remaining);
    if (remaining > 0) setTimeout(tick, 800);
    else { S.loopRunning = false; log('FERTIG', JSON.stringify(S.acted)); }
  };
  log('start', location.href, 'CHECKS=', JSON.stringify(CHECKS), 'COMBO=', JSON.stringify(COMBO));
  setTimeout(tick, 900);
})();
''';
  }

  void _showVorfallDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String hilfeTyp = existing?['hilfe_typ']?.toString().isNotEmpty == true ? existing!['hilfe_typ'].toString() : _hilfeTypen.first;
    String status = existing?['status']?.toString().isNotEmpty == true ? existing!['status'].toString() : 'angemeldet';
    String zugTyp = existing?['zug_typ']?.toString().isNotEmpty == true ? existing!['zug_typ'].toString() : _zugTypen.first;
    String hilfsmittel = existing?['hilfsmittel']?.toString().isNotEmpty == true ? existing!['hilfsmittel'].toString() : _hilfsmittel.first;
    String begleit = existing?['begleitperson']?.toString().isNotEmpty == true ? existing!['begleitperson'].toString() : 'nein';
    // Fahrkarte: Default „Deutschland Ticket" wenn ein Vertrag hinterlegt ist.
    String ticketArt = existing?['ticket_art']?.toString().isNotEmpty == true
        ? existing!['ticket_art'].toString()
        : (_activeDticket != null ? _ticketArten.first : _ticketArten.last);
    // Schwerhörigkeit — vorbelegt aus dem Gesundheitsprofil (Hörgeräte hinterlegt).
    bool schwerhoerig = isEdit
        ? (existing['schwerhoerig']?.toString() == 'ja' || existing['schwerhoerig']?.toString() == '1')
        : _gesundheitHoergeraete;
    final datumC = TextEditingController(text: existing?['reise_datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: existing?['reise_uhrzeit']?.toString() ?? '');
    final rueckDatumC = TextEditingController(text: existing?['rueck_datum']?.toString() ?? '');
    final rueckUhrzeitC = TextEditingController(text: existing?['rueck_uhrzeit']?.toString() ?? '');
    final vonC = TextEditingController(text: existing?['von_bahnhof']?.toString() ?? '');
    final nachC = TextEditingController(text: existing?['nach_bahnhof']?.toString() ?? '');
    final zugNrC = TextEditingController(text: existing?['zug_nummer']?.toString() ?? '');
    final begleitAnzC = TextEditingController(text: existing?['begleitperson_anzahl']?.toString() ?? '');
    // Schritt 4: Kontakt — autofilled aus Stufe 1 der Verifizierung.
    final kontaktNameC = TextEditingController(text: _userFullName);
    final kontaktEmailC = TextEditingController(text: widget.user.email);
    final kontaktTelC = TextEditingController(text: _userBestPhone);

    Future<void> pickDate() async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) datumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
    }
    Future<void> pickTime() async {
      final p = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (p != null) uhrzeitC.text = '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
    }
    Future<void> pickRueckDate() async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 30)), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) rueckDatumC.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
    }
    Future<void> pickRueckTime() async {
      final p = await showTimePicker(context: context, initialTime: TimeOfDay.now());
      if (p != null) rueckUhrzeitC.text = '${p.hour.toString().padLeft(2, '0')}:${p.minute.toString().padLeft(2, '0')}';
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Hilfeleistung bearbeiten' : 'Neue Hilfeleistung — MSZ'),
      content: SizedBox(width: 560, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Art der Hilfe *', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: hilfeTyp,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: _hilfeTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setD(() => hilfeTyp = v ?? _hilfeTypen.first),
        ),
        const SizedBox(height: 12),
        const Text('Reiseverbindung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: vonC, decoration: const InputDecoration(labelText: 'Von (Bahnhof)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.train, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: nachC, decoration: const InputDecoration(labelText: 'Nach (Bahnhof)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag, size: 16)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: datumC, readOnly: true, onTap: pickDate, decoration: const InputDecoration(labelText: 'Reisedatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: uhrzeitC, readOnly: true, onTap: pickTime, decoration: const InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 16)))),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            initialValue: zugTyp,
            decoration: const InputDecoration(labelText: 'Zugart', isDense: true, border: OutlineInputBorder()),
            items: _zugTypen.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) => setD(() => zugTyp = v ?? _zugTypen.first),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: TextField(controller: zugNrC, decoration: const InputDecoration(labelText: 'Zug-Nr. (z.B. ICE 599)', isDense: true, border: OutlineInputBorder()))),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Icon(Icons.keyboard_return, size: 14, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          const Text('Rückfahrt (optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(controller: rueckDatumC, readOnly: true, onTap: pickRueckDate, decoration: const InputDecoration(labelText: 'Rückreisedatum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: rueckUhrzeitC, readOnly: true, onTap: pickRueckTime, decoration: const InputDecoration(labelText: 'Rück-Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.schedule, size: 16)))),
        ]),
        const SizedBox(height: 14),
        const Text('Hilfsmittel & Begleitung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: hilfsmittel,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Hilfsmittel', isDense: true, border: OutlineInputBorder()),
          items: _hilfsmittel.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => hilfsmittel = v ?? _hilfsmittel.first),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          decoration: BoxDecoration(
            color: schwerhoerig ? Colors.indigo.shade50 : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: schwerhoerig ? Colors.indigo.shade200 : Colors.grey.shade300),
          ),
          child: Row(children: [
            Icon(Icons.hearing, size: 16, color: schwerhoerig ? Colors.indigo.shade600 : Colors.grey.shade500),
            const SizedBox(width: 8),
            const Expanded(child: Text('Schwerhörig / Hörbehinderung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
            if (schwerhoerig && _gesundheitHoergeraeteSeite.isNotEmpty)
              Padding(padding: const EdgeInsets.only(right: 6),
                child: Text('Hörgerät: $_gesundheitHoergeraeteSeite', style: TextStyle(fontSize: 10, color: Colors.indigo.shade700, fontWeight: FontWeight.w500))),
            Switch(value: schwerhoerig, activeThumbColor: Colors.indigo.shade600, onChanged: (v) => setD(() => schwerhoerig = v)),
          ]),
        ),
        if (!isEdit && _gesundheitHoergeraete)
          Padding(padding: const EdgeInsets.only(top: 3, left: 4),
            child: Text('automatisch aus Gesundheitsprofil (Hörgeräte hinterlegt)', style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontStyle: FontStyle.italic))),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(flex: 2, child: DropdownButtonFormField<String>(
            initialValue: begleit,
            decoration: const InputDecoration(labelText: 'Begleitperson', isDense: true, border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'nein', child: Text('nein', style: TextStyle(fontSize: 12))),
              DropdownMenuItem(value: 'ja', child: Text('ja', style: TextStyle(fontSize: 12))),
            ],
            onChanged: (v) => setD(() => begleit = v ?? 'nein'),
          )),
          const SizedBox(width: 10),
          Expanded(flex: 3, child: TextField(
            controller: begleitAnzC,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Anzahl Begleitpersonen', isDense: true, border: OutlineInputBorder()),
          )),
        ]),
        const SizedBox(height: 14),
        const Text('Fahrkarte / Ticket', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          initialValue: ticketArt,
          isExpanded: true,
          decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
          items: _ticketArten.map((t) => DropdownMenuItem(value: t, child: Text(t, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => ticketArt = v ?? _ticketArten.last),
        ),
        if (ticketArt == 'Deutschland Ticket') ...[
          const SizedBox(height: 8),
          _dticketInfoCard(_activeDticket),
        ],
        const SizedBox(height: 14),
        DropdownButtonFormField<String>(
          initialValue: status,
          decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
          items: _statusList.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setD(() => status = v ?? 'angemeldet'),
        ),

        // ─── Schritt 4: Kontakt (autofilled aus Stufe 1) ────────────────────
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.contact_mail, size: 14, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Text('Kontakt (Schritt 4)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade900)),
              const Spacer(),
              Text('automatisch aus Stufe 1', style: TextStyle(fontSize: 10, color: Colors.blue.shade700, fontStyle: FontStyle.italic)),
            ]),
            const SizedBox(height: 8),
            TextField(controller: kontaktNameC, decoration: const InputDecoration(labelText: 'Name (Vorname Nachname)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.person, size: 16))),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: kontaktEmailC, decoration: const InputDecoration(labelText: 'E-Mail', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.email, size: 16)))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: kontaktTelC, decoration: const InputDecoration(labelText: 'Telefon / Handy', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone, size: 16)))),
            ]),
          ]),
        ),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        OutlinedButton.icon(
          icon: const Icon(Icons.open_in_browser, size: 16),
          label: const Text('Online anmelden', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.indigo.shade700, side: BorderSide(color: Colors.indigo.shade400)),
          onPressed: () => _launchMszOnline(hilfsmittel: hilfsmittel, schwerhoerig: schwerhoerig, begleit: begleit),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.mail_outline, size: 16),
          label: const Text('E-Mail an MSZ', style: TextStyle(fontSize: 12)),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red.shade700, side: BorderSide(color: Colors.red.shade400)),
          onPressed: () => _sendMailToMsz(
            hilfeTyp: hilfeTyp,
            status: status,
            reiseDatum: datumC.text.trim(),
            reiseUhrzeit: uhrzeitC.text.trim(),
            rueckDatum: rueckDatumC.text.trim(),
            rueckUhrzeit: rueckUhrzeitC.text.trim(),
            vonBahnhof: vonC.text.trim(),
            nachBahnhof: nachC.text.trim(),
            zugTyp: zugTyp,
            zugNummer: zugNrC.text.trim(),
            hilfsmittel: hilfsmittel,
            begleitperson: begleit,
            begleitAnzahl: begleitAnzC.text.trim(),
            schwerhoerig: schwerhoerig,
            hoergeraeteSeite: schwerhoerig ? _gesundheitHoergeraeteSeite : '',
            ticketArt: ticketArt,
            ticketAboNr: ticketArt == 'Deutschland Ticket' ? (_activeDticket?['abo_nr']?.toString() ?? '') : '',
            kontaktName: kontaktNameC.text.trim(),
            kontaktEmail: kontaktEmailC.text.trim(),
            kontaktTelefon: kontaktTelC.text.trim(),
          ),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: _saving ? null : () async {
            setD(() => _saving = true);
            try {
              await widget.apiService.saveDeutscheBahnVorfall(widget.userId, {
                if (isEdit) 'id': existing['id'],
                'typ': hilfeTyp,
                'titel': hilfeTyp,
                'status': status,
                'reise_datum': datumC.text.trim(),
                'reise_uhrzeit': uhrzeitC.text.trim(),
                'rueck_datum': rueckDatumC.text.trim(),
                'rueck_uhrzeit': rueckUhrzeitC.text.trim(),
                'von_bahnhof': vonC.text.trim(),
                'nach_bahnhof': nachC.text.trim(),
                'zug_typ': zugTyp,
                'zug_nummer': zugNrC.text.trim(),
                'hilfe_typ': hilfeTyp,
                'hilfsmittel': hilfsmittel,
                'begleitperson': begleit,
                'begleitperson_anzahl': begleitAnzC.text.trim(),
                'schwerhoerig': schwerhoerig ? 'ja' : 'nein',
                'hoergeraete_seite': schwerhoerig ? _gesundheitHoergeraeteSeite : '',
                'ticket_art': ticketArt,
                'ticket_abo_nr': ticketArt == 'Deutschland Ticket' ? (_activeDticket?['abo_nr']?.toString() ?? '') : '',
              });
              if (ctx.mounted) Navigator.pop(ctx);
              _load();
            } catch (e) {
              if (ctx.mounted) ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
            }
            setD(() => _saving = false);
          },
          child: Text(isEdit ? 'Speichern' : 'Anmelden'),
        ),
      ],
    )));
  }

  /// Build the MSZ e-mail (recipient, subject, body) and show it in-app in a
  /// dialog with individual copy-buttons. No external mail client needed —
  /// the Vorsitzer copies each piece into whichever mail app they use.
  /// MSZ officially accepts requests at msz@deutschebahn.com.
  static const _mszRecipient = 'msz@deutschebahn.com';

  void _sendMailToMsz({
    required String hilfeTyp,
    required String status,
    required String reiseDatum,
    required String reiseUhrzeit,
    required String rueckDatum,
    required String rueckUhrzeit,
    required String vonBahnhof,
    required String nachBahnhof,
    required String zugTyp,
    required String zugNummer,
    required String hilfsmittel,
    required String begleitperson,
    required String begleitAnzahl,
    required bool schwerhoerig,
    required String hoergeraeteSeite,
    required String ticketArt,
    required String ticketAboNr,
    required String kontaktName,
    required String kontaktEmail,
    required String kontaktTelefon,
  }) {
    final route = [vonBahnhof, nachBahnhof].where((s) => s.isNotEmpty).join(' → ');
    final hatRueck = rueckDatum.isNotEmpty || rueckUhrzeit.isNotEmpty;
    final subject = 'Anmeldung Mobilitätshilfe: $hilfeTyp'
        '${route.isNotEmpty ? " ($route)" : ""}'
        '${reiseDatum.isNotEmpty ? " am $reiseDatum" : ""}'
        '${hatRueck ? " (Hin- und Rückfahrt)" : ""}';

    final lines = <String>[
      'Sehr geehrte Damen und Herren der Mobilitätsservice-Zentrale,',
      '',
      'ich möchte hiermit eine Hilfeleistung für folgende Reise anmelden:',
      '',
      '── SCHRITT 1: REISEVERBINDUNG ──',
      'HINFAHRT:',
      if (vonBahnhof.isNotEmpty)     '  Von:            $vonBahnhof',
      if (nachBahnhof.isNotEmpty)    '  Nach:           $nachBahnhof',
      if (reiseDatum.isNotEmpty)     '  Reisedatum:     $reiseDatum',
      if (reiseUhrzeit.isNotEmpty)   '  Uhrzeit:        $reiseUhrzeit',
      if (zugTyp.isNotEmpty)         '  Zugart:         $zugTyp',
      if (zugNummer.isNotEmpty)      '  Zug-Nr.:        $zugNummer',
      if (hatRueck) ...[
        '',
        'RÜCKFAHRT:',
        if (nachBahnhof.isNotEmpty)  '  Von:            $nachBahnhof',
        if (vonBahnhof.isNotEmpty)   '  Nach:           $vonBahnhof',
        if (rueckDatum.isNotEmpty)   '  Reisedatum:     $rueckDatum',
        if (rueckUhrzeit.isNotEmpty) '  Uhrzeit:        $rueckUhrzeit',
      ],
      '',
      '── SCHRITT 2: REISENDER ──',
      'Hilfsmittel:      $hilfsmittel',
      if (schwerhoerig) 'Hörbehinderung:   schwerhörig${hoergeraeteSeite.isNotEmpty ? " (Hörgerät: $hoergeraeteSeite)" : ""}',
      'Begleitperson:    $begleitperson${begleitAnzahl.isNotEmpty ? " (Anzahl: $begleitAnzahl)" : ""}',
      '',
      '── SCHRITT 3: UNTERSTÜTZUNGSBEDARF ──',
      'Art der Hilfe:    $hilfeTyp',
      '',
      '── SCHRITT 4: KONTAKT ──',
      if (kontaktName.isNotEmpty)    'Name:             $kontaktName',
      if (kontaktEmail.isNotEmpty)   'E-Mail:           $kontaktEmail',
      if (kontaktTelefon.isNotEmpty) 'Telefon / Handy:  $kontaktTelefon',
      '',
      if (ticketArt == 'Deutschland Ticket') ...[
        '── FAHRKARTE ──',
        'Ticket:           Deutschland Ticket',
        if (ticketAboNr.isNotEmpty)  'Abo-Nr.:          $ticketAboNr',
        '',
      ],
      'Bitte um Bestätigung.',
      '',
      'Mit freundlichen Grüßen',
      if (kontaktName.isNotEmpty) kontaktName,
    ];
    final body = lines.join('\n');

    showDialog(context: context, builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(width: 720, height: 640, child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
          decoration: BoxDecoration(color: Colors.red.shade50, border: Border(bottom: BorderSide(color: Colors.red.shade200))),
          child: Row(children: [
            Icon(Icons.mail_outline, color: Colors.red.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text('E-Mail für MSZ — bereit zum Kopieren',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade900))),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          _mailFieldBlock(
            label: 'AN (Empfänger)',
            value: _mszRecipient,
            monospace: false,
          ),
          const SizedBox(height: 12),
          _mailFieldBlock(
            label: 'BETREFF',
            value: subject,
            monospace: false,
          ),
          const SizedBox(height: 12),
          _mailFieldBlock(
            label: 'NACHRICHT',
            value: body,
            monospace: true,
            expanded: true,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, minimumSize: const Size.fromHeight(44)),
            icon: const Icon(Icons.copy_all, size: 18),
            label: const Text('Alles kopieren (Empfänger + Betreff + Nachricht)'),
            onPressed: () async {
              final full = 'An: $_mszRecipient\r\nBetreff: $subject\r\n\r\n$body';
              await Clipboard.setData(ClipboardData(text: full));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(
                  content: Text('Vollständige E-Mail kopiert'),
                  backgroundColor: Colors.green,
                ));
              }
            },
          ),
          const SizedBox(height: 8),
          Text(
            'Hinweis: Fügen Sie den Inhalt in Ihrem E-Mail-Programm (Gmail, Outlook, Thunderbird…) ein und senden Sie ab. MSZ bestätigt normalerweise innerhalb weniger Stunden.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
          ),
        ]))),
      ])),
    ));
  }

  /// One block in the e-mail preview dialog: label + selectable content + copy button.
  Widget _mailFieldBlock({required String label, required String value, required bool monospace, bool expanded = false}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.grey.shade200,
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(7), topRight: Radius.circular(7)),
          ),
          child: Row(children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.grey.shade800, letterSpacing: 0.4))),
            InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('$label kopiert'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ));
                }
              },
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.copy, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Text('Kopieren', style: TextStyle(fontSize: 11, color: Colors.blue.shade700, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.all(10),
          child: SelectableText(
            value,
            style: TextStyle(
              fontSize: 12,
              fontFamily: monospace ? 'monospace' : null,
              height: monospace ? 1.35 : 1.2,
            ),
          ),
        ),
      ]),
    );
  }
}
