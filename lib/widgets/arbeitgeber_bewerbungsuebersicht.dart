import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import 'korrespondenz_attachments_widget.dart';

/// Bewerbungsübersicht — applications tracker per (user, arbeitgeber).
/// Data is AES-256-CBC encrypted server-side in table user_bewerbungen.
class ArbeitgeberBewerbungsuebersichtContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final List<Map<String, dynamic>> dbArbeitgeberListe;

  const ArbeitgeberBewerbungsuebersichtContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.dbArbeitgeberListe,
  });

  @override
  State<ArbeitgeberBewerbungsuebersichtContent> createState() => _State();
}

class _State extends State<ArbeitgeberBewerbungsuebersichtContent> {
  List<Map<String, dynamic>> _bewerbungen = [];
  bool _loaded = false;

  static const Map<String, ({IconData icon, String label, MaterialColor color})> _wege = {
    'online': (icon: Icons.public, label: 'Online (Portal)', color: Colors.blue),
    'email': (icon: Icons.email, label: 'E-Mail', color: Colors.indigo),
    'fax': (icon: Icons.fax, label: 'Fax', color: Colors.deepPurple),
    'persoenlich': (icon: Icons.handshake, label: 'Persönlich', color: Colors.green),
    'post': (icon: Icons.local_post_office, label: 'Post', color: Colors.brown),
    'telefonisch': (icon: Icons.phone, label: 'Telefonisch', color: Colors.teal),
  };

