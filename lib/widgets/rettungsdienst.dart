import 'package:flutter/material.dart';
import '../services/api_service.dart';
import 'korrespondenz_attachments_widget.dart';

class RettungsdienstContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const RettungsdienstContent({super.key, required this.apiService, required this.userId});
  @override
  State<RettungsdienstContent> createState() => _RettungsdienstContentState();
}

class _RettungsdienstContentState extends State<RettungsdienstContent> {
  List<Map<String, dynamic>> _vorfaelle = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getRettungsdienstData(widget.userId);
      if (res['success'] == true) {
        _vorfaelle = (res['vorfaelle'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (e) { debugPrint('[Rettungsdienst] load: $e'); }
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    // Träger varies per Einsatz (ILS dispatches whoever's available), so no "Zuständiger" tab —
    // Einsätze is the only meaningful structure. Each Einsatz records its own Träger.
    return _EinsatzTab(
      vorfaelle: _vorfaelle,
      apiService: widget.apiService,
      userId: widget.userId,
      instanceIdx: 0,
      onReload: _load,
    );
  }
}

// ==================== EINSÄTZE ====================

class _EinsatzTab extends StatefulWidget {
  final List<Map<String, dynamic>> vorfaelle;
  final ApiService apiService;
  final int userId;
  final int instanceIdx;
  final Future<void> Function() onReload;
  const _EinsatzTab({required this.vorfaelle, required this.apiService, required this.userId, this.instanceIdx = 0, required this.onReload});
  @override
  State<_EinsatzTab> createState() => _EinsatzTabState();
}

class _EinsatzTabState extends State<_EinsatzTab> {
  static const typLabels = {
    'notarzteinsatz': 'Notarzteinsatz',
    'rettungswagen': 'Rettungswagen (RTW)',
    'krankentransport': 'Krankentransport (KTW)',
    'behandlung_vor_ort': 'Behandlung vor Ort (kein Transport)',
    'fehlfahrt': 'Fehlfahrt / Einsatz abgebrochen',
    'sonstiges': 'Sonstiges',
  };

  static const statusLabels = {
    'offen': ('Offen', Colors.orange),
    'abgeschlossen': ('Abgeschlossen', Colors.green),
    'kostenstreit': ('Kostenstreit', Colors.red),
    'kk_uebernommen': ('KK übernommen', Colors.teal),
    'kk_abgelehnt': ('KK abgelehnt', Colors.deepOrange),
  };

  static const alarmiertDurchOptions = {
    'mitglied': 'Mitglied selbst',
    'familie': 'Familie / Angehörige',
    'passant': 'Passant',
    'polizei': 'Polizei',
    'hausarzt': 'Hausarzt',
    'pflegedienst': 'Pflegedienst',
    'arbeitgeber': 'Arbeitgeber / Kollegen',
    'sonstige': 'Sonstige',
  };

  static const transportOptions = {
    'ja': 'Ja, transportiert',
    'nein': 'Nein, vor Ort behandelt',
    'unklar': 'Unklar / nicht dokumentiert',
    'verweigert': 'Transport verweigert',
  };

  static const polizeiVorOrtOptions = {
    'nein': 'Nein, nur Rettungsdienst',
    'ja_ohne_anzeige': 'Ja, ohne Strafanzeige',
    'ja_anzeige_folgt': 'Ja, Strafanzeige folgt',
    'ja_anzeige_existiert': 'Ja, Strafanzeige existiert',
  };

  void _showEinsatzDialog({Map<String, dynamic>? existing}) {
    final isEdit = existing != null;
    String typ = existing?['typ']?.toString() ?? 'notarzteinsatz';
    String status = existing?['status']?.toString() ?? 'offen';
    String alarmiert = existing?['alarmiert_durch']?.toString() ?? 'mitglied';
    String transport = existing?['transport']?.toString() ?? 'ja';
    String polizeiVorOrt = existing?['polizei_vor_ort']?.toString().isNotEmpty == true ? existing!['polizei_vor_ort'].toString() : 'nein';
    int? polizeiVorfallId = existing?['polizei_vorfall_id'] != null ? int.tryParse(existing!['polizei_vorfall_id'].toString()) : null;
    bool polizeiDsAutofill = (existing?['polizei_autofill'] ?? 0) == 1;
    final titelC = TextEditingController(text: existing?['titel']?.toString() ?? '');
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: existing?['uhrzeit']?.toString() ?? '');
    final einsatznrC = TextEditingController(text: existing?['einsatznummer']?.toString() ?? '');
    final einsatzortC = TextEditingController(text: existing?['einsatzort']?.toString() ?? '');
    final diagnoseC = TextEditingController(text: existing?['diagnose_vor_ort']?.toString() ?? '');
    final massnahmenC = TextEditingController(text: existing?['massnahmen_vor_ort']?.toString() ?? '');
    final zielklinikC = TextEditingController(text: existing?['zielklinik']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    final polizeiDsC = TextEditingController(text: existing?['polizei_dienststelle']?.toString() ?? '');
    final polizeiSbC = TextEditingController(text: existing?['polizei_sachbearbeiter']?.toString() ?? '');
    List<Map<String, dynamic>> strafanzeigen = [];
    bool strafanzeigenLoaded = false;
    // Träger (per Einsatz — Rettungsdienst is dispatched on-demand by 112)
    final traegerC = TextEditingController(text: existing?['traeger']?.toString() ?? '');
    int? traegerId = existing?['traeger_id'] != null ? int.tryParse(existing!['traeger_id'].toString()) : null;
    final traegerSearchC = TextEditingController();
    List<Map<String, dynamic>> traegerResults = [];
    bool traegerSearching = false;

    Future<void> searchTraeger(String q, void Function(VoidCallback) setDlg) async {
      if (q.length < 2) return;
      setDlg(() => traegerSearching = true);
      try {
        final r = await widget.apiService.searchRettungsdienstDatenbank(q);
        if (r['success'] == true) {
          traegerResults = (r['results'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        }
      } catch (_) {}
      setDlg(() => traegerSearching = false);
    }

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: Row(children: [
        Icon(isEdit ? Icons.edit : Icons.add_circle, size: 18, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text(isEdit ? 'Einsatz bearbeiten' : 'Neuer Einsatz', style: const TextStyle(fontSize: 15)),
      ]),
      content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<String>(initialValue: typ, decoration: InputDecoration(labelText: 'Einsatz-Typ', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: typLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => typ = v ?? typ)),
        const SizedBox(height: 10),
        // ============== Träger (per Einsatz) ==============
        TextField(controller: traegerC,
          decoration: InputDecoration(
            labelText: 'Rettungsdienst-Träger',
            hintText: 'DRK / Malteser / Johanniter / ASB / Feuerwehr ...',
            isDense: true,
            prefixIcon: const Icon(Icons.local_taxi, size: 18),
            suffixIcon: traegerId != null
              ? Tooltip(message: 'Aus Datenbank verknüpft', child: Icon(Icons.verified, size: 16, color: Colors.teal.shade600))
              : null,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          onChanged: (v) => setDlg(() {
            // Freier Text — Datenbank-Verknüpfung aufheben
            traegerId = null;
          }),
        ),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(child: TextField(controller: traegerSearchC,
            decoration: InputDecoration(
              hintText: 'In Datenbank suchen (DRK Ulm, Malteser ...)',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onSubmitted: (q) => searchTraeger(q, setDlg),
          )),
          const SizedBox(width: 6),
          IconButton(
            icon: traegerSearching ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.search, size: 18),
            onPressed: () => searchTraeger(traegerSearchC.text, setDlg),
            tooltip: 'Suchen',
          ),
        ]),
        if (traegerResults.isNotEmpty)
          Container(margin: const EdgeInsets.only(top: 4), constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(8)),
            child: ListView.builder(shrinkWrap: true, itemCount: traegerResults.length, itemBuilder: (lctx, i) {
              final t = traegerResults[i];
              return ListTile(dense: true,
                title: Text(t['name'] ?? '', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: Text('${t['traeger'] ?? ''} · ${t['ort'] ?? ''}', style: const TextStyle(fontSize: 10)),
                trailing: const Icon(Icons.check_circle_outline, size: 16),
                onTap: () => setDlg(() {
                  traegerC.text = t['name']?.toString() ?? '';
                  traegerId = t['id'] is int ? t['id'] as int : int.tryParse(t['id'].toString());
                  traegerResults = [];
                  traegerSearchC.clear();
                }),
              );
            }),
          ),
        const SizedBox(height: 10),
        TextField(controller: titelC, decoration: InputDecoration(labelText: 'Titel / Anlass', hintText: 'z.B. Sturz, Brustschmerz, Atemnot...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: status, decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: statusLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.$1, style: TextStyle(fontSize: 12, color: e.value.$2)))).toList(),
          onChanged: (v) => setDlg(() => status = v ?? status)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: TextField(controller: datumC, readOnly: true,
            decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async {
              final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
              if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
            })),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: uhrzeitC,
            decoration: InputDecoration(labelText: 'Uhrzeit', hintText: '14:35', isDense: true, prefixIcon: const Icon(Icons.access_time, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
        ]),
        const SizedBox(height: 10),
        TextField(controller: einsatznrC, decoration: InputDecoration(labelText: 'Einsatznummer (vom Protokoll)', isDense: true, prefixIcon: const Icon(Icons.confirmation_number, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: alarmiert,
          decoration: InputDecoration(labelText: 'Alarmiert durch', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: alarmiertDurchOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => alarmiert = v ?? alarmiert)),
        const SizedBox(height: 10),
        TextField(controller: einsatzortC, decoration: InputDecoration(labelText: 'Einsatzort (Adresse)', hintText: 'z.B. Wohnadresse, Arbeitsplatz...', isDense: true, prefixIcon: const Icon(Icons.location_on, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: diagnoseC, maxLines: 2,
          decoration: InputDecoration(labelText: 'Diagnose vor Ort (laut Sanitäter)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: massnahmenC, maxLines: 2,
          decoration: InputDecoration(labelText: 'Maßnahmen vor Ort', hintText: 'EKG, Sauerstoff, Infusion, Medikation...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: transport,
          decoration: InputDecoration(labelText: 'Transport', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: transportOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) => setDlg(() => transport = v ?? transport)),
        const SizedBox(height: 10),
        TextField(controller: zielklinikC,
          decoration: InputDecoration(labelText: 'Zielklinik (leer = unbekannt)', isDense: true, prefixIcon: const Icon(Icons.local_hospital, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        // ============== Polizei vor Ort ==============
        const SizedBox(height: 18),
        const Divider(),
        Row(children: [
          Icon(Icons.local_police, color: Colors.blue.shade700, size: 18),
          const SizedBox(width: 6),
          Text('Polizei vor Ort', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.blue.shade800)),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(initialValue: polizeiVorOrt,
          decoration: InputDecoration(labelText: 'Polizei vor Ort?', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: polizeiVorOrtOptions.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)))).toList(),
          onChanged: (v) async {
            if (v == null) return;
            setDlg(() => polizeiVorOrt = v);
            // Auto-fill on switch to "ja_*" if Dienststelle field is empty
            if (v != 'nein' && polizeiDsC.text.trim().isEmpty) {
              try {
                final r = await widget.apiService.getZustaendigePolizei(widget.userId);
                final ds = r['dienststelle'];
                if (ds is Map && (ds['name']?.toString().isNotEmpty ?? false)) {
                  setDlg(() {
                    polizeiDsC.text = ds['name'].toString();
                    polizeiDsAutofill = true;
                  });
                }
              } catch (_) {}
              // Load Strafanzeigen for picker (when state is "anzeige_existiert")
              if (!strafanzeigenLoaded) {
                try {
                  final r = await widget.apiService.listStrafanzeigenForRettungsdienst(widget.userId);
                  final list = (r['strafanzeigen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
                  setDlg(() { strafanzeigen = list; strafanzeigenLoaded = true; });
                } catch (_) {}
              }
            }
            if (v != 'ja_anzeige_existiert') {
              setDlg(() => polizeiVorfallId = null);
            }
          }),
        if (polizeiVorOrt != 'nein') ...[
          const SizedBox(height: 10),
          TextField(controller: polizeiDsC,
            decoration: InputDecoration(
              labelText: 'Polizei-Dienststelle',
              isDense: true,
              prefixIcon: const Icon(Icons.local_police, size: 18),
              suffixIcon: polizeiDsAutofill ? Tooltip(message: 'Übernommen aus Zuständige Polizeidienststelle', child: Icon(Icons.link, size: 16, color: Colors.teal.shade600)) : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onChanged: (_) => setDlg(() => polizeiDsAutofill = false),
          ),
          const SizedBox(height: 10),
          TextField(controller: polizeiSbC,
            decoration: InputDecoration(
              labelText: 'Sachbearbeiter',
              isDense: true,
              prefixIcon: const Icon(Icons.person, size: 18),
              suffixIcon: polizeiVorOrt == 'ja_anzeige_existiert' && polizeiVorfallId != null
                ? Tooltip(message: 'Übernommen aus verknüpfter Strafanzeige', child: Icon(Icons.link, size: 16, color: Colors.teal.shade600))
                : null,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          if (polizeiVorOrt == 'ja_anzeige_existiert') ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<int?>(
              initialValue: polizeiVorfallId,
              isExpanded: true,
              decoration: InputDecoration(labelText: 'Verknüpfte Strafanzeige', isDense: true, prefixIcon: const Icon(Icons.report, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('— keine Verknüpfung —', style: TextStyle(fontSize: 12, color: Colors.grey))),
                ...strafanzeigen.map((sa) => DropdownMenuItem<int?>(
                  value: sa['id'] is int ? sa['id'] as int : int.tryParse(sa['id'].toString()),
                  child: Text(
                    '${sa['aktenzeichen']?.toString().isNotEmpty == true ? sa['aktenzeichen'] : '(ohne Az.)'} · ${sa['datum'] ?? ''} · ${sa['delikt'] ?? sa['typ'] ?? ''}',
                    style: const TextStyle(fontSize: 11),
                    overflow: TextOverflow.ellipsis,
                  ),
                )),
              ],
              onChanged: (v) {
                setDlg(() => polizeiVorfallId = v);
                // Auto-fill Sachbearbeiter from picked Strafanzeige
                if (v != null) {
                  final picked = strafanzeigen.firstWhere((sa) => (sa['id'] is int ? sa['id'] as int : int.tryParse(sa['id'].toString())) == v, orElse: () => {});
                  final sb = picked['sachbearbeiter_name']?.toString() ?? '';
                  if (sb.isNotEmpty) setDlg(() => polizeiSbC.text = sb);
                }
              },
            ),
            if (strafanzeigen.isEmpty && strafanzeigenLoaded)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(
                'Keine Strafanzeigen für dieses Mitglied erfasst. Erst unter Behörde → Polizei → Vorfälle anlegen.',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade800, fontStyle: FontStyle.italic),
              )),
          ],
        ],
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          final payload = <String, dynamic>{
            'traeger': traegerC.text,
            'traeger_id': traegerId,
            'typ': typ,
            'titel': titelC.text,
            'status': status,
            'datum': datumC.text,
            'uhrzeit': uhrzeitC.text,
            'einsatznummer': einsatznrC.text,
            'alarmiert_durch': alarmiert,
            'einsatzort': einsatzortC.text,
            'diagnose_vor_ort': diagnoseC.text,
            'massnahmen_vor_ort': massnahmenC.text,
            'transport': transport,
            'zielklinik': zielklinikC.text,
            'notiz': notizC.text,
            'polizei_vor_ort': polizeiVorOrt,
            'polizei_dienststelle': polizeiDsC.text,
            'polizei_sachbearbeiter': polizeiSbC.text,
            'polizei_vorfall_id': polizeiVorOrt == 'ja_anzeige_existiert' ? polizeiVorfallId : null,
            'polizei_autofill': polizeiDsAutofill ? 1 : 0,
          };
          if (isEdit) payload['id'] = existing['id'];
          await widget.apiService.rettungsdienstAction(widget.userId, {
            'action': 'save_vorfall',
            'instance_idx': widget.instanceIdx,
            'vorfall': payload,
          });
          await widget.onReload();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
          child: Text(isEdit ? 'Speichern' : 'Hinzufügen')),
      ],
    )));
  }

  void _openDetail(Map<String, dynamic> v) {
    showDialog(context: context, barrierDismissible: false, builder: (ctx) => Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: SizedBox(width: 760, height: 580, child: _EinsatzDetailModal(vorfall: v, apiService: widget.apiService, userId: widget.userId, onReload: widget.onReload, onEdit: () { Navigator.pop(ctx); _showEinsatzDialog(existing: v); })),
    ));
  }

  Future<void> _delete(Map<String, dynamic> v) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Einsatz löschen?', style: TextStyle(fontSize: 15)),
      content: const Text('Alle Korrespondenz und Rechnungen zu diesem Einsatz werden ebenfalls gelöscht.', style: TextStyle(fontSize: 12)),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen'))],
    ));
    if (ok != true) return;
    await widget.apiService.rettungsdienstAction(widget.userId, {'action': 'delete_vorfall', 'id': v['id']});
    await widget.onReload();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(12), child: Row(children: [
        Icon(Icons.emergency, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text('Einsätze (${widget.vorfaelle.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: () => _showEinsatzDialog(), icon: const Icon(Icons.add, size: 16), label: const Text('Neuer Einsatz', style: TextStyle(fontSize: 12)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
      ])),
      Expanded(child: widget.vorfaelle.isEmpty
        ? Center(child: Text('Keine Einsätze', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 12), itemCount: widget.vorfaelle.length, itemBuilder: (ctx, i) {
            final v = widget.vorfaelle[i];
            final status = v['status']?.toString() ?? 'offen';
            final st = statusLabels[status] ?? ('Offen', Colors.orange);
            final transport = v['transport']?.toString() ?? '';
            return Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
              onTap: () => _openDetail(v),
              leading: CircleAvatar(backgroundColor: st.$2.shade100, child: Icon(Icons.emergency, color: st.$2.shade700, size: 20)),
              title: Text(v['titel']?.toString().isNotEmpty == true ? v['titel'].toString() : (typLabels[v['typ']] ?? v['typ']?.toString() ?? ''), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${typLabels[v['typ']] ?? ''} · ${v['datum'] ?? ''} ${v['uhrzeit'] ?? ''}', style: const TextStyle(fontSize: 11)),
                if ((v['traeger']?.toString() ?? '').isNotEmpty) Text('Träger: ${v['traeger']}', style: TextStyle(fontSize: 10, color: Colors.teal.shade700, fontWeight: FontWeight.w600)),
                if ((v['einsatznummer']?.toString() ?? '').isNotEmpty) Text('Nr. ${v['einsatznummer']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                if (transport == 'ja' && (v['zielklinik']?.toString() ?? '').isNotEmpty)
                  Text('→ ${v['zielklinik']}', style: TextStyle(fontSize: 10, color: Colors.teal.shade700, fontStyle: FontStyle.italic)),
                if (transport == 'ja' && (v['zielklinik']?.toString() ?? '').isEmpty)
                  Text('→ Klinik unbekannt', style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontStyle: FontStyle.italic)),
                if ((v['polizei_vor_ort']?.toString() ?? 'nein') != 'nein' && (v['polizei_vor_ort']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 2), child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.local_police, size: 10, color: Colors.blue.shade700),
                    const SizedBox(width: 3),
                    Flexible(child: Text(
                      (v['linked_strafanzeige_aktenzeichen']?.toString() ?? '').isNotEmpty
                          ? 'Polizei + Strafanzeige Az. ${v['linked_strafanzeige_aktenzeichen']}'
                          : 'Polizei vor Ort',
                      style: TextStyle(fontSize: 10, color: Colors.blue.shade800, fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    )),
                  ])),
              ]),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: st.$2.shade100, borderRadius: BorderRadius.circular(12)),
                  child: Text(st.$1, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: st.$2.shade800))),
                const SizedBox(width: 4),
                IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade300), onPressed: () => _delete(v)),
              ]),
            ));
          })),
    ]);
  }
}

