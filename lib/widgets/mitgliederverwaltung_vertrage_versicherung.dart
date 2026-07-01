import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'mitgliederverwaltung_vertraege.dart' show VertragDokTab, VertragKorrTab;

// ============================================================
// MITGLIEDERVERWALTUNG → VERTRÄGE → VERSICHERUNG
//
// The Versicherung sub-tab of vertraege_content lives here because
// insurance contracts branch into 11 Sparten (KFZ, Haftpflicht,
// Hausrat, Leben, Kranken, Rechtsschutz, Unfall, BU, Reise, Tier,
// Sonstige). Each Sparte-Tab holds two sub-tabs:
//   - "Zuständige Versicherung"  → the companies covering the member
//     for that Sparte (union of active-contract-derived + explicitly
//     marked via user_versicherungen). Lupe-search to add extra.
//   - "Vertrag"                   → contracts filed under that Sparte.
//
// The Neuer-Vertrag-Dialog defaults to the current Sparte and pre-
// filters the Versicherung-Auswahl to companies that actually list
// that Sparte in their coverage — cuts down the pick list from 71+
// firms to only the relevant ones.
// ============================================================

const _versicherungSparten = <String, String>{
  'kfz': 'KFZ-Versicherung',
  'haftpflicht': 'Privathaftpflicht',
  'hausrat': 'Hausratversicherung',
  'leben': 'Lebensversicherung',
  'kranken': 'Krankenzusatzversicherung',
  'rechtsschutz': 'Rechtsschutzversicherung',
  'unfall': 'Unfallversicherung',
  'berufsunfaehigkeit': 'Berufsunfähigkeit',
  'reise': 'Reise-/Auslandsversicherung',
  'tier': 'Tierversicherung',
  'sonstige': 'Sonstige',
};

const _versicherungSpartenIcons = <String, IconData>{
  'kfz': Icons.directions_car,
  'haftpflicht': Icons.security,
  'hausrat': Icons.home,
  'leben': Icons.favorite,
  'kranken': Icons.medical_services,
  'rechtsschutz': Icons.gavel,
  'unfall': Icons.warning_amber,
  'berufsunfaehigkeit': Icons.work,
  'reise': Icons.flight,
  'tier': Icons.pets,
  'sonstige': Icons.more_horiz,
};

class MitgliederverwaltungVertraegeVersicherung extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final List<Map<String, dynamic>> vertraege;
  final Future<void> Function() onChanged;
  const MitgliederverwaltungVertraegeVersicherung({
    super.key,
    required this.apiService,
    required this.userId,
    required this.vertraege,
    required this.onChanged,
  });

  @override
  State<MitgliederverwaltungVertraegeVersicherung> createState() =>
      _MitgliederverwaltungVertraegeVersicherungState();
}

