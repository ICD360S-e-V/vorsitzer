import 'dart:convert';
import 'package:flutter/material.dart';
import 'phone_link.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/external_browser_service.dart';
import '../utils/clipboard_helper.dart';

/// Deutsche Bahn — Mobilitätsservice-Zentrale (MSZ)
///
/// Zwei Tabs:
///   • „Zuständige Deutsche Bahn" — MSZ-Kontaktkarte
///   • „Reiseverbindung" — gespeicherte Strecken des Mitglieds. Der 🌐-Button
///     jeder Verbindung öffnet msz.bahnhof.de im externen Chromium und füllt
///     die Anmeldung selbst aus (_launchMszOnline → _buildMszAutoFillJs):
///     Schritt 1 aus den Mitgliedsdaten (Hilfsmittel aus den Rezepten,
///     Hörbehinderung aus dem Gesundheitsprofil, „nur Nahverkehr" bei
///     vorhandenem Deutschlandticket), Schritt 2 aus dieser Verbindung,
///     Schritt 3 aus Verifizierung Stufe 1 (Anrede, Name, Telefon).
///
/// ⚠️ Die Anmeldung läuft ausschließlich über das Portal — Entscheidung des
/// Users vom 14.08.2026: „facem online că avem buton care completează
/// online datele". Ein zweiter Weg per E-Mail an msz@deutschebahn.com war
/// gebaut (Dialog + fertige Nachricht zum Kopieren) und wurde am selben Tag
/// entfernt, weil er nie benutzt wurde. Wer ihn wiederhaben will, findet ihn
/// vollständig in der Historie; neu schreiben muss ihn niemand.
///
/// ⚠️ Ebenfalls entfernt (14.08.2026): der Vorfall-Tab, das Verzeichnis der
/// Hilfeleistungs-Anmeldungen. Er war schon am 07.07.2026 aus der TabBar
/// genommen worden (96c9b9598, „nicht mehr relevant"), sein Code blieb aber
/// als toter Rest liegen und war die einzige `unused_element`-Warnung des
/// Projekts. Tabelle `deutschebahn_vorfaelle` und die Endpunkte
/// save_vorfall/delete_vorfall bestehen serverseitig unangetastet weiter.
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
  bool _loaded = false, _loading = false;

  Map<String, dynamic> _data = {};
  List<Map<String, dynamic>> _institutionen = [];
  List<Map<String, dynamic>> _dticketVertraege = [];
  bool _gesundheitHoergeraete = false;
  String _gesundheitHoergeraeteSeite = '';
  /// Hilfsmittel-Rezepte des Mitglieds (mitglied_rezepte, alle Arzt-Typen) —
  /// Quelle für die automatische MSZ-Online-Auswahl (E-Rollstuhl etc.).
  List<Map<String, dynamic>> _hilfsmittelRezepte = [];
  /// Gespeicherte Reiseverbindungen (Start/Ziel/Hin/Rück) des Mitglieds —
  /// jede kann per Globus-Button die MSZ-Online-Anmeldung starten (Schritt 1
  /// aus den Mitgliedsdaten, Schritt 2 aus dieser Verbindung).
  List<Map<String, dynamic>> _reiseverbindungen = [];

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
        _reiseverbindungen = (res['reiseverbindungen'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
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
    // ⚠️ Der Rebuild muss bleiben: `_data` wird oben außerhalb von setState
    // geschrieben, sonst zeigt die Karte weiter den alten Wert. Früher hing er
    // am Flag `_saving`, das nur der entfernte Vorfall-Dialog gelesen hat.
    if (mounted) setState(() {});
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
            const SizedBox(width: 4), const Flexible(child: Text('Zuständige Deutsche Bahn', overflow: TextOverflow.ellipsis)),
          ])),
          Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.circle, size: 8, color: _reiseverbindungen.isNotEmpty ? Colors.green : Colors.grey.shade400),
            const SizedBox(width: 4), const Icon(Icons.route, size: 16),
            const SizedBox(width: 4), const Flexible(child: Text('Reiseverbindung', overflow: TextOverflow.ellipsis)),
          ])),
        ],
      ),
      Expanded(child: TabBarView(controller: _tabCtrl, children: [_buildInstitutionTab(), _buildReiseverbindungTab()])),
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
      if (isPhoneIcon(icon)) PhoneCallButton(number: value, label: label, size: 14),
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

  // ────────────────────────── Tab 3: Gespeicherte Reiseverbindungen ──────────────────────────
  Widget _buildReiseverbindungTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 12, 12, 4), child: Row(children: [
        Icon(Icons.route, size: 18, color: Colors.red.shade700), const SizedBox(width: 8),
        // ⚠️ Expanded statt Text + Spacer — die Zeile lief auf dem Pixel 8 um
        // 259 dp über, bei doppelter Systemschrift um 819 dp.
        Expanded(child: Text('${_reiseverbindungen.length} gespeicherte Verbindungen',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
        const SizedBox(width: 8),
        // ⚠️ Bei doppelter Systemschrift lief die Beschriftung um 172 dp über,
        // auf 320 dp um 28. Deshalb wird der Knopf dort zum reinen Symbol —
        // ihn kleiner zu skalieren würde genau die große Schrift zurücknehmen,
        // die das Mitglied eingestellt hat. Die Trefferfläche bleibt 48 dp.
        Builder(builder: (c) {
          final knapp = MediaQuery.of(c).size.width < 380 || MediaQuery.of(c).textScaler.scale(12) > 15;
          if (knapp) {
            return IconButton(
              tooltip: 'Neue Reiseverbindung',
              icon: Icon(Icons.add_circle, color: Colors.red.shade600),
              onPressed: () => _showReiseverbindungDialog(),
            );
          }
          return FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neue Reiseverbindung', style: TextStyle(fontSize: 12)),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), minimumSize: Size.zero),
            onPressed: () => _showReiseverbindungDialog(),
          );
        }),
      ])),
      Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline, size: 13, color: Colors.grey.shade500), const SizedBox(width: 6),
        // Kurz gehalten: bei doppelter Systemschrift schiebt jede Zeile hier
        // die erste Verbindung weiter unter den Bildschirmrand.
        Expanded(child: Text('Häufige Strecken speichern (z. B. Ulm → Saarbrücken). Der 🌐-Button öffnet die MSZ-Online-Anmeldung: Schritt 1 aus den Mitgliedsdaten, Schritt 2 aus dieser Verbindung.',
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic))),
      ])),
      const SizedBox(height: 8),
      Expanded(child: _reiseverbindungen.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.route, size: 48, color: Colors.grey.shade300),
            const SizedBox(height: 8),
            Text('Keine Reiseverbindungen gespeichert', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: _reiseverbindungen.length, itemBuilder: (_, i) {
            final rv = _reiseverbindungen[i];
            final start = rv['start_bahnhof']?.toString() ?? '';
            final ziel = rv['ziel_bahnhof']?.toString() ?? '';
            final route = [start, ziel].where((s) => s.isNotEmpty).join(' → ');
            final hin = '${rv['hin_datum'] ?? ''}'.trim();
            final rueck = '${rv['rueck_datum'] ?? ''}'.trim();
            final name = rv['name']?.toString() ?? '';
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Colors.red.shade50, child: Icon(Icons.route, size: 18, color: Colors.red.shade700)),
                title: Text(name.isNotEmpty ? name : (route.isNotEmpty ? route : '—'), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (name.isNotEmpty && route.isNotEmpty) Text(route, style: const TextStyle(fontSize: 11)),
                  if (hin.isNotEmpty) Text('Hin: $hin', style: const TextStyle(fontSize: 11)),
                  if (rueck.isNotEmpty) Text('Rück: $rueck', style: const TextStyle(fontSize: 11)),
                ]),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(
                    tooltip: 'Online anmelden (MSZ) — Schritt 1 + 2 automatisch',
                    icon: Icon(Icons.public, color: Colors.indigo.shade600),
                    onPressed: () => _launchMszOnline(reiseverbindung: rv),
                  ),
                  PopupMenuButton<String>(
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 16), SizedBox(width: 8), Text('Bearbeiten')])),
                      const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 16, color: Colors.red), SizedBox(width: 8), Text('Löschen', style: TextStyle(color: Colors.red))])),
                    ],
                    onSelected: (a) {
                      if (a == 'edit') _showReiseverbindungDialog(existing: rv);
                      if (a == 'delete') _deleteReiseverbindung(rv);
                    },
                  ),
                ]),
                onTap: () => _showReiseverbindungDialog(existing: rv),
              ),
            );
          })),
    ]);
  }

  Future<void> _deleteReiseverbindung(Map<String, dynamic> rv) async {
    final c = await showDialog<bool>(context: context, builder: (d) => AlertDialog(
      title: const Text('Reiseverbindung löschen?'),
      content: Text(rv['name']?.toString().isNotEmpty == true ? rv['name'].toString() : '${rv['start_bahnhof'] ?? ''} → ${rv['ziel_bahnhof'] ?? ''}'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(d, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(d, true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Löschen')),
      ],
    ));
    if (c != true) return;
    await widget.apiService.deleteDeutscheBahnReiseverbindung(widget.userId, int.tryParse(rv['id'].toString()) ?? 0);
    _load();
  }

  void _showReiseverbindungDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    final nameC = TextEditingController(text: existing?['name']?.toString() ?? '');
    final startC = TextEditingController(text: existing?['start_bahnhof']?.toString() ?? '');
    final zielC = TextEditingController(text: existing?['ziel_bahnhof']?.toString() ?? '');
    final hinDatumC = TextEditingController(text: existing?['hin_datum']?.toString() ?? '');
    final rueckDatumC = TextEditingController(text: existing?['rueck_datum']?.toString() ?? '');

    Future<void> pickDate(TextEditingController c) async {
      final p = await showDatePicker(context: context, initialDate: DateTime.now(), firstDate: DateTime.now().subtract(const Duration(days: 1)), lastDate: DateTime(2040), locale: const Locale('de'));
      if (p != null) c.text = '${p.day.toString().padLeft(2, '0')}.${p.month.toString().padLeft(2, '0')}.${p.year}';
    }

    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      title: Text(isEdit ? 'Reiseverbindung bearbeiten' : 'Neue Reiseverbindung'),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Name (optional, z. B. Heimreise)', isDense: true, border: OutlineInputBorder())),
        const SizedBox(height: 12),
        const Text('Strecke', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(controller: startC, decoration: const InputDecoration(labelText: 'Start-Bahnhof (z. B. Ulm Hbf)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.train, size: 16))),
        const SizedBox(height: 10),
        TextField(controller: zielC, decoration: const InputDecoration(labelText: 'Ziel-Bahnhof (z. B. Saarbrücken Hbf)', isDense: true, border: OutlineInputBorder(), prefixIcon: Icon(Icons.flag, size: 16))),
        const SizedBox(height: 14),
        const Text('Hinfahrt (Datum)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(controller: hinDatumC, readOnly: true, onTap: () => pickDate(hinDatumC), decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16))),
        const SizedBox(height: 14),
        const Text('Rückfahrt (Datum, optional)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        TextField(controller: rueckDatumC, readOnly: true, onTap: () => pickDate(rueckDatumC), decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
          onPressed: () async {
            if (startC.text.trim().isEmpty || zielC.text.trim().isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('Start- und Ziel-Bahnhof sind Pflicht'), backgroundColor: Colors.red));
              return;
            }
            await widget.apiService.saveDeutscheBahnReiseverbindung(widget.userId, {
              if (isEdit) 'id': existing['id'],
              'name': nameC.text.trim(),
              'start_bahnhof': startC.text.trim(),
              'ziel_bahnhof': zielC.text.trim(),
              'hin_datum': hinDatumC.text.trim(),
              'rueck_datum': rueckDatumC.text.trim(),
            });
            if (ctx.mounted) Navigator.pop(ctx);
            _load();
          },
          child: Text(isEdit ? 'Speichern' : 'Anlegen'),
        ),
      ],
    ));
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

    // combo = Enum-VALUES des nativen <select> (nicht Labels!) — das MSZ-Formular
    // rendert ein natives <select><optgroup label="Rollstuhl"><option value="WheelchairElectric">
    // Elektrorollstuhl, Elektromobil</option>… und liest e.target.value.
    final checks = <String>[];
    final combo = <String>[];
    if (eRoll || rollator || manualRoll) {
      checks.add('reise mit einem Hilfsmittel');
      if (eRoll) {
        combo.add('WheelchairElectric');   // Elektrorollstuhl, Elektromobil
        combo.add('UpTo250kg');            // Gesamtgewicht (Rollstuhl + Person + Gepäck) bis 250 kg
      } else if (rollator) {
        combo.add('Rollator');
      } else if (manualRoll) {
        combo.add('Wheelchair');           // Manueller Rollstuhl
      }
    }
    if (blindstock || blindfuehr) checks.add('blind oder sehbeeinträchtigt');
    // Eigenständige Kategorie (unabhängig vom Hilfsmittel): Hörgeräte im
    // Gesundheitsprofil → otherImpairment-Select auf „Taubheit oder Schwerhörigkeit".
    // „Andere Einschränkungen oder Hilfebedarf" ist KEINE Checkbox — es ist eine
    // Karte mit <b>-Titel und direkt sichtbarem <select> (kein Ankreuzen nötig).
    // Der Select nutzt das LABEL als option-value und liest onChange den
    // selectedIndex — daher das Label übergeben, nicht das Enum.
    if (schwerhoerig) {
      combo.add('Taubheit oder Schwerhörigkeit');
    }
    if (begleit == 'ja') checks.add('Begleitperson');
    if (blindfuehr) checks.add('Assistenzhund');
    return (checks: checks, combo: combo);
  }

  /// MSZ-Anrede aus dem Geschlecht: männlich → „Herr", weiblich → „Frau",
  /// sonst leer (MSZ hat zusätzlich „Neutrale Anrede", die lassen wir offen).
  String _anredeVonGeschlecht(String? g) {
    final s = (g ?? '').trim().toLowerCase();
    if (s == 'm' || s == 'männlich' || s == 'herr' || s == 'male') return 'Herr';
    if (s == 'w' || s == 'weiblich' || s == 'frau' || s == 'female') return 'Frau';
    return '';
  }

  /// Öffnet das MSZ-Portal im externen Chromium und füllt aus:
  ///   • Schritt 1 — aus den Mitgliedsdaten (Hilfsmittel-Rezepte, Hörgeräte).
  ///   • Schritt 2 — aus [reiseverbindung] (Start/Ziel/Hin/Rück), falls gesetzt.
  ///
  /// Einziger Aufrufer ist der 🌐-Knopf am Reiseverbindung-Tab; er übergibt
  /// nur [reiseverbindung], sodass für Schritt 1 die Mitglieds-Defaults
  /// greifen. Die drei übrigen Parameter stammen aus der Zeit des
  /// Vorfall-Dialogs (entfernt 14.08.2026) und bleiben als Übersteuerung
  /// erhalten — sie kosten nichts und ersparen eine Signaturänderung, falls
  /// je wieder ein Aufrufer mit eigenen Angaben dazukommt.
  Future<void> _launchMszOnline({String hilfsmittel = '', bool? schwerhoerig, String begleit = 'nein', Map<String, dynamic>? reiseverbindung}) async {
    final sh = schwerhoerig ?? _gesundheitHoergeraete;
    final picks = _computeMszPicks(hilfsmittel: hilfsmittel, schwerhoerig: sh, begleit: begleit);
    final weitere = sh
        ? 'Schwerhörig / Hörbehinderung${_gesundheitHoergeraeteSeite.isNotEmpty ? " (Hörgerät: $_gesundheitHoergeraeteSeite)" : ""}'
        : '';
    final rv = reiseverbindung == null ? <String, String>{} : {
      'start': reiseverbindung['start_bahnhof']?.toString() ?? '',
      'ziel': reiseverbindung['ziel_bahnhof']?.toString() ?? '',
      'hin_datum': reiseverbindung['hin_datum']?.toString() ?? '',
      'hin_uhrzeit': reiseverbindung['hin_uhrzeit']?.toString() ?? '',
      'rueck_datum': reiseverbindung['rueck_datum']?.toString() ?? '',
      'rueck_uhrzeit': reiseverbindung['rueck_uhrzeit']?.toString() ?? '',
      // „Nur Nahverkehr" nur setzen, wenn das Mitglied ein Deutschland-Ticket hat
      // (Behörde → Deutschlandticket → Vertrag vorhanden).
      'nur_nahverkehr': _dticketVertraege.isNotEmpty ? '1' : '',
    };
    // Schritt 3 „Reisende:r" — Kontakt aus Verifizierung Stufe 1 (widget.user).
    // Anrede aus geschlecht; E-Mail fest icd@icd360s.de (unabhängig vom Mitglied);
    // Telefon = Mobil > Festnetz.
    final contact = {
      'anrede': _anredeVonGeschlecht(widget.user.geschlecht),
      'vorname': (widget.user.vorname ?? '').trim(),
      'nachname': (widget.user.nachname ?? '').trim(),
      'email': 'icd@icd360s.de',
      'telefon': ((widget.user.telefonMobil ?? '').trim().isNotEmpty
          ? (widget.user.telefonMobil ?? '')
          : (widget.user.telefonFix ?? '')).trim(),
    };
    final all = [...picks.checks, ...picks.combo, if (rv['start']?.isNotEmpty == true) '${rv['start']} → ${rv['ziel']}'];
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
      autoFillJs: _buildMszAutoFillJs(picks.checks, picks.combo, weitere, rv, contact),
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
  String _buildMszAutoFillJs(List<String> checks, List<String> combo, String weitere, Map<String, String> rv, Map<String, String> contact) {
    final checksJson = jsonEncode(checks);
    final comboJson = jsonEncode(combo);
    final weitereJson = jsonEncode(weitere);
    final rvJson = jsonEncode(rv);
    final contactJson = jsonEncode(contact);
    return '''
(() => {
  // Gemeinsamer Zustand pro Frame — überlebt Re-Injektionen (evaluateOnNewDocument
  // + onLoad + evaluate feuern das Skript mehrfach). Damit klickt KEINE zweite
  // Skript-Instanz eine schon gesetzte Option erneut → kein Umschalten (Toggle).
  const S = (window.__icd_msz = window.__icd_msz || { acted: {}, comboOpened: 0 });
  const log = (...a) => { try { console.warn('[ICD-MSZ]', ...a); } catch (_) {} };
  if (S.loopRunning) { log('loop läuft bereits in diesem Frame — skip'); return; }
  S.loopRunning = true;
  const RV = $rvJson;  // Schritt 2: {start, ziel, hin_datum, rueck_datum, nur_nahverkehr}
  const C3 = $contactJson;  // Schritt 3: {anrede, vorname, nachname, email, telefon}

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

  // Setzt einen Formularwert per Ziel-String. Deckt die MSZ-Muster ab:
  //   1) natives <select> — option matcht per VALUE (Hilfsmittel: value=Enum
  //      "WheelchairElectric") ODER per sichtbarem TEXT/Label (otherImpairment:
  //      value=Label "Taubheit oder Schwerhörigkeit", onChange liest selectedIndex).
  //      Deshalb: value setzen UND selectedIndex explizit setzen + change feuern.
  //   2) Radio-Button (input[type=radio] oder [role=radio]) mit value=… (Gewicht).
  // Nicht auf Sichtbarkeit filtern — db-Komponenten verstecken evtl. das native Element.
  const selectAid = (target) => {
    const nt = norm(target);
    for (const sel of document.querySelectorAll('select')) {
      const opts = [...(sel.options || [])];
      let opt = opts.find(o => o.value === target);
      if (!opt) opt = opts.find(o => norm(o.textContent) === nt);
      if (!opt && nt.length > 4) opt = opts.find(o => norm(o.textContent).includes(nt) || norm(o.value).includes(nt));
      if (!opt) continue;
      if (sel.selectedIndex === opt.index) return true; // schon gesetzt
      sel.scrollIntoView({ block: 'center' });
      const setter = Object.getOwnPropertyDescriptor(window.HTMLSelectElement.prototype, 'value')?.set;
      if (setter) setter.call(sel, opt.value); else sel.value = opt.value;
      sel.selectedIndex = opt.index;   // manche Felder lesen onChange den selectedIndex
      sel.dispatchEvent(new Event('input', { bubbles: true }));
      sel.dispatchEvent(new Event('change', { bubbles: true }));
      log('Select →', target, 'idx=' + opt.index, JSON.stringify((opt.textContent || opt.value || '').trim()));
      return true;
    }
    for (const r of document.querySelectorAll('input[type=radio],[role=radio]')) {
      const v = r.value || r.getAttribute('value') || '';
      if (v !== target && norm(r.getAttribute('aria-label') || '') !== nt) continue;
      if (r.checked || r.getAttribute('aria-checked') === 'true') return true; // schon gesetzt
      r.scrollIntoView({ block: 'center' });
      r.click();
      log('Radio →', target);
      return true;
    }
    return false;
  };

  // ── Schritt 2 (Reiseverbindung) ──
  // MSZ ist eine SPA: der Wechsel Schritt 1 → 2 lädt KEIN neues Dokument, das Skript
  // wird also NICHT neu injiziert. Deshalb bleibt DIESE Schleife aktiv (langer
  // Timeout, solange RV gesetzt), bis Schritt 2 gefüllt ist.
  // Struktur laut Bundle: startStopPlace/endStopPlace = <input type=search> mit
  // floating Label „Startbahnhof"/„Zielbahnhof" + <ul><li>-Vorschlägen; tripType =
  // role=tab-Segmente („Einfache Fahrt" / „Hin- und Rückfahrt"); Datum = <input type=date>.
  const de2iso = (d) => { const m = /^(\\d{2})\\.(\\d{2})\\.(\\d{4})\$/.exec((d || '').trim()); return m ? m[3] + '-' + m[2] + '-' + m[1] : ''; };

  const stationInput = (labelRe) => {
    return [...document.querySelectorAll('input')].filter(isUsable).find(i => {
      const id = i.getAttribute('id');
      const lbl = id ? document.querySelector('label[for="' + id + '"]') : null;
      const blob = (i.getAttribute('aria-label') || '') + ' ' + (lbl ? lbl.textContent : '') + ' ' + ((i.closest('div,section,fieldset') || {}).innerText || '');
      return labelRe.test(blob);
    }) || null;
  };

  // Klick, der auch Combobox-/Menü-Optionen zuverlässig auswählt: viele reagieren
  // auf mousedown (onClick käme nach dem Blur, wenn die Liste schon zu ist). Deshalb
  // brauchte der Zielbahnhof-Vorschlag bisher eine manuelle Bestätigung.
  const fireClick = (el) => {
    el.scrollIntoView({ block: 'center' });
    for (const t of ['pointerdown', 'mousedown', 'mouseup', 'click']) {
      el.dispatchEvent(new MouseEvent(t, { bubbles: true, cancelable: true, view: window }));
    }
  };

  // Rückgabe: 'done' | 'pending' | 'absent'.
  const fillStation = (key, value, labelRe) => {
    if (!value || S.acted[key] === 'done') return 'done';
    const inp = stationInput(labelRe);
    if (!inp) return 'absent';
    if (S.acted[key] !== 'typed') {
      inp.focus();
      setNativeValue(inp, value);
      inp.dispatchEvent(new KeyboardEvent('keydown', { bubbles: true }));
      inp.dispatchEvent(new KeyboardEvent('keyup', { bubbles: true }));
      S.acted[key] = 'typed';
      log('S2 Bahnhof getippt', key, JSON.stringify(value));
      return 'pending';
    }
    const nt = norm(value.split(/[ ,(]/)[0]);
    const opt = [...document.querySelectorAll('li,[role=option]')].filter(isUsable).find(o => norm(o.textContent).includes(nt));
    if (!opt) return 'pending';
    fireClick(opt);
    S.acted[key] = 'done';
    log('S2 Bahnhof gewählt', key, JSON.stringify((opt.textContent || '').trim()));
    return 'done';
  };

  const clickTripTwoWay = () => {
    if (S.acted.tripType) return;
    if (!RV.rueck_datum) { S.acted.tripType = 1; return; }   // ohne Rückdatum: einfache Fahrt reicht
    const seg = [...document.querySelectorAll('[role=tab],button,label,span,div')].filter(isUsable)
      .find(el => norm(el.innerText || el.textContent) === 'hin- und rückfahrt');
    if (seg) { fireClick(seg); S.acted.tripType = 1; log('S2 Hin- und Rückfahrt gewählt'); }
  };

  const fillDates = () => {
    const dates = [...document.querySelectorAll('input[type=date]')].filter(isUsable);
    if (dates[0] && RV.hin_datum && !S.acted.s2_hin_d) {
      const iso = de2iso(RV.hin_datum);
      if (iso) { setNativeValue(dates[0], iso); S.acted.s2_hin_d = 1; log('S2 Hindatum', iso); }
    }
    if (dates[1] && RV.rueck_datum && !S.acted.s2_rueck_d) {
      const iso = de2iso(RV.rueck_datum);
      if (iso) { setNativeValue(dates[1], iso); S.acted.s2_rueck_d = 1; log('S2 Rückdatum', iso); }
    }
  };

  // „Verkehrsmittel auswählen" → „Nur Nahverkehr" (Iu.LOCAL) — NUR wenn das Mitglied
  // ein Deutschland-Ticket hat. Das Dropdown klappt nach unten auf: erst den Trigger
  // klicken, dann die Option „Nur Nahverkehr".
  const selectNahverkehr = () => {
    if (!RV.nur_nahverkehr || S.acted.nahverkehr) return true;
    const opt = [...document.querySelectorAll('li,[role=option],[role=menuitem],button,a,span,div')].filter(isUsable)
      .find(el => norm(el.innerText || el.textContent) === 'nur nahverkehr');
    if (opt) { fireClick(opt); S.acted.nahverkehr = 1; log('S2 Nur Nahverkehr gewählt'); return true; }
    if ((S.acted.vmOpen || 0) < 5) {
      const cands = [...document.querySelectorAll('button,[role=button],[aria-haspopup],summary,div,span')].filter(isUsable)
        .filter(el => /verkehrsmittel/i.test((el.innerText || el.textContent || '') + ' ' + (el.getAttribute('aria-label') || '')));
      const trig = cands.sort((a, b) => (a.innerText || '').length - (b.innerText || '').length)[0];
      if (trig) { fireClick(trig); S.acted.vmOpen = (S.acted.vmOpen || 0) + 1; log('S2 Verkehrsmittel-Dropdown geöffnet #' + S.acted.vmOpen); }
    }
    return false;
  };

  const fillSchritt2 = () => {
    if (!RV || !RV.start) return true;                       // keine Reiseverbindung
    const s = fillStation('s2_start', RV.start, /start/i);
    if (s === 'absent') return false;                        // noch nicht auf Schritt 2 → Schleife am Leben halten
    clickTripTwoWay();
    fillDates();
    const nv = selectNahverkehr();
    if (s !== 'done') return false;                          // Start zuerst fertig
    const z = fillStation('s2_ziel', RV.ziel, /ziel/i);
    return z === 'done' && nv;
  };

  // ── Schritt 3 (Reisende:r) — Kontakt. Anrede = <select> (Herr/Frau/Neutrale
  // Anrede; option-value = Enum, Label = Text) → selectAid per Label. Vorname/
  // Nachname/E-Mail/Mobilfunknummer = Textfelder mit floating Label.
  const fillTextByLabel = (key, value, labelRe) => {
    if (!value || S.acted[key] === 'done') return 'done';
    const inp = [...document.querySelectorAll('input,textarea')].filter(isUsable).find(i => {
      const id = i.getAttribute('id');
      const lbl = id ? document.querySelector('label[for="' + id + '"]') : null;
      const own = (i.getAttribute('aria-label') || '') + ' ' + (i.getAttribute('name') || '') + ' ' + (i.getAttribute('placeholder') || '') + ' ' + (lbl ? lbl.textContent : '');
      return labelRe.test(own);
    });
    if (!inp) return 'absent';
    inp.focus();
    setNativeValue(inp, value);
    inp.dispatchEvent(new Event('blur', { bubbles: true }));
    S.acted[key] = 'done';
    log('S3 Feld gefüllt', key, JSON.stringify(value));
    return 'done';
  };

  const fillSchritt3 = () => {
    if (!C3) return true;
    const vn = fillTextByLabel('s3_vorname', C3.vorname, /vorname/i);
    if (vn === 'absent') return false;                       // nicht auf Schritt 3 → Schleife am Leben halten
    fillTextByLabel('s3_nachname', C3.nachname, /nachname/i);
    fillTextByLabel('s3_email', C3.email, /e-?mail/i);
    fillTextByLabel('s3_tel', C3.telefon, /mobilfunk|mobil|telefon|handy/i);
    if (C3.anrede && !S.acted.s3_anrede && selectAid(C3.anrede)) S.acted.s3_anrede = 1;
    return !!S.acted.s3_vorname && (!C3.anrede || !!S.acted.s3_anrede);
  };

  const start = Date.now();
  // Bei gesetzter Reiseverbindung länger laufen — der Nutzer navigiert selbst zu
  // Schritt 2 (SPA, kein Reload), die Schleife muss so lange am Leben bleiben.
  const MAX_MS = (RV && RV.start) ? 300000 : 45000;
  let n = 0;
  const tick = () => {
    n++;
    if (Date.now() - start > MAX_MS) { S.loopRunning = false; log('timeout', JSON.stringify(S.acted)); return; }
    let remaining = 0;
    for (const c of CHECKS) if (!ensureChecked(c)) remaining++;
    for (const o of COMBO) {
      if (S.acted['o:' + o]) continue;
      if (selectAid(o)) S.acted['o:' + o] = 1; else remaining++;
    }
    if (!fillSchritt2()) remaining++;
    if (!fillSchritt3()) remaining++;
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
}