  static const Map<String, ({String label, MaterialColor color})> _statuses = {
    'gesendet': (label: 'Gesendet', color: Colors.blue),
    'eingang_bestaetigt': (label: 'Eingang bestätigt', color: Colors.lightBlue),
    'einladung': (label: 'Einladung Gespräch', color: Colors.amber),
    'gespraech_termin': (label: 'Gesprächstermin', color: Colors.orange),
    'in_pruefung': (label: 'In Prüfung', color: Colors.purple),
    'angebot': (label: 'Angebot erhalten', color: Colors.green),
    'zugesagt': (label: 'Zugesagt', color: Colors.teal),
    'abgesagt': (label: 'Abgesagt', color: Colors.red),
    'zurueckgezogen': (label: 'Zurückgezogen', color: Colors.grey),
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await widget.apiService.listBewerbungen(widget.userId);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      if (r['success'] == true) {
        final dataField = r['data'] ?? r;
        final list = dataField['bewerbungen'] ?? [];
        _bewerbungen = List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map)));
      }
    });
    // Im Hintergrund prueft der Server, welche BA-Stellen inzwischen 404
    // liefern, und setzt ba_stelle_expired_at. Wenn sich etwas geaendert
    // hat, laden wir die Liste neu — der Benutzer muss nichts manuell tun.
    _runBaBulkCheck();
  }

  Future<void> _runBaBulkCheck() async {
    final res = await widget.apiService.bulkCheckBaStatus(widget.userId);
    if (!mounted || res['success'] != true) return;
    final changed = ((res['newly_expired'] as int? ?? 0) + (res['restored'] as int? ?? 0)) > 0;
    if (!changed) return;
    final r = await widget.apiService.listBewerbungen(widget.userId);
    if (!mounted || r['success'] != true) return;
    final dataField = r['data'] ?? r;
    final list = dataField['bewerbungen'] ?? [];
    setState(() {
      _bewerbungen = List<Map<String, dynamic>>.from(list.map((e) => Map<String, dynamic>.from(e as Map)));
    });
    if ((res['newly_expired'] as int? ?? 0) > 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${res['newly_expired']} BA-Stelle(n) nicht mehr verfuegbar — markiert in der Liste'),
        backgroundColor: Colors.orange.shade700,
      ));
    }
  }

  void _openSearch() {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> filtered = List.from(widget.dbArbeitgeberListe);
    final existingIds = _bewerbungen.map((b) => b['arbeitgeber_id'].toString()).toSet();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
        void doFilter(String q) {
          if (q.isEmpty) {
            setDlg(() => filtered = List.from(widget.dbArbeitgeberListe));
            return;
          }
          final l = q.toLowerCase();
          setDlg(() => filtered = widget.dbArbeitgeberListe.where((s) =>
              (s['firma_name']?.toString() ?? '').toLowerCase().contains(l) ||
              (s['hauptzentrale_ort']?.toString() ?? '').toLowerCase().contains(l) ||
              (s['niederlassung_ort']?.toString() ?? '').toLowerCase().contains(l) ||
              (s['branche']?.toString() ?? '').toLowerCase().contains(l)).toList());
        }
        return AlertDialog(
          title: Row(children: [
            Icon(Icons.search, color: Colors.deepPurple.shade700),
            const SizedBox(width: 8),
            const Text('Arbeitgeber für Bewerbung auswählen', style: TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(width: 550, height: 450, child: Column(children: [
            TextField(
              controller: searchC,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'Firma, Ort oder Branche suchen...',
                prefixIcon: const Icon(Icons.search),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onChanged: doFilter,
            ),
            const SizedBox(height: 12),
            Expanded(child: filtered.isEmpty
                ? Center(child: Text('Keine Arbeitgeber gefunden', style: TextStyle(color: Colors.grey.shade400)))
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final s = filtered[i];
                      final alreadyAdded = existingIds.contains(s['id'].toString());
                      return Card(
                        margin: const EdgeInsets.only(bottom: 6),
                        color: alreadyAdded ? Colors.grey.shade100 : null,
                        child: ListTile(
                          enabled: !alreadyAdded,
                          leading: CircleAvatar(backgroundColor: Colors.deepPurple.shade100, child: Icon(Icons.business, color: Colors.deepPurple.shade700, size: 20)),
                          title: Text(s['firma_name'] ?? '', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: alreadyAdded ? Colors.grey : null)),
                          subtitle: Text('${s['branche'] ?? ''} · ${s['niederlassung_ort'] ?? s['hauptzentrale_ort'] ?? ''}', style: const TextStyle(fontSize: 11)),
                          trailing: alreadyAdded
                              ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 18)
                              : Icon(Icons.add_circle_outline, color: Colors.deepPurple.shade400),
                          onTap: alreadyAdded ? null : () async {
                            Navigator.pop(ctx);
                            final aid = int.tryParse(s['id'].toString()) ?? 0;
                            await widget.apiService.saveBewerbung(widget.userId, aid, {
                              'status_journal': <Map<String, dynamic>>[],
                              'korrespondenz': <Map<String, dynamic>>[],
                              'general_notes': '',
                              'created_at': DateTime.now().toIso8601String(),
                            });
                            await _load();
                          },
                        ),
                      );
                    },
                  )),
          ])),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
        );
      }),
    );
  }

  Future<void> _deleteBewerbung(int arbeitgeberId, String firmaName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Bewerbung löschen?', style: TextStyle(fontSize: 15)),
        content: Text('Bewerbung bei "$firmaName" inkl. aller Korrespondenz wirklich löschen?', style: const TextStyle(fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await widget.apiService.deleteBewerbung(widget.userId, arbeitgeberId);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // ─── HEADER ───
      Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [Colors.deepPurple.shade50, Colors.indigo.shade50]),
        ),
        child: Row(children: [
          Icon(Icons.assignment_ind, color: Colors.deepPurple.shade700, size: 26),
          const SizedBox(width: 8),
          const Text('Bewerbungsübersicht', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(color: Colors.deepPurple.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text('${_bewerbungen.length}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade300)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock, size: 10, color: Colors.green.shade700),
              const SizedBox(width: 3),
              Text('AES-256', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
            ]),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(Icons.search, color: Colors.deepPurple.shade700, size: 26),
            tooltip: 'Arbeitgeber suchen & Bewerbung hinzufügen',
            onPressed: widget.dbArbeitgeberListe.isEmpty ? null : _openSearch,
          ),
        ]),
      ),

      // ─── LIST ───
      Expanded(
        child: _bewerbungen.isEmpty
            ? Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.assignment_outlined, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  Text('Noch keine Bewerbungen', style: TextStyle(fontSize: 14, color: Colors.grey.shade500)),
                  const SizedBox(height: 6),
                  Text('Über die Lupe oben Arbeitgeber wählen', style: TextStyle(fontSize: 11, color: Colors.grey.shade400)),
                ]),
              )
            : ListView.builder(
                padding: const EdgeInsets.all(12),
                itemCount: _bewerbungen.length,
                itemBuilder: (_, i) {
                  final b = _bewerbungen[i];
                  final firmaName = b['firma_name']?.toString() ?? '(Firma gelöscht)';
                  final ort = b['ort']?.toString() ?? '';
                  final branche = b['branche']?.toString() ?? '';
                  final statusCount = b['status_count'] is int ? b['status_count'] as int : 0;
                  final korrCount = b['korr_count'] is int ? b['korr_count'] as int : 0;
                  final latest = b['latest_status'] is Map ? Map<String, dynamic>.from(b['latest_status'] as Map) : null;
                  final aid = b['arbeitgeber_id'] is int ? b['arbeitgeber_id'] as int : int.tryParse(b['arbeitgeber_id'].toString()) ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: InkWell(
                      onTap: () => _openDetailModal(aid, firmaName),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(children: [
                          CircleAvatar(radius: 22, backgroundColor: Colors.deepPurple.shade100, child: Icon(Icons.business, color: Colors.deepPurple.shade700, size: 22)),
                          const SizedBox(width: 12),
                          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(firmaName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                            if (branche.isNotEmpty || ort.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text([branche, ort].where((e) => e.isNotEmpty).join(' · '), style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ),
                            if ((b['ba_titel']?.toString() ?? '').isNotEmpty || (b['ba_beruf']?.toString() ?? '').isNotEmpty) Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.indigo.shade200)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.search, size: 11, color: Colors.indigo.shade700),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text('BA-Stelle: ${b['ba_titel']?.toString() ?? b['ba_beruf']?.toString() ?? ''}',
                                      style: TextStyle(fontSize: 10, color: Colors.indigo.shade900), overflow: TextOverflow.ellipsis)),
                                ]),
                              ),
                            ),
                            if ((b['ba_stelle_expired_at']?.toString() ?? '').isNotEmpty) Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.orange.shade300)),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  Icon(Icons.cloud_off, size: 11, color: Colors.orange.shade800),
                                  const SizedBox(width: 4),
                                  Flexible(child: Text(
                                    'Stelle bei BA nicht mehr verfuegbar (seit ${b['ba_stelle_expired_at'].toString().split(' ').first.split('T').first})',
                                    style: TextStyle(fontSize: 10, color: Colors.orange.shade900, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis,
                                  )),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Row(children: [
                              _miniBadge(Icons.history, '$statusCount', Colors.blue, 'Status-Einträge'),
                              const SizedBox(width: 6),
                              _miniBadge(Icons.email, '$korrCount', Colors.indigo, 'Korrespondenz'),
                              if (latest != null) ...[
                                const SizedBox(width: 8),
                                _statusChip(latest['status']?.toString() ?? ''),
                              ],
                            ]),
                          ])),
                          // BA-Validitäts-Badge (nur fuer Eintraege mit ba_refnr):
                          //   ✓ gruen  – Stelle existiert noch bei der Bundesagentur
                          //   ✗ rot    – Stelle wurde inzwischen entfernt
                          if ((b['ba_refnr']?.toString() ?? '').isNotEmpty) Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Tooltip(
                              message: (b['ba_stelle_expired_at']?.toString() ?? '').isEmpty
                                  ? 'BA-Stelle noch verfuegbar'
                                  : 'BA-Stelle nicht mehr verfuegbar',
                              child: Container(
                                width: 22, height: 22,
                                decoration: BoxDecoration(
                                  color: (b['ba_stelle_expired_at']?.toString() ?? '').isEmpty
                                      ? Colors.green.shade100
                                      : Colors.red.shade100,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: (b['ba_stelle_expired_at']?.toString() ?? '').isEmpty
                                      ? Colors.green.shade400
                                      : Colors.red.shade400, width: 1.5),
                                ),
                                child: Icon(
                                  (b['ba_stelle_expired_at']?.toString() ?? '').isEmpty ? Icons.check : Icons.close,
                                  size: 14,
                                  color: (b['ba_stelle_expired_at']?.toString() ?? '').isEmpty
                                      ? Colors.green.shade800
                                      : Colors.red.shade800,
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                            tooltip: 'Bewerbung löschen',
                            onPressed: () => _deleteBewerbung(aid, firmaName),
                          ),
                          Icon(Icons.chevron_right, color: Colors.grey.shade400),
                        ]),
                      ),
                    ),
                  );
                },
              ),
      ),
    ]);
  }

  Widget _miniBadge(IconData icon, String count, MaterialColor color, String tooltip) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 11, color: color.shade700),
          const SizedBox(width: 3),
          Text(count, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color.shade800)),
        ]),
      ),
    );
  }

  Widget _statusChip(String statusKey) {
    final s = _statuses[statusKey];
    if (s == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(color: s.color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: s.color.shade300)),
      child: Text(s.label, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: s.color.shade800)),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  //   DETAIL MODAL mit 3 Tabs (Details / Status / Korrespondenz)
  // ═══════════════════════════════════════════════════════════════
  Future<void> _openDetailModal(int arbeitgeberId, String firmaName) async {
    final res = await widget.apiService.getBewerbung(widget.userId, arbeitgeberId);
    if (!mounted) return;
    if (res['success'] != true) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fehler beim Laden'), backgroundColor: Colors.red));
      return;
    }
    // PHP jsonResponse uses array_merge — fields are at ROOT level, not nested under 'data'
    final arbeitgeber = res['arbeitgeber'] is Map ? Map<String, dynamic>.from(res['arbeitgeber'] as Map) : <String, dynamic>{};
    final inner = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final baRefnr = (res['ba_refnr'] ?? '').toString();
    final baTitel = (res['ba_titel'] ?? '').toString();
    final baBeruf = (res['ba_beruf'] ?? '').toString();
    final baMarkedAt = (res['ba_marked_at'] ?? '').toString();
    final hasBa = baRefnr.isNotEmpty;

    List<Map<String, dynamic>> statusJournal = List<Map<String, dynamic>>.from(
      (inner['status_journal'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    List<Map<String, dynamic>> korrespondenz = List<Map<String, dynamic>>.from(
      (inner['korrespondenz'] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)),
    );
    String generalNotes = inner['general_notes']?.toString() ?? '';

    Future<void> persist() async {
      await widget.apiService.saveBewerbung(widget.userId, arbeitgeberId, {
        'status_journal': statusJournal,
        'korrespondenz': korrespondenz,
        'general_notes': generalNotes,
      });
    }

    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dlgCtx) => DefaultTabController(
        length: hasBa ? 6 : 4,
        child: StatefulBuilder(builder: (mctx, setM) {
          return AlertDialog(
            titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
            contentPadding: EdgeInsets.zero,
            title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.business_center, color: Colors.deepPurple.shade700, size: 22),
                const SizedBox(width: 8),
                Expanded(child: Text(firmaName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.lock, size: 9, color: Colors.green.shade700),
                    const SizedBox(width: 2),
                    Text('AES-256', style: TextStyle(fontSize: 8, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                  ]),
                ),
                IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () async { await persist(); if (mctx.mounted) Navigator.pop(dlgCtx); await _load(); }),
              ]),
              const SizedBox(height: 4),
              TabBar(
                isScrollable: true,
                labelColor: Colors.deepPurple.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.deepPurple,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: [
                  const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                  const Tab(icon: Icon(Icons.history, size: 16), text: 'Bewerbung Status'),
                  const Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
                  if (hasBa) const Tab(icon: Icon(Icons.work_outline, size: 16), text: 'Stellenanzeige'),
                  if (hasBa) const Tab(icon: Icon(Icons.edit_note, size: 16), text: 'Anschreiben'),
                  const Tab(icon: Icon(Icons.description, size: 16), text: 'Lebenslauf'),
                ],
              ),
            ]),
            content: SizedBox(
              width: 720,
              height: 500,
              child: TabBarView(children: [
                _detailsTab(arbeitgeber, generalNotes, (v) async { generalNotes = v; await persist(); }),
                _statusJournalTab(statusJournal, (updated) async { setM(() => statusJournal = updated); await persist(); }),
                _korrespondenzTab(arbeitgeberId, korrespondenz, baRefnr, baTitel, baBeruf, (updated) async { setM(() => korrespondenz = updated); await persist(); }),
                if (hasBa) _StellenanzeigeTab(
                  apiService: widget.apiService,
                  userId: widget.userId,
                  refnr: baRefnr,
                  baTitel: baTitel,
                  baBeruf: baBeruf,
                  baMarkedAt: baMarkedAt,
                ),
                if (hasBa) _AnschreibenTab(
                  apiService: widget.apiService,
                  userId: widget.userId,
                  refnr: baRefnr,
                  firmaName: firmaName,
                ),
                _LebenslaufTab(
                  apiService: widget.apiService,
                  userId: widget.userId,
                  firmaName: firmaName,
                ),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ─── DETAILS TAB ───
  Widget _detailsTab(Map<String, dynamic> ag, String notes, Future<void> Function(String) onNotesSave) {
    final notesC = TextEditingController(text: notes);

    final firmaName = ag['firma_name']?.toString() ?? '';
    final firmaKurz = ag['firma_kurz']?.toString() ?? '';
    final branche = ag['branche']?.toString() ?? '';
    final rechtsform = ag['rechtsform']?.toString() ?? '';
    final website = ag['website']?.toString() ?? '';
    final geschaeftsfuehrer = ag['geschaeftsfuehrer']?.toString() ?? '';
    final ansprechpartner = ag['ansprechpartner_name']?.toString() ?? '';
    final registergericht = ag['registergericht']?.toString() ?? '';
    final registernummer = ag['registernummer']?.toString() ?? '';
    final steuernummer = ag['steuernummer']?.toString() ?? '';
    final ustId = ag['ust_id']?.toString() ?? '';

    final initial = firmaName.isNotEmpty ? firmaName.substring(0, 1).toUpperCase() : '?';

    // Hauptzentrale
    final hStrasse = ag['hauptzentrale_strasse']?.toString() ?? '';
    final hPlz = ag['hauptzentrale_plz']?.toString() ?? '';
    final hOrt = ag['hauptzentrale_ort']?.toString() ?? '';
    final hLand = ag['hauptzentrale_land']?.toString() ?? '';
    final hTel = ag['hauptzentrale_telefon']?.toString() ?? ag['telefon']?.toString() ?? '';
    final hFax = ag['hauptzentrale_fax']?.toString() ?? ag['fax']?.toString() ?? '';
    final hEmail = ag['hauptzentrale_email']?.toString() ?? ag['email']?.toString() ?? '';
    final hOeffnung = ag['hauptzentrale_oeffnungszeiten']?.toString() ?? '';

    // Niederlassung
    final nStrasse = ag['niederlassung_strasse']?.toString() ?? '';
    final nPlz = ag['niederlassung_plz']?.toString() ?? '';
    final nOrt = ag['niederlassung_ort']?.toString() ?? '';
    final nTel = ag['niederlassung_telefon']?.toString() ?? '';
    final nFax = ag['niederlassung_fax']?.toString() ?? '';
    final nEmail = ag['niederlassung_email']?.toString() ?? '';
    final nOeffnung = ag['niederlassung_oeffnungszeiten']?.toString() ?? '';
    final hasNL = nStrasse.isNotEmpty || nOrt.isNotEmpty || nTel.isNotEmpty || nEmail.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // ─── HERO HEADER ───
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.deepPurple.shade100, Colors.indigo.shade50],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.deepPurple.shade200),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            // Logo placeholder
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [Colors.deepPurple.shade400, Colors.deepPurple.shade700]),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(color: Colors.deepPurple.shade300, blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Center(
                child: Text(initial, style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SelectableText(firmaName, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade900, height: 1.1)),
              if (firmaKurz.isNotEmpty && firmaKurz != firmaName) ...[
                const SizedBox(height: 2),
                Text(firmaKurz, style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade600, fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 4, children: [
                if (rechtsform.isNotEmpty) _miniPill(Icons.gavel, rechtsform, Colors.indigo),
                if (branche.isNotEmpty) _miniPill(Icons.category, branche, Colors.teal),
              ]),
              if (website.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  Icon(Icons.public, size: 14, color: Colors.blue.shade700),
                  const SizedBox(width: 4),
                  Expanded(child: SelectableText(website, style: TextStyle(fontSize: 12, color: Colors.blue.shade700, decoration: TextDecoration.underline))),
                ]),
              ],
            ])),
          ]),
        ),
        const SizedBox(height: 16),

        // ─── KONTAKT GRID (Telefon, Fax, E-Mail) ───
        Text('Kontakt', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        const SizedBox(height: 8),
        Row(children: [
          if (hTel.isNotEmpty || nTel.isNotEmpty)
            Expanded(child: _contactCard(Icons.phone, 'Telefon', nTel.isNotEmpty ? nTel : hTel, nTel.isNotEmpty ? hTel : '', Colors.green)),
          if ((hTel.isNotEmpty || nTel.isNotEmpty) && (hFax.isNotEmpty || nFax.isNotEmpty)) const SizedBox(width: 10),
          if (hFax.isNotEmpty || nFax.isNotEmpty)
            Expanded(child: _contactCard(Icons.fax, 'Fax', nFax.isNotEmpty ? nFax : hFax, nFax.isNotEmpty ? hFax : '', Colors.deepPurple)),
        ]),
        if ((hTel.isNotEmpty || nTel.isNotEmpty || hFax.isNotEmpty || nFax.isNotEmpty) && (hEmail.isNotEmpty || nEmail.isNotEmpty))
          const SizedBox(height: 10),
        if (hEmail.isNotEmpty || nEmail.isNotEmpty)
          _contactCard(Icons.email, 'E-Mail', nEmail.isNotEmpty ? nEmail : hEmail, nEmail.isNotEmpty ? hEmail : '', Colors.blue, fullWidth: true),
        const SizedBox(height: 16),

        // ─── HAUPTSITZ ADDRESS ───
        if (hStrasse.isNotEmpty || hOrt.isNotEmpty) ...[
          _addressBlock('Hauptsitz', Icons.home_work, hStrasse, hPlz, hOrt, hLand, hOeffnung, Colors.indigo),
          const SizedBox(height: 10),
        ],

        // ─── NIEDERLASSUNG BIBERACH ───
        if (hasNL) ...[
          _addressBlock('Niederlassung Biberach', Icons.location_on, nStrasse, nPlz, nOrt, '', nOeffnung, Colors.deepPurple),
          const SizedBox(height: 10),
        ],

        // ─── RECHTLICHE DATEN ───
        if (geschaeftsfuehrer.isNotEmpty || ansprechpartner.isNotEmpty || registergericht.isNotEmpty || registernummer.isNotEmpty || steuernummer.isNotEmpty || ustId.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text('Rechtliche & Geschäftsdaten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (geschaeftsfuehrer.isNotEmpty) _legalRow(Icons.person, 'Geschäftsführer', geschaeftsfuehrer),
              if (ansprechpartner.isNotEmpty) _legalRow(Icons.contact_phone, 'Ansprechpartner', ansprechpartner),
              if (registergericht.isNotEmpty) _legalRow(Icons.account_balance, 'Registergericht', registergericht),
              if (registernummer.isNotEmpty) _legalRow(Icons.confirmation_number, 'HR-Nummer', registernummer),
              if (steuernummer.isNotEmpty) _legalRow(Icons.receipt_long, 'Steuernummer / CUI', steuernummer),
              if (ustId.isNotEmpty) _legalRow(Icons.euro, 'USt-IdNr.', ustId),
            ]),
          ),
          const SizedBox(height: 16),
        ],

        // ─── NOTIZEN ───
        Row(children: [
          Icon(Icons.sticky_note_2, size: 16, color: Colors.amber.shade700),
          const SizedBox(width: 6),
          Text('Allgemeine Notizen zur Bewerbung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
        ]),
        const SizedBox(height: 6),
        TextField(
          controller: notesC,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Z.B. Stellenausschreibung, Ansprechpartner-Notizen, Gehaltsvorstellung...',
            isDense: true,
            filled: true,
            fillColor: Colors.amber.shade50,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.amber.shade300)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.amber.shade200)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: onNotesSave,
        ),
      ]),
    );
  }

  Widget _miniPill(IconData icon, String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: color.shade200)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: color.shade700),
        const SizedBox(width: 4),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Text(text, style: TextStyle(fontSize: 10, color: color.shade800, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
        ),
      ]),
    );
  }

  Widget _contactCard(IconData icon, String label, String primary, String secondary, MaterialColor color, {bool fullWidth = false}) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.shade50, Colors.white]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.shade200),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(color: color.shade100, shape: BoxShape.circle),
          child: Icon(icon, size: 18, color: color.shade800),
        ),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 10, color: color.shade600, fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          SelectableText(primary, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade900)),
          if (secondary.isNotEmpty && secondary != primary) Padding(
            padding: const EdgeInsets.only(top: 2),
            child: SelectableText(secondary, style: TextStyle(fontSize: 11, color: color.shade500)),
          ),
        ])),
      ]),
    );
  }

  Widget _addressBlock(String title, IconData titleIcon, String strasse, String plz, String ort, String land, String oeffnung, MaterialColor color) {
    final addrLines = <String>[];
    if (strasse.isNotEmpty) addrLines.add(strasse);
    final plzOrt = [plz, ort].where((e) => e.isNotEmpty).join(' ');
    if (plzOrt.isNotEmpty) addrLines.add(plzOrt);
    if (land.isNotEmpty) addrLines.add(land);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(titleIcon, size: 16, color: color.shade700),
          const SizedBox(width: 6),
          Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800)),
        ]),
        const SizedBox(height: 6),
        ...addrLines.map((line) => Padding(
          padding: const EdgeInsets.only(left: 22, bottom: 1),
          child: SelectableText(line, style: TextStyle(fontSize: 13, color: Colors.grey.shade800)),
        )),
        if (oeffnung.isNotEmpty) Padding(
          padding: const EdgeInsets.only(left: 22, top: 4),
          child: Row(children: [
            Icon(Icons.schedule, size: 12, color: color.shade500),
            const SizedBox(width: 4),
            Expanded(child: Text(oeffnung, style: TextStyle(fontSize: 11, color: color.shade700, fontStyle: FontStyle.italic))),
          ]),
        ),
      ]),
    );
  }

  Widget _legalRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 8),
        SizedBox(width: 140, child: Text('$label:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
        Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  // ─── STATUS JOURNAL TAB ───
  Widget _statusJournalTab(List<Map<String, dynamic>> journal, Future<void> Function(List<Map<String, dynamic>>) onChanged) {
    final sorted = List<Map<String, dynamic>>.from(journal);
    sorted.sort((a, b) => (b['datum']?.toString() ?? '').compareTo(a['datum']?.toString() ?? ''));

    Future<void> addEntry({Map<String, dynamic>? existing}) async {
      final datumC = TextEditingController(text: existing?['datum']?.toString() ?? DateFormat('dd.MM.yyyy').format(DateTime.now()));
      String weg = existing?['weg']?.toString() ?? 'email';
      String status = existing?['status']?.toString() ?? 'gesendet';
      final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
      final isEdit = existing != null;

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
          title: Row(children: [
            Icon(isEdit ? Icons.edit : Icons.add_circle, color: Colors.deepPurple.shade700, size: 20),
            const SizedBox(width: 8),
            Text(isEdit ? 'Eintrag bearbeiten' : 'Neuer Status-Eintrag', style: const TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(width: 440, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
              controller: datumC,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Datum',
                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.edit_calendar, size: 16),
                  onPressed: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
                    if (picked != null) datumC.text = DateFormat('dd.MM.yyyy').format(picked);
                  },
                ),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text('Einreichungsweg (wie CV gesendet)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: _wege.entries.map((e) => ChoiceChip(
              avatar: Icon(e.value.icon, size: 13, color: weg == e.key ? Colors.white : e.value.color.shade700),
              label: Text(e.value.label, style: TextStyle(fontSize: 11, color: weg == e.key ? Colors.white : null)),
              selected: weg == e.key,
              selectedColor: e.value.color.shade600,
              onSelected: (_) => setDlg(() => weg = e.key),
            )).toList()),
            const SizedBox(height: 10),
            Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            DropdownButtonFormField<String>(
              initialValue: status,
              decoration: InputDecoration(isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              items: _statuses.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value.label, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setDlg(() => status = v ?? status),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: notizC,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Notiz',
                hintText: 'z.B. CV + Anschreiben angehängt, Position XY',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple),
              onPressed: () {
                Navigator.pop(ctx, {
                  'id': existing?['id'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
                  'datum': datumC.text.trim(),
                  'weg': weg,
                  'status': status,
                  'notiz': notizC.text.trim(),
                });
              },
              child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
            ),
          ],
        )),
      );

      if (result == null) return;
      final updated = List<Map<String, dynamic>>.from(journal);
      if (isEdit) {
        final idx = updated.indexWhere((e) => e['id'].toString() == existing['id'].toString());
        if (idx >= 0) updated[idx] = result;
      } else {
        updated.add(result);
      }
      await onChanged(updated);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(children: [
          Icon(Icons.history, color: Colors.deepPurple.shade700, size: 18),
          const SizedBox(width: 6),
          Text('Status-Journal', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.deepPurple.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text('${journal.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.deepPurple, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
            onPressed: () => addEntry(),
          ),
        ]),
      ),
      Expanded(
        child: sorted.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.history_toggle_off, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Noch keine Einträge', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text('Jeden CV-Versand als Eintrag dokumentieren', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final e = sorted[i];
                  final wegKey = e['weg']?.toString() ?? '';
                  final w = _wege[wegKey];
                  final st = _statuses[e['status']?.toString() ?? ''];
                  return Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.deepPurple.shade100)),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(color: (w?.color ?? Colors.grey).shade100, shape: BoxShape.circle),
                        child: Icon(w?.icon ?? Icons.help_outline, size: 18, color: (w?.color ?? Colors.grey).shade700),
                      ),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Text(e['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                          const SizedBox(width: 8),
                          if (w != null) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: w.color.shade50, borderRadius: BorderRadius.circular(8)),
                            child: Text(w.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: w.color.shade800)),
                          ),
                          const SizedBox(width: 6),
                          if (st != null) Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: st.color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: st.color.shade300)),
                            child: Text(st.label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: st.color.shade800)),
                          ),
                        ]),
                        if ((e['notiz']?.toString() ?? '').isNotEmpty) Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(e['notiz'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        ),
                      ])),
                      IconButton(
                        icon: Icon(Icons.edit, size: 16, color: Colors.orange.shade600),
                        tooltip: 'Bearbeiten',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () => addEntry(existing: e),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                        tooltip: 'Löschen',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () async {
                          final updated = List<Map<String, dynamic>>.from(journal)..removeWhere((x) => x['id'].toString() == e['id'].toString());
                          await onChanged(updated);
                        },
                      ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }

  // ─── KORRESPONDENZ TAB ───
  Widget _korrespondenzTab(int arbeitgeberId, List<Map<String, dynamic>> korr, String baRefnr, String baTitel, String baBeruf, Future<void> Function(List<Map<String, dynamic>>) onChanged) {
    final sorted = List<Map<String, dynamic>>.from(korr);
    sorted.sort((a, b) => (b['datum']?.toString() ?? '').compareTo(a['datum']?.toString() ?? ''));

    Future<void> addEntry({Map<String, dynamic>? existing}) async {
      final datumC = TextEditingController(text: existing?['datum']?.toString() ?? DateFormat('dd.MM.yyyy').format(DateTime.now()));
      String richtung = existing?['richtung']?.toString() ?? 'ausgang';
      String kanal = existing?['kanal']?.toString() ?? 'email';
      final betreffC = TextEditingController(text: existing?['betreff']?.toString() ?? '');
      final textC = TextEditingController(text: existing?['text']?.toString() ?? '');
      final isEdit = existing != null;
      bool generating = false;

      // Auto-Generieren aus Stellenanzeige — nur wenn ba_refnr vorhanden,
      // kanal=email, richtung=ausgang und es ist ein NEUER Eintrag.
      Future<void> autoFill(StateSetter setDlg) async {
        if (baRefnr.isEmpty) return;
        setDlg(() => generating = true);
        final tpl = await widget.apiService.generateEmailTemplate(
          userId: widget.userId, refnr: baRefnr,
        );
        if (!mounted) return;
        setDlg(() {
          generating = false;
          if (tpl != null) {
            betreffC.text = (tpl['betreff'] ?? '').toString();
            textC.text    = (tpl['text']    ?? '').toString();
          }
        });
        if (tpl == null) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Konnte kein Template erzeugen — Stelle bei BA nicht mehr abrufbar?'),
            backgroundColor: Colors.red,
          ));
        } else if (tpl['empfaenger_email'] != null && (tpl['empfaenger_email'] as String).isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Generiert · Empfaenger: ${tpl['empfaenger_email']}'),
            backgroundColor: Colors.green.shade700,
            duration: const Duration(seconds: 4),
          ));
        }
      }

      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setDlg) => AlertDialog(
          title: Row(children: [
            Icon(isEdit ? Icons.edit : Icons.email, color: Colors.indigo.shade700, size: 20),
            const SizedBox(width: 8),
            Text(isEdit ? 'Korrespondenz bearbeiten' : 'Neue Korrespondenz', style: const TextStyle(fontSize: 15)),
          ]),
          content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(child: ChoiceChip(
                label: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_received, size: 14), SizedBox(width: 4), Text('Eingang', style: TextStyle(fontSize: 12))]),
                selected: richtung == 'eingang',
                selectedColor: Colors.green.shade200,
                onSelected: (_) => setDlg(() => richtung = 'eingang'),
              )),
              const SizedBox(width: 8),
              Expanded(child: ChoiceChip(
                label: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.call_made, size: 14), SizedBox(width: 4), Text('Ausgang', style: TextStyle(fontSize: 12))]),
                selected: richtung == 'ausgang',
                selectedColor: Colors.blue.shade200,
                onSelected: (_) => setDlg(() => richtung = 'ausgang'),
              )),
            ]),
            const SizedBox(height: 10),
            TextField(
              controller: datumC,
              readOnly: true,
              decoration: InputDecoration(
                labelText: 'Datum',
                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.edit_calendar, size: 16),
                  onPressed: () async {
                    final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
                    if (picked != null) datumC.text = DateFormat('dd.MM.yyyy').format(picked);
                  },
                ),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            Text('Kanal', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            Wrap(spacing: 6, runSpacing: 4, children: _wege.entries.map((e) => ChoiceChip(
              avatar: Icon(e.value.icon, size: 13, color: kanal == e.key ? Colors.white : e.value.color.shade700),
              label: Text(e.value.label, style: TextStyle(fontSize: 11, color: kanal == e.key ? Colors.white : null)),
              selected: kanal == e.key,
              selectedColor: e.value.color.shade600,
              onSelected: (_) => setDlg(() => kanal = e.key),
            )).toList()),
            // Auto-Generieren nur sinnvoll bei E-Mail-Ausgang fuer BA-Stellen.
            if (baRefnr.isNotEmpty && kanal == 'email' && richtung == 'ausgang') ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.auto_awesome, size: 16, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text(
                    'BA-Stelle Ref. $baRefnr verfuegbar',
                    style: TextStyle(fontSize: 11, color: Colors.indigo.shade900),
                  )),
                  TextButton.icon(
                    onPressed: generating ? null : () => autoFill(setDlg),
                    icon: generating
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh, size: 14),
                    label: Text(generating ? 'Generiert…' : 'Auto-fuellen', style: const TextStyle(fontSize: 11)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.indigo.shade700,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ]),
              ),
            ],
            const SizedBox(height: 10),
            TextField(
              controller: betreffC,
              decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textC,
              maxLines: 8,
              decoration: InputDecoration(labelText: 'Text / Inhalt', hintText: 'Mailtext einkopieren oder Auto-fuellen druecken...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              style: const TextStyle(fontSize: 12),
            ),
          ]))),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.indigo),
              onPressed: () {
                Navigator.pop(ctx, {
                  'id': existing?['id'] ?? DateTime.now().millisecondsSinceEpoch,
                  'datum': datumC.text.trim(),
                  'richtung': richtung,
                  'kanal': kanal,
                  'betreff': betreffC.text.trim(),
                  'text': textC.text.trim(),
                });
              },
              child: Text(isEdit ? 'Speichern' : 'Hinzufügen'),
            ),
          ],
        )),
      );

      if (result == null) return;
      final updated = List<Map<String, dynamic>>.from(korr);
      if (isEdit) {
        final idx = updated.indexWhere((e) => e['id'].toString() == existing['id'].toString());
        if (idx >= 0) updated[idx] = result;
      } else {
        updated.add(result);
      }
      await onChanged(updated);
    }

    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
        child: Row(children: [
          Icon(Icons.email, color: Colors.indigo.shade700, size: 18),
          const SizedBox(width: 6),
          Text('E-Mail Korrespondenz', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: Colors.indigo.shade100, borderRadius: BorderRadius.circular(10)),
            child: Text('${korr.length}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
          ),
          const Spacer(),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: Colors.indigo, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6)),
            icon: const Icon(Icons.add, size: 14),
            label: const Text('Mail', style: TextStyle(fontSize: 11)),
            onPressed: () => addEntry(),
          ),
        ]),
      ),
      Expanded(
        child: sorted.isEmpty
            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.mark_email_unread_outlined, size: 40, color: Colors.grey.shade300),
                const SizedBox(height: 8),
                Text('Keine Korrespondenz erfasst', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Text('Eingehende & ausgehende Mails + PDF-Anhänge hier dokumentieren', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
              ]))
            : ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                itemCount: sorted.length,
                itemBuilder: (_, i) {
                  final e = sorted[i];
                  final isEingang = e['richtung']?.toString() == 'eingang';
                  final kanal = _wege[e['kanal']?.toString() ?? 'email'];
                  final korrId = e['id'] is int ? e['id'] as int : int.tryParse(e['id'].toString()) ?? 0;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: isEingang ? Colors.green.shade200 : Colors.blue.shade200),
                    ),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: isEingang ? Colors.green.shade50 : Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(isEingang ? Icons.call_received : Icons.call_made, size: 11, color: isEingang ? Colors.green.shade700 : Colors.blue.shade700),
                            const SizedBox(width: 3),
                            Text(isEingang ? 'EINGANG' : 'AUSGANG', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isEingang ? Colors.green.shade700 : Colors.blue.shade700)),
                          ]),
                        ),
                        const SizedBox(width: 6),
                        Text(e['datum']?.toString() ?? '', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                        if (kanal != null) ...[
                          const SizedBox(width: 6),
                          Icon(kanal.icon, size: 12, color: kanal.color.shade700),
                        ],
                        const Spacer(),
                        IconButton(
                          icon: Icon(Icons.edit, size: 14, color: Colors.orange.shade600),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          tooltip: 'Bearbeiten',
                          onPressed: () => addEntry(existing: e),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                          tooltip: 'Löschen',
                          onPressed: () async {
                            final updated = List<Map<String, dynamic>>.from(korr)..removeWhere((x) => x['id'].toString() == e['id'].toString());
                            await onChanged(updated);
                          },
                        ),
                      ]),
                      if ((e['betreff']?.toString() ?? '').isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(e['betreff'].toString(), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                      ),
                      if ((e['text']?.toString() ?? '').isNotEmpty) Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
                          child: Text(e['text'].toString(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // PDF Anhänge (existing infrastructure)
                      if (korrId > 0)
                        KorrAttachmentsWidget(
                          apiService: widget.apiService,
                          modul: 'bewerbung_${widget.userId}_$arbeitgeberId',
                          korrespondenzId: korrId,
                        ),
                    ]),
                  );
                },
              ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// Tab "Stellenanzeige" — sichtbar nur, wenn die Bewerbung urspruenglich