class _MitgliederverwaltungVertraegeVersicherungState
    extends State<MitgliederverwaltungVertraegeVersicherung> {
  List<Map<String, dynamic>> _versicherungen = [];
  // Explicitly-marked "Zuständige" companies per sparte (from
  // user_versicherungen). Each entry: {id, versicherung_id, sparte, ...v fields}
  List<Map<String, dynamic>> _userMarked = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final r  = await widget.apiService.getVersicherungen();
    final ur = await widget.apiService.listUserVersicherungen(widget.userId);
    if (!mounted) return;
    setState(() {
      _versicherungen = (r['success'] == true && r['data'] is List)
          ? (r['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      _userMarked = (ur['success'] == true && ur['data'] is List)
          ? (ur['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
      _loaded = true;
    });
  }

  Map<int, Map<String, dynamic>> get _byId {
    final out = <int, Map<String, dynamic>>{};
    for (final v in _versicherungen) {
      final id = int.tryParse(v['id']?.toString() ?? '');
      if (id != null) out[id] = v;
    }
    return out;
  }

  /// Companies that offer a given Sparte — filtered from the master list
  /// by checking whether the sparte string contains the key.
  List<Map<String, dynamic>> _versicherungenFuerSparte(String sparte) {
    return _versicherungen.where((v) {
      final s = (v['sparte']?.toString() ?? '').toLowerCase();
      return s.split(',').map((e) => e.trim()).contains(sparte);
    }).toList();
  }

  /// Zuständige for a Sparte = union of:
  ///   - companies that appear in an active contract of that sparte
  ///   - user-marked entries for that sparte in user_versicherungen
  /// Each entry: {vers: {...}, markingId?: N, viaContract: bool}
  List<Map<String, dynamic>> _zustaendigeFuerSparte(String sparte) {
    final byId = _byId;
    final result = <Map<String, dynamic>>[];
    final seen = <int>{};

    for (final c in widget.vertraege) {
      if ((c['tarif']?.toString() ?? '') != sparte) continue;
      final vid = int.tryParse(c['versicherung_id']?.toString() ?? '');
      if (vid == null || byId[vid] == null || seen.contains(vid)) continue;
      seen.add(vid);
      result.add({'vers': byId[vid]!, 'viaContract': true});
    }
    for (final m in _userMarked) {
      if ((m['sparte']?.toString() ?? '') != sparte) continue;
      final vid = int.tryParse(m['versicherung_id']?.toString() ?? '');
      if (vid == null || byId[vid] == null || seen.contains(vid)) continue;
      seen.add(vid);
      final markingId = int.tryParse(m['id']?.toString() ?? '');
      result.add({'vers': byId[vid]!, 'viaContract': false, 'markingId': markingId});
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final sparten = _versicherungSparten.entries.toList();
    return DefaultTabController(
      length: sparten.length,
      child: Column(children: [
        Material(
          color: Colors.green.shade50,
          child: TabBar(
            isScrollable: true,
            labelColor: Colors.green.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.green.shade700,
            tabs: sparten.map((s) {
              final n = widget.vertraege.where((v) => v['tarif']?.toString() == s.key).length;
              return Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(_versicherungSpartenIcons[s.key] ?? Icons.shield, size: 14),
                const SizedBox(width: 4),
                Text('${s.value} ($n)'),
              ]));
            }).toList(),
          ),
        ),
        Expanded(child: TabBarView(
          children: sparten.map((s) => _buildSpartePane(s.key, s.value)).toList(),
        )),
      ]),
    );
  }

  // ============ SPARTE-PANE — 2 Sub-Sub-Tabs (Zuständige + Vertrag) ============
  Widget _buildSpartePane(String sparteKey, String sparteLabel) {
    final zustaendige = _zustaendigeFuerSparte(sparteKey);
    final vertraegeInSparte = widget.vertraege.where((v) => v['tarif']?.toString() == sparteKey).toList();
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Material(
          color: Colors.green.shade50.withValues(alpha: 0.5),
          child: TabBar(
            labelColor: Colors.green.shade800,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.green.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: zustaendige.isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4),
                const Icon(Icons.shield, size: 12),
                const SizedBox(width: 4),
                Text('Zuständige Versicherung (${zustaendige.length})', style: const TextStyle(fontSize: 11)),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: vertraegeInSparte.isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4),
                const Icon(Icons.description, size: 12),
                const SizedBox(width: 4),
                Text('Vertrag (${vertraegeInSparte.length})', style: const TextStyle(fontSize: 11)),
              ])),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _buildZustaendigePane(sparteKey, sparteLabel, zustaendige),
          _buildVertragPane(sparteKey, sparteLabel, vertraegeInSparte),
        ])),
      ]),
    );
  }

  Widget _buildZustaendigePane(String sparteKey, String sparteLabel, List<Map<String, dynamic>> zustaendige) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.shield, size: 18, color: Colors.green.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text('Zuständige $sparteLabel',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800))),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 14),
            label: const Text('Versicherung wählen', style: TextStyle(fontSize: 11)),
            onPressed: () async {
              final picked = await _showVersicherungSearch(context, sparteKey: sparteKey);
              if (picked == null) return;
              final vid = int.tryParse(picked['id']?.toString() ?? '');
              if (vid == null) return;
              await widget.apiService.addUserVersicherung(widget.userId, vid, sparte: sparteKey);
              await _load();
            },
            style: OutlinedButton.styleFrom(foregroundColor: Colors.green.shade700),
          ),
        ]),
        const SizedBox(height: 12),
        if (zustaendige.isEmpty)
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(children: [
              Icon(Icons.shield_outlined, size: 36, color: Colors.grey.shade400),
              const SizedBox(height: 8),
              Text('Keine Zuständige Versicherung',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 4),
              Text('Tippen Sie auf "Versicherung wählen" oder legen Sie einen Vertrag an.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ]),
          )
        else
          ...zustaendige.map((e) {
            final v = e['vers'] as Map<String, dynamic>;
            final viaContract = e['viaContract'] == true;
            final markingId = e['markingId'] as int?;
            final contractsHere = widget.vertraege.where((c) =>
              (c['tarif']?.toString() ?? '') == sparteKey &&
              c['versicherung_id']?.toString() == v['id']?.toString()).toList();
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.green.shade300),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.shield, size: 20, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(v['name']?.toString() ?? '',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade900))),
                  if (contractsHere.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(8)),
                      child: Text('${contractsHere.length} Vertrag',
                        style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  if (!viaContract && markingId != null)
                    IconButton(
                      icon: Icon(Icons.close, size: 16, color: Colors.red.shade400),
                      tooltip: 'Markierung entfernen',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                      onPressed: () async {
                        await widget.apiService.deleteUserVersicherung(markingId);
                        await _load();
                      },
                    ),
                ]),
                const SizedBox(height: 6),
                if ((v['strasse']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.place, '${v['strasse']}, ${v['plz_ort']}'),
                if ((v['telefon']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.phone, v['telefon'].toString()),
                if ((v['fax']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.print, 'Fax: ${v['fax']}'),
                if ((v['email']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.email, v['email'].toString()),
                if ((v['website']?.toString() ?? '').isNotEmpty)
                  _infoRow(Icons.language, v['website'].toString()),
              ]),
            );
          }),
      ]),
    );
  }

  Widget _infoRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Icon(icon, size: 12, color: Colors.green.shade600),
        const SizedBox(width: 6),
        Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.green.shade800))),
      ]),
    );
  }

  Widget _buildVertragPane(String sparteKey, String sparteLabel, List<Map<String, dynamic>> vertraegeInSparte) {
    final byId = _byId;
    final aktive = vertraegeInSparte.where((v) => v['is_active'] == 1 || v['is_active'] == true || v['is_active'] == '1').toList();
    final inaktive = vertraegeInSparte.where((v) => !(v['is_active'] == 1 || v['is_active'] == true || v['is_active'] == '1')).toList();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 6), child: Row(children: [
        Icon(Icons.description, size: 18, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('$sparteLabel — Verträge (${vertraegeInSparte.length})',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700))),
        ElevatedButton.icon(
          onPressed: () => _addVertragDialog(defaultSparte: sparteKey),
          icon: const Icon(Icons.add, size: 14),
          label: const Text('Neuer Vertrag', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green.shade700,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          ),
        ),
      ])),
      Expanded(child: vertraegeInSparte.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_versicherungSpartenIcons[sparteKey] ?? Icons.description_outlined, size: 44, color: Colors.grey.shade300),
              const SizedBox(height: 8),
              Text('Keine Verträge in $sparteLabel', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
            ]))
          : ListView(padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              ...aktive.map((v) => _buildVertragCard(v, byId, aktiv: true)),
              if (inaktive.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 12, bottom: 6),
                  child: Text('Beendet / Gekündigt',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w600)),
                ),
                ...inaktive.map((v) => _buildVertragCard(v, byId, aktiv: false)),
              ],
            ])),
    ]);
  }

  Widget _buildVertragCard(Map<String, dynamic> v, Map<int, Map<String, dynamic>> byId, {required bool aktiv}) {
    final versId = int.tryParse(v['versicherung_id']?.toString() ?? '');
    final versName = versId != null ? (byId[versId]?['name']?.toString() ?? v['versicherung_name']?.toString() ?? '?') : (v['anbieter']?.toString() ?? '?');
    final sparteKey = v['tarif']?.toString() ?? '';
    final sparteLabel = _versicherungSparten[sparteKey] ?? sparteKey;
    final color = aktiv ? Colors.green : Colors.grey;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.shade100,
          child: Icon(Icons.shield, color: color.shade800),
        ),
        title: Text(versName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sparteLabel.isNotEmpty)
            Text(sparteLabel, style: TextStyle(fontSize: 11, color: color.shade700, fontWeight: FontWeight.w600)),
          if ((v['vertragsnummer']?.toString() ?? '').isNotEmpty)
            Text('Nr.: ${v['vertragsnummer']}', style: const TextStyle(fontSize: 11)),
          if ((v['vertragsbeginn']?.toString() ?? '').isNotEmpty)
            Text('Beginn: ${_fmtDate(v['vertragsbeginn'].toString())}',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
          onPressed: () async {
            final id = int.tryParse(v['id']?.toString() ?? '');
            if (id != null) {
              await widget.apiService.deleteVertrag(id);
              await widget.onChanged();
            }
          },
        ),
        onTap: () => _openDetail(v),
      ),
    );
  }

  String _fmtDate(String iso) {
    final p = iso.split('-');
    if (p.length == 3) return '${p[2]}.${p[1]}.${p[0]}';
    return iso;
  }

  Future<void> _addVertragDialog({Map<String, dynamic>? existing, String? defaultSparte}) async {
    final id = int.tryParse(existing?['id']?.toString() ?? '');
    int? selVersId = int.tryParse(existing?['versicherung_id']?.toString() ?? '');
    String sparte = existing?['tarif']?.toString() ?? defaultSparte ?? 'haftpflicht';

    // When opened from a Sparte-Vertrag-Pane, the sparte is already fixed by
    // context — hide the Sparte dropdown and pre-select the sole Zuständige
    // if there's exactly one. Multiple → user picks via chips. None → keep
    // the search button as fallback.
    final sparteLocked = defaultSparte != null;
    final zustaendige = _zustaendigeFuerSparte(sparte);
    if (sparteLocked && selVersId == null && zustaendige.length == 1) {
      selVersId = int.tryParse(zustaendige.first['vers']['id']?.toString() ?? '');
    }

    final nrC = TextEditingController(text: existing?['vertragsnummer']?.toString() ?? '');
    final beginnC = TextEditingController(text: existing?['vertragsbeginn']?.toString() ?? '');
    final kostenC = TextEditingController(text: existing?['monatliche_kosten']?.toString() ?? '');
    bool submitting = false;
    if (!mounted) return;

    final ok = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
      Map<String, dynamic>? sel;
      if (selVersId != null) {
        try { sel = _versicherungen.firstWhere((v) => v['id'].toString() == selVersId.toString()); } catch (_) {}
      }
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text(id != null ? 'Vertrag bearbeiten' : 'Neuer Vertrag',
          style: TextStyle(color: Colors.green.shade800)),
        content: SizedBox(width: 500, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (sparteLocked) ...[
            Row(children: [
              Icon(_versicherungSpartenIcons[sparte] ?? Icons.category, size: 16, color: Colors.green.shade700),
              const SizedBox(width: 6),
              Text('Sparte: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
              Text(_versicherungSparten[sparte] ?? sparte,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green.shade900)),
            ]),
            const SizedBox(height: 10),
          ],
          // Versicherung: quick-pick chips from Zuständige (if any) + fallback search
          if (zustaendige.isNotEmpty && sel == null) ...[
            Text('Zuständige Versicherung wählen:', style: TextStyle(fontSize: 11, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final z in zustaendige)
                ChoiceChip(
                  label: Text(z['vers']['name']?.toString() ?? '?', style: const TextStyle(fontSize: 12)),
                  selected: false,
                  onSelected: (_) => setD(() => selVersId = int.tryParse(z['vers']['id']?.toString() ?? '')),
                  avatar: Icon(Icons.shield, size: 14, color: Colors.green.shade700),
                ),
              ActionChip(
                label: const Text('Andere...', style: TextStyle(fontSize: 12)),
                avatar: const Icon(Icons.search, size: 14),
                onPressed: () async {
                  final picked = await _showVersicherungSearch(ctx2, sparteKey: sparte);
                  if (picked != null) {
                    setD(() => selVersId = int.tryParse(picked['id']?.toString() ?? ''));
                  }
                },
              ),
            ]),
            const SizedBox(height: 10),
          ] else Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade200)),
            child: Row(children: [
              Icon(Icons.shield, size: 18, color: Colors.green.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text(sel?['name']?.toString() ?? 'Versicherung wählen',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: sel != null ? Colors.green.shade900 : Colors.grey.shade600))),
              OutlinedButton.icon(
                icon: const Icon(Icons.search, size: 14),
                label: Text(sel == null ? 'Suchen' : 'Ändern', style: const TextStyle(fontSize: 11)),
                onPressed: () async {
                  final picked = await _showVersicherungSearch(ctx2, sparteKey: sparte);
                  if (picked != null) {
                    setD(() => selVersId = int.tryParse(picked['id']?.toString() ?? ''));
                  }
                },
              ),
            ]),
          ),
          const SizedBox(height: 10),
          if (!sparteLocked) ...[
            DropdownButtonFormField<String>(
              initialValue: sparte,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Sparte',
                prefixIcon: const Icon(Icons.category, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: _versicherungSparten.entries.map((e) => DropdownMenuItem(
                value: e.key,
                child: Text(e.value, style: const TextStyle(fontSize: 13)),
              )).toList(),
              onChanged: (v) => setD(() => sparte = v ?? 'sonstige'),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: nrC,
            decoration: InputDecoration(
              labelText: 'Vertragsnummer *',
              prefixIcon: const Icon(Icons.tag, size: 18),
              hintText: 'z.B. HP-2026-12345',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: beginnC,
            readOnly: true,
            decoration: InputDecoration(
              labelText: 'Vertragsbeginn (gültig ab) *',
              prefixIcon: const Icon(Icons.calendar_today, size: 18),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onTap: () async {
              final p = await showDatePicker(
                context: ctx2,
                initialDate: DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(DateTime.now().year + 5),
                locale: const Locale('de'),
              );
              if (p != null) {
                beginnC.text = '${p.year}-${p.month.toString().padLeft(2, '0')}-${p.day.toString().padLeft(2, '0')}';
                setD(() {});
              }
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: kostenC,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: 'Beitrag / Monat (€)',
              prefixIcon: const Icon(Icons.euro, size: 18),
              hintText: 'optional',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]))),
        actions: [
          TextButton(onPressed: submitting ? null : () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            onPressed: submitting ? null : () async {
              // Explicit validation with visible feedback — silent return
              // was confusing the Vorstand ("Nichts passiert!").
              String? missing;
              if (selVersId == null) missing = 'Bitte Versicherung auswählen';
              else if (nrC.text.trim().isEmpty) missing = 'Bitte Vertragsnummer eintragen';
              else if (beginnC.text.trim().isEmpty) missing = 'Bitte Vertragsbeginn wählen';
              if (missing != null) {
                ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(
                  content: Text(missing),
                  backgroundColor: Colors.orange.shade700,
                  duration: const Duration(seconds: 2),
                ));
                return;
              }
              setD(() => submitting = true);
              try {
                final versName = _byId[selVersId!]?['name']?.toString() ?? '';
                final r = await widget.apiService.saveVertrag(widget.userId, {
                  if (id != null) 'id': id,
                  'kategorie': 'versicherung',
                  'versicherung_id': selVersId,
                  'anbieter': versName,
                  'vertragsnummer': nrC.text.trim(),
                  'tarif': sparte,
                  'vertragsbeginn': beginnC.text.trim(),
                  'monatliche_kosten': kostenC.text.trim().isEmpty ? null : double.tryParse(kostenC.text.trim().replaceAll(',', '.')),
                  'is_active': 1,
                });
                if (r['success'] == true) {
                  if (ctx.mounted) Navigator.pop(ctx, true);
                } else {
                  setD(() => submitting = false);
                  if (ctx2.mounted) {
                    ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(
                      content: Text('Fehler: ${r['message'] ?? 'Speichern fehlgeschlagen'}'),
                      backgroundColor: Colors.red.shade700,
                    ));
                  }
                }
              } catch (e) {
                setD(() => submitting = false);
                if (ctx2.mounted) {
                  ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(
                    content: Text('Netzwerkfehler: $e'),
                    backgroundColor: Colors.red.shade700,
                  ));
                }
              }
            },
            style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700),
            child: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Speichern'),
          ),
        ],
      );
    }));
    if (ok == true) await widget.onChanged();
  }

  Future<Map<String, dynamic>?> _showVersicherungSearch(BuildContext hostCtx, {String? sparteKey}) async {
    String q = '';
    // When called from a Sparte-Pane, only offer companies that actually
    // list that sparte in their coverage — otherwise the list becomes
    // unnecessary long and easy to mispick.
    final pool = sparteKey == null ? _versicherungen : _versicherungenFuerSparte(sparteKey);
    return await showDialog<Map<String, dynamic>?>(
      context: hostCtx,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setD) {
        final filtered = q.trim().isEmpty
            ? pool
            : pool.where((b) {
                final needle = q.toLowerCase();
                return (b['name']?.toString().toLowerCase() ?? '').contains(needle)
                    || (b['plz_ort']?.toString().toLowerCase() ?? '').contains(needle)
                    || (b['sparte']?.toString().toLowerCase() ?? '').contains(needle);
              }).toList();
        final title = sparteKey != null
            ? 'Versicherung auswählen — ${_versicherungSparten[sparteKey] ?? sparteKey}'
            : 'Versicherung auswählen';
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(children: [
            Icon(Icons.search, color: Colors.green.shade700),
            const SizedBox(width: 8),
            Expanded(child: Text(title, overflow: TextOverflow.ellipsis)),
          ]),
          content: SizedBox(
            width: 500, height: 500,
            child: Column(children: [
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Name, Sparte, Ort...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onChanged: (v) => setD(() => q = v),
              ),
              const SizedBox(height: 8),
              Expanded(child: filtered.isEmpty
                ? Center(child: Text('Keine Treffer', style: TextStyle(color: Colors.grey.shade500)))
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 4),
                    itemBuilder: (_, i) {
                      final b = filtered[i];
                      return InkWell(
                        onTap: () => Navigator.pop(ctx, b),
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(children: [
                            Icon(Icons.shield, size: 20, color: Colors.green.shade600),
                            const SizedBox(width: 10),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(b['name']?.toString() ?? '',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
                              if ((b['plz_ort']?.toString() ?? '').isNotEmpty)
                                Text('${b['strasse'] ?? ''}, ${b['plz_ort']}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                              if ((b['sparte']?.toString() ?? '').isNotEmpty)
                                Text('Sparten: ${b['sparte']}',
                                  style: TextStyle(fontSize: 10, color: Colors.green.shade400, fontStyle: FontStyle.italic)),
                            ])),
                          ]),
                        ),
                      );
                    },
                  ),
              ),
            ]),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen'))],
        );
      }),
    );
  }

  void _openDetail(Map<String, dynamic> v) {
    final vid = int.tryParse(v['id']?.toString() ?? '');
    if (vid == null) return;
    final versId = int.tryParse(v['versicherung_id']?.toString() ?? '');
    final versData = versId != null ? _byId[versId] : null;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        insetPadding: const EdgeInsets.all(20),
        child: SizedBox(
          width: 760, height: 640,
          child: _VersicherungDetailView(
            apiService: widget.apiService,
            userId: widget.userId,
            vertragId: vid,
            vertrag: v,
            versicherung: versData,
            onEdit: () { Navigator.pop(ctx); _addVertragDialog(existing: v); },
            onClose: () => Navigator.pop(ctx),
          ),
        ),
      ),
    ).then((_) => widget.onChanged());
  }
}

