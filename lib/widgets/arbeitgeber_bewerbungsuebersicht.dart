import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
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
    final dataField = res['data'] is Map ? Map<String, dynamic>.from(res['data'] as Map) : <String, dynamic>{};
    final arbeitgeber = dataField['arbeitgeber'] is Map ? Map<String, dynamic>.from(dataField['arbeitgeber'] as Map) : <String, dynamic>{};
    final inner = dataField['data'] is Map ? Map<String, dynamic>.from(dataField['data'] as Map) : <String, dynamic>{};

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
        length: 3,
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
                labelColor: Colors.deepPurple.shade700,
                unselectedLabelColor: Colors.grey.shade600,
                indicatorColor: Colors.deepPurple,
                labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                tabs: const [
                  Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
                  Tab(icon: Icon(Icons.history, size: 16), text: 'Bewerbung Status'),
                  Tab(icon: Icon(Icons.email, size: 16), text: 'Korrespondenz'),
                ],
              ),
            ]),
            content: SizedBox(
              width: 720,
              height: 500,
              child: TabBarView(children: [
                _detailsTab(arbeitgeber, generalNotes, (v) async { generalNotes = v; await persist(); }),
                _statusJournalTab(statusJournal, (updated) async { setM(() => statusJournal = updated); await persist(); }),
                _korrespondenzTab(arbeitgeberId, korrespondenz, (updated) async { setM(() => korrespondenz = updated); await persist(); }),
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
    Widget infoRow(IconData icon, String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 16, color: Colors.deepPurple.shade400),
          const SizedBox(width: 8),
          SizedBox(width: 130, child: Text('$label:', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
          Expanded(child: SelectableText(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
        ]),
      );
    }

    final hStrasse = ag['hauptzentrale_strasse']?.toString() ?? '';
    final hPlz = ag['hauptzentrale_plz']?.toString() ?? '';
    final hOrt = ag['hauptzentrale_ort']?.toString() ?? '';
    final hLand = ag['hauptzentrale_land']?.toString() ?? '';
    final hzAddress = [hStrasse, [hPlz, hOrt].where((e) => e.isNotEmpty).join(' '), hLand].where((e) => e.isNotEmpty).join(', ');

    final nStrasse = ag['niederlassung_strasse']?.toString() ?? '';
    final nPlz = ag['niederlassung_plz']?.toString() ?? '';
    final nOrt = ag['niederlassung_ort']?.toString() ?? '';
    final nAddress = [nStrasse, [nPlz, nOrt].where((e) => e.isNotEmpty).join(' ')].where((e) => e.isNotEmpty).join(', ');

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Arbeitgeber details
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.deepPurple.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.deepPurple.shade200)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Arbeitgeber-Informationen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
            const SizedBox(height: 8),
            infoRow(Icons.business, 'Firma', ag['firma_name']?.toString()),
            infoRow(Icons.label, 'Kurz', ag['firma_kurz']?.toString()),
            infoRow(Icons.gavel, 'Rechtsform', ag['rechtsform']?.toString()),
            infoRow(Icons.category, 'Branche', ag['branche']?.toString()),
            if (hzAddress.isNotEmpty) infoRow(Icons.home_work, 'Hauptzentrale', hzAddress),
            infoRow(Icons.phone, 'HZ Telefon', ag['hauptzentrale_telefon']?.toString()),
            infoRow(Icons.email, 'HZ E-Mail', ag['hauptzentrale_email']?.toString()),
            if (nAddress.isNotEmpty) infoRow(Icons.location_on, 'Niederlassung', nAddress),
            infoRow(Icons.phone_forwarded, 'NL Telefon', ag['niederlassung_telefon']?.toString()),
            infoRow(Icons.alternate_email, 'NL E-Mail', ag['niederlassung_email']?.toString()),
            infoRow(Icons.public, 'Website', ag['website']?.toString()),
            infoRow(Icons.person, 'Geschäftsführer', ag['geschaeftsfuehrer']?.toString()),
            infoRow(Icons.contact_phone, 'Ansprechpartner', ag['ansprechpartner_name']?.toString()),
            infoRow(Icons.account_balance, 'Registergericht', ag['registergericht']?.toString()),
            infoRow(Icons.confirmation_number, 'HR-Nummer', ag['registernummer']?.toString()),
            infoRow(Icons.receipt_long, 'Steuernummer', ag['steuernummer']?.toString()),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Allgemeine Notizen zur Bewerbung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
        const SizedBox(height: 4),
        TextField(
          controller: notesC,
          maxLines: 4,
          decoration: InputDecoration(
            hintText: 'Z.B. Stellenausschreibung, Ansprechpartner-Notizen...',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          style: const TextStyle(fontSize: 13),
          onChanged: onNotesSave,
        ),
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
  Widget _korrespondenzTab(int arbeitgeberId, List<Map<String, dynamic>> korr, Future<void> Function(List<Map<String, dynamic>>) onChanged) {
    final sorted = List<Map<String, dynamic>>.from(korr);
    sorted.sort((a, b) => (b['datum']?.toString() ?? '').compareTo(a['datum']?.toString() ?? ''));

    Future<void> addEntry({Map<String, dynamic>? existing}) async {
      final datumC = TextEditingController(text: existing?['datum']?.toString() ?? DateFormat('dd.MM.yyyy').format(DateTime.now()));
      String richtung = existing?['richtung']?.toString() ?? 'ausgang';
      String kanal = existing?['kanal']?.toString() ?? 'email';
      final betreffC = TextEditingController(text: existing?['betreff']?.toString() ?? '');
      final textC = TextEditingController(text: existing?['text']?.toString() ?? '');
      final isEdit = existing != null;

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
            const SizedBox(height: 10),
            TextField(
              controller: betreffC,
              decoration: InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
              style: const TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: textC,
              maxLines: 5,
              decoration: InputDecoration(labelText: 'Text / Inhalt', hintText: 'Mailtext einkopieren...', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
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