// aus der Bundesagentur-Jobsuche kam (ba_refnr gesetzt). Laedt den
// Volltext der Stelle live ueber /pc/v4/jobdetails — wenn die Anzeige
// inzwischen offline ist, sehen wir 'Stelle nicht mehr verfuegbar'.
// ─────────────────────────────────────────────────────────────────
class _StellenanzeigeTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String refnr;
  final String baTitel;
  final String baBeruf;
  final String baMarkedAt;
  const _StellenanzeigeTab({
    required this.apiService,
    required this.userId,
    required this.refnr,
    required this.baTitel,
    required this.baBeruf,
    required this.baMarkedAt,
  });

  @override
  State<_StellenanzeigeTab> createState() => _StellenanzeigeTabState();
}

class _StellenanzeigeTabState extends State<_StellenanzeigeTab> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  String? _error;

  static final _emailRe = RegExp(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}');
  static final _telRe = RegExp(r'(?:\+49[\s\-/]?|\(?0\)?[\s\-/]?)\d[\d\s\-/()]{6,}\d');

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.getStellenangebotDetail(widget.refnr);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _detail = res;
      if (res == null) _error = 'Stelle nicht mehr verfuegbar bei der Bundesagentur';
    });
    // Synchronisiere DB-Flag mit Live-Status — so erscheint das orange
    // Badge in der Bewerbungsuebersicht beim naechsten Reload.
    widget.apiService.markBewerbungBaExpired(
      userId: widget.userId,
      refnr: widget.refnr,
      expired: res == null,
    );
  }

  Future<void> _launch(String url) async {
    final uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Konnte $url nicht oeffnen')));
    }
  }

  List<String> _extractAll(String text, RegExp re) =>
      re.allMatches(text).map((m) => m.group(0)!.trim()).toSet().toList();

  Widget _row(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 14, color: Colors.grey.shade600), const SizedBox(width: 6),
      Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
    ]),
  );

  Widget _badge(IconData icon, String text, MaterialColor color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: color.shade200)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 12, color: color.shade800), const SizedBox(width: 4),
      Text(text, style: TextStyle(fontSize: 11, color: color.shade900)),
    ]),
  );

  String _arbeitszeitLabel(Map<String, dynamic> d) {
    final parts = <String>[];
    if (d['arbeitszeitVollzeit'] == true) parts.add('Vollzeit');
    if (d['arbeitszeitTeilzeit'] == true) parts.add('Teilzeit');
    if (d['arbeitszeitMinijob'] == true) parts.add('Minijob');
    if (d['arbeitszeitSchichtNachtWochenende'] == true) parts.add('Schicht/Nacht/Wo');
    if (d['arbeitszeitHeimTelearbeit'] == true) parts.add('Home-Office');
    if (d['istGeringfuegigeBeschaeftigung'] == true && !parts.contains('Minijob')) parts.add('Minijob');
    return parts.join(' · ');
  }

  String _adresseLabel(Map<String, dynamic>? loc) {
    if (loc == null) return '';
    final a = (loc['adresse'] is Map) ? loc['adresse'] as Map : <String, dynamic>{};
    final strasse = a['strasse']?.toString() ?? '';
    final hausnr = a['hausnummer']?.toString() ?? '';
    final plz = a['plz']?.toString() ?? '';
    final ort = a['ort']?.toString() ?? '';
    return [
      if (strasse.isNotEmpty) '$strasse${hausnr.isNotEmpty ? " $hausnr" : ""}',
      if (plz.isNotEmpty || ort.isNotEmpty) '$plz $ort'.trim(),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    // Always show marked-at + fallback title even if detail is gone
    Widget header() => Container(
      padding: const EdgeInsets.all(10),
      color: Colors.indigo.shade50,
      child: Row(children: [
        Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'Markiert als beworben${widget.baMarkedAt.isNotEmpty ? " am ${widget.baMarkedAt.split('T').first.split(' ').first}" : ""}',
          style: TextStyle(fontSize: 11, color: Colors.green.shade900, fontWeight: FontWeight.bold),
        )),
        Text('Ref ${widget.refnr}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
      ]),
    );

    if (_error != null || _detail == null) {
      return Column(children: [
        header(),
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(_error ?? 'Keine Daten', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          if (widget.baTitel.isNotEmpty) Text(widget.baTitel, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
          if (widget.baBeruf.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(widget.baBeruf, style: const TextStyle(fontSize: 12, color: Colors.grey))),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: () => _launch('https://www.arbeitsagentur.de/jobsuche/jobdetail/${widget.refnr}'),
            icon: const Icon(Icons.open_in_new, size: 14),
            label: const Text('Auf arbeitsagentur.de versuchen'),
          ),
        ])))),
      ]);
    }

    final d = _detail!;
    final titel = (d['stellenangebotsTitel'] ?? widget.baTitel).toString();
    final firma = (d['firma'] ?? '').toString();
    final hauptberuf = (d['hauptberuf'] ?? widget.baBeruf).toString();
    final alt1 = (d['alternativBeruf1'] ?? '').toString();
    final alt2 = (d['alternativBeruf2'] ?? '').toString();
    final vertrag = (d['vertragsdauer'] ?? '').toString();
    final vergueteung = (d['verguetungsangabe'] ?? '').toString();
    final eintritt = ((d['eintrittszeitraum'] is Map ? d['eintrittszeitraum']['von'] : null) ?? '').toString().split('T').first;
    final beschreibung = (d['stellenangebotsBeschreibung'] ?? '').toString();
    final loc = (d['stellenlokationen'] is List && (d['stellenlokationen'] as List).isNotEmpty)
        ? (d['stellenlokationen'] as List).first as Map<String, dynamic>
        : null;
    final adresse = _adresseLabel(loc);
    final lat = loc?['breite'];
    final lon = loc?['laenge'];
    final emails = beschreibung.isEmpty ? <String>[] : _extractAll(beschreibung, _emailRe);
    final tels = beschreibung.isEmpty ? <String>[] : _extractAll(beschreibung, _telRe);

    return Column(children: [
      header(),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(titel, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        if (firma.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Text(firma, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 4, children: [
          if (_arbeitszeitLabel(d).isNotEmpty) _badge(Icons.access_time, _arbeitszeitLabel(d), Colors.blue),
          if (vertrag.isNotEmpty) _badge(Icons.event_repeat, vertrag, Colors.purple),
          if (eintritt.isNotEmpty) _badge(Icons.event, 'ab $eintritt', Colors.green),
          if (vergueteung.isNotEmpty && vergueteung != 'KEINE_ANGABEN') _badge(Icons.euro, vergueteung, Colors.orange),
          if (d['quereinstiegGeeignet'] == true) _badge(Icons.swap_horiz, 'Quereinstieg', Colors.teal),
        ]),
        const SizedBox(height: 12),
        if (hauptberuf.isNotEmpty) _row(Icons.work, 'Hauptberuf: $hauptberuf'),
        if (alt1.isNotEmpty) _row(Icons.alt_route, 'Alternativ: $alt1'),
        if (alt2.isNotEmpty) _row(Icons.alt_route, 'Alternativ: $alt2'),
        if (adresse.isNotEmpty) Row(children: [
          Expanded(child: _row(Icons.location_on, adresse)),
          if (lat != null && lon != null) TextButton.icon(
            onPressed: () => _launch('https://www.google.com/maps/search/?api=1&query=$lat,$lon'),
            icon: const Icon(Icons.map, size: 14), label: const Text('Karte', style: TextStyle(fontSize: 11)),
          ),
        ]),
        if (emails.isNotEmpty || tels.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(Icons.contact_mail, size: 14, color: Colors.green.shade800), const SizedBox(width: 4),
                Text('Bewerbungs-Kontakt aus Anzeige', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green.shade900)),
              ]),
              const SizedBox(height: 4),
              Wrap(spacing: 6, runSpacing: 4, children: [
                ...emails.map((e) => ActionChip(
                  avatar: const Icon(Icons.email, size: 12),
                  label: Text(e, style: const TextStyle(fontSize: 10)),
                  visualDensity: VisualDensity.compact,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: e));
                    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e kopiert'), duration: const Duration(seconds: 1)));
                  },
                )),
                ...tels.map((t) {
                  final digits = t.replaceAll(RegExp(r'[^\d+]'), '');
                  return ActionChip(
                    avatar: const Icon(Icons.phone, size: 12),
                    label: Text(t, style: const TextStyle(fontSize: 10)),
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: digits));
                      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$digits kopiert'), duration: const Duration(seconds: 1)));
                    },
                  );
                }),
              ]),
            ]),
          ),
        ],
        if (beschreibung.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('Beschreibung', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.grey.shade200)),
            child: SelectableText(beschreibung, style: const TextStyle(fontSize: 12, height: 1.4)),
          ),
        ],
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerRight, child: ElevatedButton.icon(
          onPressed: () => _launch('https://www.arbeitsagentur.de/jobsuche/jobdetail/${widget.refnr}'),
          icon: const Icon(Icons.open_in_new, size: 14),
          label: const Text('Auf arbeitsagentur.de oeffnen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
        )),
      ]))),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// Tab "Lebenslauf" — generiert den DIN-5008-Lebenslauf server-seitig