// ==================== EINSATZ DETAIL MODAL ====================

class _EinsatzDetailModal extends StatefulWidget {
  final Map<String, dynamic> vorfall;
  final ApiService apiService;
  final int userId;
  final Future<void> Function() onReload;
  final VoidCallback onEdit;
  const _EinsatzDetailModal({required this.vorfall, required this.apiService, required this.userId, required this.onReload, required this.onEdit});
  @override
  State<_EinsatzDetailModal> createState() => _EinsatzDetailModalState();
}

class _EinsatzDetailModalState extends State<_EinsatzDetailModal> with TickerProviderStateMixin {
  late TabController _tabC;
  List<Map<String, dynamic>> _korr = [];
  List<Map<String, dynamic>> _rechnungen = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabC = TabController(length: 5, vsync: this);
    _loadDetail();
  }

  @override
  void dispose() { _tabC.dispose(); super.dispose(); }

  Future<void> _loadDetail() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getRettungsdienstVorfallDetail(widget.userId, widget.vorfall['id'] as int);
      if (res['success'] == true) {
        _korr = (res['korrespondenz'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
        _rechnungen = (res['rechnungen'] as List?)?.map((e) => Map<String, dynamic>.from(e as Map)).toList() ?? [];
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    final titel = widget.vorfall['titel']?.toString().isNotEmpty == true
        ? widget.vorfall['titel'].toString()
        : (_EinsatzTabState.typLabels[widget.vorfall['typ']] ?? '');
    return Column(children: [
      Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
        child: Row(children: [
          Icon(Icons.emergency, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(titel, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.teal.shade800), overflow: TextOverflow.ellipsis)),
          IconButton(icon: Icon(Icons.edit, color: Colors.teal.shade700, size: 20), tooltip: 'Einsatz bearbeiten', onPressed: widget.onEdit),
          IconButton(icon: const Icon(Icons.close), onPressed: () { Navigator.pop(context); widget.onReload(); }),
        ])),
      TabBar(controller: _tabC, labelColor: Colors.teal.shade800, unselectedLabelColor: Colors.grey, indicatorColor: Colors.teal.shade700, isScrollable: true, tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Einsatzprotokoll'),
        Tab(text: 'Unterlagen'),
        Tab(text: 'Korrespondenz'),
        Tab(text: 'Rechnungen'),
      ]),
      Expanded(child: _isLoading ? const Center(child: CircularProgressIndicator()) : TabBarView(controller: _tabC, children: [
        _buildDetailsTab(),
        _buildProtokollTab(),
        _buildUnterlagenTab(),
        _buildKorrTab(),
        _buildRechnungenTab(),
      ])),
    ]);
  }

  Widget _buildDetailsTab() {
    final v = widget.vorfall;
    final status = v['status']?.toString() ?? 'offen';
    final st = _EinsatzTabState.statusLabels[status] ?? ('Offen', Colors.orange);
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: st.$2.shade100, borderRadius: BorderRadius.circular(12)),
          child: Text(st.$1, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: st.$2.shade800))),
        const Spacer(),
        Text('${v['datum'] ?? ''} ${v['uhrzeit'] ?? ''}', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
      ]),
      const SizedBox(height: 14),
      _section('Einsatz'),
      _infoRow('Typ', _EinsatzTabState.typLabels[v['typ']] ?? v['typ']?.toString() ?? ''),
      _infoRow('Träger', v['traeger']?.toString() ?? ''),
      _infoRow('Titel / Anlass', v['titel']?.toString() ?? ''),
      _infoRow('Einsatznummer', v['einsatznummer']?.toString() ?? ''),
      _infoRow('Alarmiert durch', _EinsatzTabState.alarmiertDurchOptions[v['alarmiert_durch']] ?? v['alarmiert_durch']?.toString() ?? ''),
      _infoRow('Einsatzort', v['einsatzort']?.toString() ?? ''),
      const SizedBox(height: 8),
      _section('Vor Ort'),
      _infoRow('Diagnose', v['diagnose_vor_ort']?.toString() ?? ''),
      _infoRow('Maßnahmen', v['massnahmen_vor_ort']?.toString() ?? ''),
      const SizedBox(height: 8),
      _section('Transport'),
      _infoRow('Transport', _EinsatzTabState.transportOptions[v['transport']] ?? v['transport']?.toString() ?? ''),
      _infoRow('Zielklinik', (v['zielklinik']?.toString() ?? '').isEmpty ? '— (unbekannt)' : v['zielklinik'].toString()),
      // ============== Polizei vor Ort badge ==============
      if ((v['polizei_vor_ort']?.toString() ?? 'nein') != 'nein' && (v['polizei_vor_ort']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        _section('Polizei vor Ort'),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Icon(Icons.local_police, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 6),
              Expanded(child: Text(
                _EinsatzTabState.polizeiVorOrtOptions[v['polizei_vor_ort']] ?? v['polizei_vor_ort'].toString(),
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.blue.shade800),
              )),
              if ((v['polizei_autofill'] ?? 0) == 1)
                Tooltip(message: 'Dienststelle aus Zuständige Polizeidienststelle übernommen', child: Icon(Icons.link, size: 14, color: Colors.teal.shade600)),
            ]),
            if ((v['polizei_dienststelle']?.toString() ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 4), child: Text('Dienststelle: ${v['polizei_dienststelle']}', style: const TextStyle(fontSize: 12))),
            if ((v['polizei_sachbearbeiter']?.toString() ?? '').isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 2), child: Text('Sachbearbeiter: ${v['polizei_sachbearbeiter']}', style: const TextStyle(fontSize: 12))),
            // Linked Strafanzeige
            if ((v['linked_strafanzeige_aktenzeichen']?.toString() ?? '').isNotEmpty) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade300)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.report, size: 14, color: Colors.red.shade700),
                  const SizedBox(width: 4),
                  Flexible(child: Text(
                    'Strafanzeige Az. ${v['linked_strafanzeige_aktenzeichen']}${(v['linked_strafanzeige_datum']?.toString() ?? '').isNotEmpty ? ' (${v['linked_strafanzeige_datum']})' : ''}',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade900),
                    overflow: TextOverflow.ellipsis,
                  )),
                  const SizedBox(width: 6),
                  Icon(Icons.open_in_new, size: 12, color: Colors.blue.shade700),
                ]),
              ),
              Padding(padding: const EdgeInsets.only(top: 2), child: Text(
                'Verknüpfung unter Behörde → Polizei → Vorfälle einsehbar',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
              )),
            ],
          ]),
        ),
      ],
      if ((v['notiz']?.toString() ?? '').isNotEmpty) ...[
        const SizedBox(height: 10),
        _section('Notiz'),
        Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Text(v['notiz'].toString(), style: const TextStyle(fontSize: 13))),
      ],
    ]));
  }

  Widget _section(String label) => Padding(padding: const EdgeInsets.only(top: 4, bottom: 6), child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700, letterSpacing: 0.5)));

  Widget _infoRow(String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600))),
      Expanded(child: Text(value, style: const TextStyle(fontSize: 13))),
    ]));
  }

  Widget _buildProtokollTab() {
    final vId = int.tryParse(widget.vorfall['id'].toString()) ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.amber.shade200)),
        child: Row(children: [
          Icon(Icons.info_outline, color: Colors.amber.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Einsatzprotokoll (Notfall-Einsatzprotokoll des Rettungsdienstes) — PDF/JPG/JPEG hochladen. Mehrere Seiten möglich.',
            style: TextStyle(fontSize: 12, color: Colors.amber.shade900))),
        ])),
      const SizedBox(height: 12),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'rettungsdienst_einsatz', korrespondenzId: vId),
    ]));
  }

  Widget _buildUnterlagenTab() {
    final vId = int.tryParse(widget.vorfall['id'].toString()) ?? 0;
    return SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
        child: Row(children: [
          Icon(Icons.folder_open, color: Colors.indigo.shade700, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(
            'Sonstige Unterlagen — Arztberichte, Entlassungsbriefe, Befunde, Fotos, weitere PDFs/JPG/JPEG zum Einsatz. Mehrere Dateien möglich.',
            style: TextStyle(fontSize: 12, color: Colors.indigo.shade900))),
        ])),
      const SizedBox(height: 12),
      KorrAttachmentsWidget(apiService: widget.apiService, modul: 'rettungsdienst_unterlagen', korrespondenzId: vId),
    ]));
  }

  Widget _buildKorrTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Korrespondenz (${_korr.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addKorr, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _korr.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _korr.length, itemBuilder: (ctx, i) {
            final k = _korr[i];
            final isEin = k['richtung'] == 'eingang';
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: InkWell(
              onTap: () => _openKorrDetail(k),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(dense: true,
                  leading: Icon(isEin ? Icons.call_received : Icons.call_made, color: isEin ? Colors.blue : Colors.orange, size: 20),
                  title: Text(k['betreff']?.toString() ?? '(kein Betreff)', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  subtitle: Text('${k['datum'] ?? ''} · ${k['methode'] ?? ''}', style: const TextStyle(fontSize: 10)),
                  trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () async {
                    await widget.apiService.rettungsdienstAction(widget.userId, {'action': 'delete_korr', 'id': k['id']});
                    await _loadDetail();
                  }),
                ),
              ]),
            ));
          })),
    ]);
  }

  void _openKorrDetail(Map<String, dynamic> k) {
    final kId = int.tryParse(k['id'].toString()) ?? 0;
    final isEin = k['richtung'] == 'eingang';
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: Row(children: [
        Icon(isEin ? Icons.call_received : Icons.call_made, size: 20, color: isEin ? Colors.blue : Colors.orange),
        const SizedBox(width: 8),
        Expanded(child: Text(k['betreff']?.toString() ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
      ]),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: isEin ? Colors.blue.shade100 : Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
            child: Text(isEin ? 'Eingang' : 'Ausgang', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEin ? Colors.blue.shade800 : Colors.orange.shade800))),
          const SizedBox(width: 8),
          if ((k['methode']?.toString() ?? '').isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(12)),
            child: Text(k['methode'].toString(), style: TextStyle(fontSize: 11, color: Colors.purple.shade700))),
          const Spacer(),
          if ((k['datum']?.toString() ?? '').isNotEmpty) Text(k['datum'].toString(), style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
        if ((k['notiz']?.toString() ?? '').isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Notiz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Text(k['notiz'].toString(), style: const TextStyle(fontSize: 13))),
        ],
        const SizedBox(height: 16),
        KorrAttachmentsWidget(apiService: widget.apiService, modul: 'rettungsdienst_korr', korrespondenzId: kId),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Schließen'))],
    ));
  }

  void _addKorr() {
    String richtung = 'eingang';
    String methode = 'Brief';
    final datumC = TextEditingController();
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: const Text('Neue Korrespondenz', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 400, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          ChoiceChip(label: const Text('Eingang'), selected: richtung == 'eingang', onSelected: (_) => setDlg(() => richtung = 'eingang')),
          const SizedBox(width: 8),
          ChoiceChip(label: const Text('Ausgang'), selected: richtung == 'ausgang', onSelected: (_) => setDlg(() => richtung = 'ausgang')),
        ]),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(initialValue: methode, decoration: InputDecoration(labelText: 'Methode', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          items: const [DropdownMenuItem(value: 'Brief', child: Text('Brief')), DropdownMenuItem(value: 'E-Mail', child: Text('E-Mail')), DropdownMenuItem(value: 'Telefon', child: Text('Telefon')), DropdownMenuItem(value: 'Fax', child: Text('Fax')), DropdownMenuItem(value: 'Persönlich', child: Text('Persönlich'))],
          onChanged: (v) => setDlg(() => methode = v ?? methode)),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        TextField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 3, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.rettungsdienstAction(widget.userId, {'action': 'save_korr', 'vorfall_id': widget.vorfall['id'], 'korr': {'richtung': richtung, 'methode': methode, 'datum': datumC.text, 'betreff': betreffC.text, 'notiz': notizC.text}});
          await _loadDetail();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    )));
  }

  Widget _buildRechnungenTab() {
    return Column(children: [
      Padding(padding: const EdgeInsets.all(8), child: Row(children: [
        Text('Rechnungen (${_rechnungen.length})', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal.shade800)),
        const Spacer(),
        ElevatedButton.icon(onPressed: _addRechnung, icon: const Icon(Icons.add, size: 14), label: const Text('Neu', style: TextStyle(fontSize: 11)),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4))),
      ])),
      Expanded(child: _rechnungen.isEmpty
        ? Center(child: Text('Keine Rechnungen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _rechnungen.length, itemBuilder: (ctx, i) {
            final r = _rechnungen[i];
            final status = r['status'] ?? 'offen';
            final colorMap = {
              'bezahlt': Colors.green,
              'kk_uebernommen': Colors.teal,
              'ueberfaellig': Colors.red,
              'kk_abgelehnt': Colors.deepOrange,
              'offen': Colors.orange,
            };
            final labelMap = {
              'bezahlt': 'Bezahlt',
              'kk_uebernommen': 'KK übernommen',
              'ueberfaellig': 'Überfällig',
              'kk_abgelehnt': 'KK abgelehnt',
              'offen': 'Offen',
            };
            final statusColor = colorMap[status] ?? Colors.orange;
            final statusLabel = labelMap[status] ?? 'Offen';
            final kId = int.tryParse(r['id'].toString()) ?? 0;
            return Card(margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3), child: ExpansionTile(
              leading: Icon(Icons.receipt_long, color: statusColor, size: 20),
              title: Row(children: [
                Text(r['rechnungsnummer']?.toString().isNotEmpty == true ? 'Nr. ${r['rechnungsnummer']}' : 'Rechnung', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(width: 8),
                if (r['betrag']?.toString().isNotEmpty == true)
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6)),
                    child: Text('${r['betrag']} €', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber.shade800))),
                const SizedBox(width: 8),
                Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(6)),
                  child: Text(statusLabel, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor))),
              ]),
              subtitle: Text(r['datum'] ?? '', style: const TextStyle(fontSize: 10)),
              trailing: IconButton(icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade300), onPressed: () async {
                await widget.apiService.rettungsdienstAction(widget.userId, {'action': 'delete_rechnung', 'id': r['id']});
                await _loadDetail();
              }),
              children: [
                if (r['notiz']?.toString().isNotEmpty == true)
                  Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8), child: Align(alignment: Alignment.centerLeft, child: Text(r['notiz'], style: const TextStyle(fontSize: 12)))),
                Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: KorrAttachmentsWidget(apiService: widget.apiService, modul: 'rettungsdienst_rechnung', korrespondenzId: kId)),
              ],
            ));
          })),
    ]);
  }

  void _addRechnung() {
    final nrC = TextEditingController();
    final betragC = TextEditingController();
    final datumC = TextEditingController();
    final notizC = TextEditingController();
    String status = 'offen';
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
      title: const Text('Neue Rechnung', style: TextStyle(fontSize: 15)),
      content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: nrC, decoration: InputDecoration(labelText: 'Rechnungsnummer', isDense: true, prefixIcon: const Icon(Icons.tag, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
        const SizedBox(height: 10),
        TextField(controller: betragC, decoration: InputDecoration(labelText: 'Betrag (€)', isDense: true, prefixIcon: const Icon(Icons.euro, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))), keyboardType: TextInputType.number),
        const SizedBox(height: 10),
        TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, prefixIcon: const Icon(Icons.calendar_today, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          onTap: () async { final d = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2040), locale: const Locale('de')); if (d != null) datumC.text = '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}'; }),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          ChoiceChip(label: const Text('Offen'), selected: status == 'offen', selectedColor: Colors.orange.shade300, onSelected: (_) => setDlg(() => status = 'offen')),
          ChoiceChip(label: const Text('Bezahlt'), selected: status == 'bezahlt', selectedColor: Colors.green.shade300, onSelected: (_) => setDlg(() => status = 'bezahlt')),
          ChoiceChip(label: const Text('KK übernommen'), selected: status == 'kk_uebernommen', selectedColor: Colors.teal.shade300, onSelected: (_) => setDlg(() => status = 'kk_uebernommen')),
          ChoiceChip(label: const Text('KK abgelehnt'), selected: status == 'kk_abgelehnt', selectedColor: Colors.deepOrange.shade300, onSelected: (_) => setDlg(() => status = 'kk_abgelehnt')),
          ChoiceChip(label: const Text('Überfällig'), selected: status == 'ueberfaellig', selectedColor: Colors.red.shade300, onSelected: (_) => setDlg(() => status = 'ueberfaellig')),
        ]),
        const SizedBox(height: 10),
        TextField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
      ]))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () async {
          Navigator.pop(ctx);
          await widget.apiService.rettungsdienstAction(widget.userId, {'action': 'save_rechnung', 'vorfall_id': widget.vorfall['id'], 'rechnung': {'rechnungsnummer': nrC.text, 'betrag': betragC.text, 'datum': datumC.text, 'status': status, 'notiz': notizC.text}});
          await _loadDetail();
        }, style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white), child: const Text('Hinzufügen')),
      ],
    )));
  }
}