class _VersicherungDetailView extends StatelessWidget {
  final ApiService apiService;
  final int userId;
  final int vertragId;
  final Map<String, dynamic> vertrag;
  final Map<String, dynamic>? versicherung;
  final VoidCallback onEdit;
  final VoidCallback onClose;
  const _VersicherungDetailView({
    required this.apiService,
    required this.userId,
    required this.vertragId,
    required this.vertrag,
    required this.versicherung,
    required this.onEdit,
    required this.onClose,
  });

  String _fmtDate(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}.${p[1]}.${p[0]}' : iso;
  }

  @override
  Widget build(BuildContext context) {
    final sparte = _versicherungSparten[vertrag['tarif']?.toString() ?? ''] ?? '';
    final aktiv = vertrag['is_active'] == 1 || vertrag['is_active'] == true || vertrag['is_active'] == '1';
    return DefaultTabController(
      length: 4,
      child: Column(children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: aktiv ? Colors.green.shade700 : Colors.grey.shade600,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
          ),
          child: Row(children: [
            const Icon(Icons.shield, color: Colors.white, size: 22),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(versicherung?['name']?.toString() ?? vertrag['anbieter']?.toString() ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              if (sparte.isNotEmpty)
                Text(sparte, style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ])),
            IconButton(icon: const Icon(Icons.edit, color: Colors.white), onPressed: onEdit),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: onClose),
          ]),
        ),
        TabBar(
          isScrollable: true,
          labelColor: Colors.green.shade700,
          indicatorColor: Colors.green.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.description, size: 18), text: 'Versicherungsschein'),
            Tab(icon: Icon(Icons.mail_outline, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.cancel, size: 18), text: 'Kündigung'),
          ],
        ),
        Expanded(child: TabBarView(children: [
          _buildDetailsTab(sparte, aktiv),
          VertragDokTab(apiService: apiService, vertragId: vertragId, kategorie: 'versicherungsschein', label: 'Versicherungsschein'),
          VertragKorrTab(apiService: apiService, vertragId: vertragId),
          VertragDokTab(apiService: apiService, vertragId: vertragId, kategorie: 'kuendigung', label: 'Kündigung'),
        ])),
      ]),
    );
  }

  Widget _buildDetailsTab(String sparte, bool aktiv) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Vertragsdaten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
        const Divider(height: 20),
        _row(Icons.shield, 'Versicherung', versicherung?['name'] ?? vertrag['anbieter']),
        if (sparte.isNotEmpty) _row(Icons.category, 'Sparte', sparte),
        _row(Icons.tag, 'Vertragsnummer', vertrag['vertragsnummer']),
        _row(Icons.calendar_today, 'Vertragsbeginn (gültig ab)',
          vertrag['vertragsbeginn'] != null ? _fmtDate(vertrag['vertragsbeginn'].toString()) : null),
        if (vertrag['monatliche_kosten'] != null)
          _row(Icons.euro, 'Beitrag / Monat', '${double.tryParse(vertrag['monatliche_kosten'].toString())?.toStringAsFixed(2)} €'),
        _row(Icons.timer, 'Mindestlaufzeit', vertrag['mindestlaufzeit']),
        _row(Icons.exit_to_app, 'Kündigungsfrist', vertrag['kuendigungsfrist']),
        _row(Icons.event_busy, 'Gekündigt am',
          (vertrag['gekuendigt_am']?.toString() ?? '').isNotEmpty ? _fmtDate(vertrag['gekuendigt_am'].toString()) : null),
        _row(Icons.event, 'Vertragsende',
          (vertrag['vertragsende']?.toString() ?? '').isNotEmpty ? _fmtDate(vertrag['vertragsende'].toString()) : null),
        if (versicherung != null) ...[
          const SizedBox(height: 12),
          Text('Kontakt Versicherung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
          const Divider(height: 16),
          if ((versicherung!['strasse']?.toString() ?? '').isNotEmpty)
            _row(Icons.place, 'Adresse', '${versicherung!['strasse']}, ${versicherung!['plz_ort']}'),
          if ((versicherung!['telefon']?.toString() ?? '').isNotEmpty)
            _row(Icons.phone, 'Telefon', versicherung!['telefon']),
          if ((versicherung!['fax']?.toString() ?? '').isNotEmpty)
            _row(Icons.print, 'Fax', versicherung!['fax']),
          if ((versicherung!['email']?.toString() ?? '').isNotEmpty)
            _row(Icons.email, 'E-Mail', versicherung!['email']),
          if ((versicherung!['website']?.toString() ?? '').isNotEmpty)
            _row(Icons.language, 'Website', versicherung!['website']),
        ],
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: aktiv ? Colors.green.shade50 : Colors.red.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: aktiv ? Colors.green.shade200 : Colors.red.shade200),
          ),
          child: Row(children: [
            Icon(aktiv ? Icons.check_circle : Icons.cancel, size: 16,
              color: aktiv ? Colors.green.shade700 : Colors.red.shade700),
            const SizedBox(width: 6),
            Text(aktiv ? 'Vertrag aktiv' : 'Vertrag beendet',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                color: aktiv ? Colors.green.shade800 : Colors.red.shade800)),
          ]),
        ),
      ]),
    );
  }

  Widget _row(IconData icon, String label, dynamic value) {
    final s = value?.toString() ?? '';
    if (s.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 170, child: Text(label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w600))),
        Expanded(child: Text(s, style: const TextStyle(fontSize: 13))),
      ]),
    );
  }
}