// (mPDF) aus Mitgliederverwaltung + Behoerde-Daten + Stellen-Tab
// (Berufserfahrung, Schulbildung, Fuehrerschein, Sprachen,
// Gabelstaplerschein, koerperliche Einschraenkung) und zeigt ihn
// direkt im Modal. Nichts wird zwischengespeichert — bei jedem
// Tab-Wechsel wird ein frischer PDF generiert, damit Aenderungen
// in den Stammdaten sofort sichtbar sind.
// ─────────────────────────────────────────────────────────────────
class _LebenslaufTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String firmaName;
  const _LebenslaufTab({
    required this.apiService,
    required this.userId,
    required this.firmaName,
  });

  @override
  State<_LebenslaufTab> createState() => _LebenslaufTabState();
}

class _LebenslaufTabState extends State<_LebenslaufTab> with AutomaticKeepAliveClientMixin {
  Uint8List? _bytes;
  String _filename = 'Lebenslauf.pdf';
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await widget.apiService.generateLebenslaufPdfServer(widget.userId);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null || res.bytes.isEmpty) {
        _error = 'PDF konnte nicht erstellt werden — fehlen Stammdaten?';
      } else {
        _bytes = res.bytes;
        _filename = res.filename;
      }
    });
  }

  Future<void> _saveToDisk() async {
    if (_bytes == null) return;
    try {
      // Server liefert 'Lebenslauf_Vorname_Nachname.pdf' via
      // Content-Disposition — Standard fuer Bewerbungs-PDFs.
      final path = await FilePickerHelper.saveFile(
        dialogTitle: 'Lebenslauf speichern',
        fileName: _filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) return; // User abgebrochen
      final saveAt = path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';
      await File(saveAt).writeAsBytes(_bytes!, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Lebenslauf gespeichert: $saveAt'),
        backgroundColor: Colors.green.shade700,
        action: SnackBarAction(
          label: 'Öffnen',
          textColor: Colors.white,
          onPressed: () => launchUrl(Uri.file(saveAt)),
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speicherfehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _print() async {
    if (_bytes == null) return;
    try {
      await Printing.layoutPdf(onLayout: (_) async => _bytes!, name: 'Lebenslauf');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Druckfehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget header() => Container(
      padding: const EdgeInsets.all(10),
      color: Colors.deepPurple.shade50,
      child: Row(children: [
        Icon(Icons.description, size: 16, color: Colors.deepPurple.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'Lebenslauf (DIN 5008, zweispaltig) — generiert vom Server',
          style: TextStyle(fontSize: 11, color: Colors.deepPurple.shade900, fontWeight: FontWeight.bold),
        )),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: 'Neu generieren',
          onPressed: _loading ? null : _load,
          color: Colors.deepPurple.shade700,
        ),
      ]),
    );

    if (_loading) {
      return Column(children: [
        header(),
        const Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('PDF wird generiert…', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]))),
      ]);
    }

    if (_error != null || _bytes == null) {
      return Column(children: [
        header(),
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(_error ?? 'Kein PDF', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Erneut versuchen'),
          ),
        ])))),
      ]);
    }

    return Column(children: [
      header(),
      Expanded(
        child: Container(
          color: Colors.grey.shade300,
          child: PdfViewer.data(_bytes!, sourceName: 'Lebenslauf_${widget.userId}.pdf'),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(children: [
          Icon(Icons.info_outline, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Expanded(child: Text(
            '${(_bytes!.length / 1024).toStringAsFixed(1)} KB · aus Stammdaten + Berufserfahrung',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
          )),
          TextButton.icon(
            onPressed: _print,
            icon: const Icon(Icons.print, size: 14),
            label: const Text('Drucken', style: TextStyle(fontSize: 11)),
          ),
          TextButton.icon(
            onPressed: _saveToDisk,
            icon: const Icon(Icons.download, size: 14),
            label: const Text('Speichern', style: TextStyle(fontSize: 11)),
          ),
        ]),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────
// Tab "Anschreiben" — sichtbar nur, wenn die Bewerbung eine BA-Refnr
// hat. Verbindet:
//   Stellenanzeige (live BA-API: hauptberuf, firma, ansprechpartner,
//     beschreibung → Anforderungen)
//   + Lebenslauf-Daten (berufserfahrung, fuehrerschein, stapler,
//     sprachen)
// Ergebnis: 1-seitiges PDF nach DIN 5008 Form B mit Keyword-Match.
// ─────────────────────────────────────────────────────────────────
class _AnschreibenTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final String refnr;
  final String firmaName;
  const _AnschreibenTab({
    required this.apiService,
    required this.userId,
    required this.refnr,
    required this.firmaName,
  });

  @override
  State<_AnschreibenTab> createState() => _AnschreibenTabState();
}

class _AnschreibenTabState extends State<_AnschreibenTab> with AutomaticKeepAliveClientMixin {
  Uint8List? _bytes;
  String _filename = 'Anschreiben.pdf';
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    final res = await widget.apiService.generateAnschreibenPdfServer(
      userId: widget.userId,
      refnr: widget.refnr,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res == null || res.bytes.isEmpty) {
        _error = 'Anschreiben konnte nicht erzeugt werden — Stelle bei BA nicht abrufbar?';
      } else {
        _bytes = res.bytes;
        _filename = res.filename;
      }
    });
  }

  Future<void> _saveToDisk() async {
    if (_bytes == null) return;
    try {
      // Server liefert 'Anschreiben_Vorname_Nachname_Firma.pdf' via
      // Content-Disposition — Standard fuer Bewerbungs-PDFs.
      final path = await FilePickerHelper.saveFile(
        dialogTitle: 'Anschreiben speichern',
        fileName: _filename,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (path == null) return; // User abgebrochen
      final saveAt = path.toLowerCase().endsWith('.pdf') ? path : '$path.pdf';
      await File(saveAt).writeAsBytes(_bytes!, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Anschreiben gespeichert: $saveAt'),
        backgroundColor: Colors.green.shade700,
        action: SnackBarAction(
          label: 'Öffnen',
          textColor: Colors.white,
          onPressed: () => launchUrl(Uri.file(saveAt)),
        ),
      ));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Speicherfehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _print() async {
    if (_bytes == null) return;
    try {
      await Printing.layoutPdf(onLayout: (_) async => _bytes!, name: 'Anschreiben');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Druckfehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    Widget header() => Container(
      padding: const EdgeInsets.all(10),
      color: Colors.teal.shade50,
      child: Row(children: [
        Icon(Icons.edit_note, size: 16, color: Colors.teal.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text(
          'Anschreiben (DIN 5008 Form B) · auto-generiert aus Stelle + Lebenslauf',
          style: TextStyle(fontSize: 11, color: Colors.teal.shade900, fontWeight: FontWeight.bold),
        )),
        IconButton(
          icon: const Icon(Icons.refresh, size: 18),
          tooltip: 'Neu generieren',
          onPressed: _loading ? null : _load,
          color: Colors.teal.shade700,
        ),
      ]),
    );

    if (_loading) {
      return Column(children: [
        header(),
        const Expanded(child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Stelle wird live von BA geladen + Match-Algorithmus laeuft…', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]))),
      ]);
    }

    if (_error != null || _bytes == null) {
      return Column(children: [
        header(),
        Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(20), child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text(_error ?? 'Kein PDF', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
          const SizedBox(height: 12),
          TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh, size: 14), label: const Text('Erneut versuchen')),
        ])))),
      ]);
    }

    return Column(children: [
      header(),
      Expanded(
        child: Container(
          color: Colors.grey.shade300,
          child: PdfViewer.data(_bytes!, sourceName: 'Anschreiben_${widget.refnr}.pdf'),
        ),
      ),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
        child: Row(children: [
          Icon(Icons.tips_and_updates, size: 12, color: Colors.grey.shade600),
          const SizedBox(width: 4),
          Expanded(child: Text(
            '${(_bytes!.length / 1024).toStringAsFixed(1)} KB · Keyword-Match aus Anzeige + Lebenslauf',
            style: TextStyle(fontSize: 10, color: Colors.grey.shade700),
          )),
          TextButton.icon(
            onPressed: _print,
            icon: const Icon(Icons.print, size: 14),
            label: const Text('Drucken', style: TextStyle(fontSize: 11)),
          ),
          TextButton.icon(
            onPressed: _saveToDisk,
            icon: const Icon(Icons.download, size: 14),
            label: const Text('Speichern', style: TextStyle(fontSize: 11)),
          ),
        ]),
      ),
    ]);
  }
}
