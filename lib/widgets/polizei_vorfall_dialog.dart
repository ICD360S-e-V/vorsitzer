import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';

class PolizeiVorfallDialog extends StatefulWidget {
  final ApiService apiService;
  final int vorfallId;
  final String mitgliedernummer;
  final VoidCallback onUpdated;

  const PolizeiVorfallDialog({super.key, required this.apiService, required this.vorfallId, required this.mitgliedernummer, required this.onUpdated});

  static Future<void> show(BuildContext context, ApiService apiService, int vorfallId, String mitgliedernummer, VoidCallback onUpdated) {
    return showDialog(context: context, builder: (_) => PolizeiVorfallDialog(apiService: apiService, vorfallId: vorfallId, mitgliedernummer: mitgliedernummer, onUpdated: onUpdated));
  }

  @override
  State<PolizeiVorfallDialog> createState() => _PolizeiVorfallDialogState();
}

class _PolizeiVorfallDialogState extends State<PolizeiVorfallDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = true;
  bool _uploading = false;
  Map<String, dynamic>? _vorfall;
  List<Map<String, dynamic>> _dokumente = [];
  List<Map<String, dynamic>> _korrespondenz = [];
  List<Map<String, dynamic>> _zahlungen = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadData();
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final result = await widget.apiService.getPolizeiVorfallDetails(widget.vorfallId);
      if (mounted && result['success'] == true) {
        _vorfall = result['vorfall'] as Map<String, dynamic>?;
        _dokumente = List<Map<String, dynamic>>.from(result['dokumente'] ?? []);
        _korrespondenz = List<Map<String, dynamic>>.from(result['korrespondenz'] ?? []);
        _zahlungen = List<Map<String, dynamic>>.from(result['zahlungen'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(width: 750, height: 600, child: Column(children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.blue.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(12))),
          child: Row(children: [
            const Icon(Icons.report, color: Colors.white, size: 24), const SizedBox(width: 10),
            Expanded(child: Text(_vorfall != null ? 'Vorfall: ${_vorfall!['typ'] ?? ''}' : 'Vorfall', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold))),
            if (_vorfall?['aktenzeichen'] != null && _vorfall!['aktenzeichen'].toString().isNotEmpty)
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(4)),
                child: Text('Az: ${_vorfall!['aktenzeichen']}', style: const TextStyle(color: Colors.white, fontSize: 12))),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context)),
          ]),
        ),
        Container(color: Colors.blue.shade50, child: TabBar(controller: _tabController, labelColor: Colors.blue.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.blue.shade700,
          tabs: const [
            Tab(icon: Icon(Icons.info, size: 18), text: 'Details'),
            Tab(icon: Icon(Icons.folder, size: 18), text: 'Dokumente'),
            Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
            Tab(icon: Icon(Icons.payment, size: 18), text: 'Zahlungen'),
          ],
        )),
        Expanded(child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(controller: _tabController, children: [_buildDetailsTab(), _buildDokumenteTab(), _buildKorrespondenzTab(), _buildZahlungenTab()]),
        ),
      ])),
    );
  }

  // ==================== DETAILS ====================
  Widget _buildDetailsTab() {
    if (_vorfall == null) return const Center(child: Text('Keine Daten'));
    final v = _vorfall!;
    final datum = (v['datum'] ?? '').toString();
    final fDatum = datum.contains('-') ? datum.split('-').reversed.join('.') : datum;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _detailRow('Art', v['typ'] ?? '-'), _detailRow('Datum', fDatum.isNotEmpty ? fDatum : '-'),
      _detailRow('Aktenzeichen', v['aktenzeichen'] ?? '-'), _detailRow('Status', _statusLabel(v['status'])),
      _detailRow('Sachbearbeiter', v['sachbearbeiter_name'] ?? '-'), _detailRow('Durchwahl', v['sachbearbeiter_telefon'] ?? '-'),
      const Divider(height: 24),
      const Text('Beschreibung', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)), const SizedBox(height: 6),
      Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
        child: Text(v['beschreibung'] ?? 'Keine Beschreibung', style: const TextStyle(fontSize: 13))),
    ]));
  }

  // ==================== DOKUMENTE ====================
  Widget _buildDokumenteTab() {
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Dokumente (${_dokumente.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ElevatedButton.icon(
          icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file, size: 18),
          label: Text(_uploading ? 'Wird hochgeladen...' : 'Hochladen (max 20)'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
          onPressed: _uploading ? null : _uploadDokumente,
        ),
      ]),
      const Divider(height: 24),
      Expanded(child: _dokumente.isEmpty
        ? Center(child: Text('Keine Dokumente', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _dokumente.length, itemBuilder: (_, i) => _buildDocItem(_dokumente[i]))),
    ]));
  }

  Future<void> _uploadDokumente() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'tiff', 'bmp', 'doc', 'docx'],
      allowMultiple: true,
      dialogTitle: 'Dokumente auswählen (max 20)',
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.where((f) => f.path != null).take(20).map((f) => f.path!).toList();
    if (paths.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final uploadResult = await widget.apiService.uploadPolizeiVorfallDokumente(widget.vorfallId, paths, widget.mitgliedernummer);
      if (mounted) {
        final count = (uploadResult['uploaded'] as List?)?.length ?? 0;
        final errors = (uploadResult['errors'] as List?)?.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count Dokument(e) hochgeladen${errors > 0 ? ', $errors Fehler' : ''}'),
          backgroundColor: errors > 0 ? Colors.orange : Colors.green,
        ));
        _loadData();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _uploading = false);
  }

  Widget _buildDocItem(Map<String, dynamic> doc) {
    final name = doc['original_name'] ?? 'Unbekannt';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    IconData icon = Icons.insert_drive_file;
    Color color = Colors.grey;
    if (ext == 'pdf') { icon = Icons.picture_as_pdf; color = Colors.red; }
    else if (['jpg','jpeg','png','tiff','bmp'].contains(ext)) { icon = Icons.image; color = Colors.blue; }
    else if (['doc','docx'].contains(ext)) { icon = Icons.description; color = Colors.indigo; }

    return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
      leading: Icon(icon, color: color), title: Text(name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(_formatDate(doc['created_at']), style: const TextStyle(fontSize: 11)),
      dense: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.blue.shade600), tooltip: 'Anzeigen', onPressed: () => _viewDoc(doc)),
        IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () => _deleteDoc(doc)),
      ]),
    ));
  }

  Future<void> _viewDoc(Map<String, dynamic> doc) async {
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    final response = await widget.apiService.downloadPolizeiVorfallDokument(docId);
    if (response == null || !mounted) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${doc['original_name']}';
      await File(filePath).writeAsBytes(response.bodyBytes);
      if (mounted) await FileViewerDialog.show(context, filePath, doc['original_name']);
    } catch (_) {}
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument löschen?'), content: Text('"${doc['original_name']}" wirklich löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen'))],
    ));
    if (confirmed != true) return;
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    await widget.apiService.deletePolizeiVorfallDokument(docId);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gelöscht'), backgroundColor: Colors.green)); _loadData(); }
  }

  // ==================== KORRESPONDENZ ====================
  Widget _buildKorrespondenzTab() {
    final eingang = _korrespondenz.where((k) => k['richtung'] == 'eingang').toList();
    final ausgang = _korrespondenz.where((k) => k['richtung'] == 'ausgang').toList();
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Korrespondenz (${_korrespondenz.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Hinzufügen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white), onPressed: _addKorrespondenz),
      ]),
      const Divider(height: 24),
      Expanded(child: _korrespondenz.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)))
        : ListView(children: [
            if (eingang.isNotEmpty) ...[_sectionLabel('Eingang', Icons.inbox, Colors.green), ...eingang.map(_buildKorrItem)],
            if (ausgang.isNotEmpty) ...[const SizedBox(height: 12), _sectionLabel('Ausgang', Icons.outbox, Colors.orange), ...ausgang.map(_buildKorrItem)],
          ])),
    ]));
  }

  Future<void> _addKorrespondenz() async {
    final betreffC = TextEditingController(); final inhaltC = TextEditingController(); final datumC = TextEditingController();
    String richtung = 'eingang';
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      title: const Text('Korrespondenz hinzufügen'),
      content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
        SegmentedButton<String>(segments: const [
          ButtonSegment(value: 'eingang', label: Text('Eingang'), icon: Icon(Icons.inbox, size: 16)),
          ButtonSegment(value: 'ausgang', label: Text('Ausgang'), icon: Icon(Icons.outbox, size: 16)),
        ], selected: {richtung}, onSelectionChanged: (v) => ss(() => richtung = v.first)),
        const SizedBox(height: 8),
        TextField(controller: datumC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Datum (TT.MM.JJJJ)', isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: betreffC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Betreff', isDense: true)),
        const SizedBox(height: 8),
        TextField(controller: inhaltC, maxLines: 3, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Inhalt', isDense: true)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white), child: const Text('Speichern'))],
    )));
    if (result == true) {
      await widget.apiService.polizeiVorfallAction({'action': 'add_korrespondenz', 'vorfall_id': widget.vorfallId, 'richtung': richtung,
        'datum': datumC.text.trim(), 'betreff': betreffC.text.trim(), 'inhalt': inhaltC.text.trim()});
      _loadData();
    }
  }

  // ==================== ZAHLUNGEN ====================
  Widget _buildZahlungenTab() {
    final totalOffen = _zahlungen.where((z) => z['status'] != 'bezahlt').fold<double>(0, (s, z) => s + (double.tryParse(z['betrag']?.toString() ?? '0') ?? 0));
    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Zahlungen (${_zahlungen.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        if (totalOffen > 0) Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8)),
          child: Text('Offen: ${totalOffen.toStringAsFixed(2)} €', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red.shade700))),
        const SizedBox(width: 8),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 18), label: const Text('Zahlung'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white), onPressed: _addZahlung),
      ]),
      const Divider(height: 24),
      Expanded(child: _zahlungen.isEmpty
        ? Center(child: Text('Keine Zahlungen', style: TextStyle(color: Colors.grey.shade500)))
        : ListView.builder(itemCount: _zahlungen.length, itemBuilder: (_, i) => _buildZahlungItem(_zahlungen[i]))),
    ]));
  }

  Future<void> _addZahlung() async {
    final betragC = TextEditingController(); final faelligC = TextEditingController();
    final beschreibungC = TextEditingController(); final ratenAnzahlC = TextEditingController(); final ratenBetragC = TextEditingController();
    String typ = 'bussgeld'; bool ratenzahlung = false;
    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      title: const Text('Zahlung hinzufügen'),
      content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        DropdownButtonFormField<String>(initialValue: typ, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Typ', isDense: true),
          items: const [DropdownMenuItem(value: 'bussgeld', child: Text('Bußgeld')), DropdownMenuItem(value: 'gebuehr', child: Text('Gebühr')),
            DropdownMenuItem(value: 'ratenzahlung', child: Text('Ratenzahlung')), DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges'))],
          onChanged: (v) { if (v != null) ss(() => typ = v); }),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: TextField(controller: betragC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Betrag (€)', isDense: true), keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: faelligC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Fällig am (TT.MM.JJJJ)', isDense: true))),
        ]),
        const SizedBox(height: 8),
        TextField(controller: beschreibungC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Beschreibung', isDense: true)),
        const SizedBox(height: 8),
        CheckboxListTile(title: const Text('Ratenzahlung beantragt'), value: ratenzahlung, onChanged: (v) => ss(() => ratenzahlung = v!), dense: true, contentPadding: EdgeInsets.zero),
        if (ratenzahlung) Row(children: [
          Expanded(child: TextField(controller: ratenAnzahlC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Anzahl Raten', isDense: true), keyboardType: TextInputType.number)),
          const SizedBox(width: 8),
          Expanded(child: TextField(controller: ratenBetragC, decoration: const InputDecoration(border: OutlineInputBorder(), labelText: 'Rate (€)', isDense: true), keyboardType: TextInputType.number)),
        ]),
      ]))),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white), child: const Text('Speichern'))],
    )));
    if (result == true) {
      await widget.apiService.polizeiVorfallAction({'action': 'add_zahlung', 'vorfall_id': widget.vorfallId, 'typ': typ,
        'betrag': double.tryParse(betragC.text.trim()), 'faellig_am': faelligC.text.trim(), 'beschreibung': beschreibungC.text.trim(),
        'ratenzahlung_beantragt': ratenzahlung, 'raten_anzahl': int.tryParse(ratenAnzahlC.text.trim()), 'raten_betrag': double.tryParse(ratenBetragC.text.trim())});
      _loadData();
    }
  }

  // ==================== HELPERS ====================
  Widget _detailRow(String label, String value) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
    SizedBox(width: 130, child: Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600))),
    Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)))]));

  Widget _sectionLabel(String text, IconData icon, MaterialColor color) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
    Icon(icon, size: 18, color: color.shade700), const SizedBox(width: 6), Text(text, style: TextStyle(fontWeight: FontWeight.bold, color: color.shade700))]));

  Widget _buildKorrItem(Map<String, dynamic> k) {
    final isEingang = k['richtung'] == 'eingang';
    final datum = (k['datum'] ?? '').toString();
    final fDatum = datum.contains('-') ? datum.split('-').reversed.join('.') : datum;
    return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
      leading: Icon(isEingang ? Icons.inbox : Icons.outbox, color: isEingang ? Colors.green : Colors.orange),
      title: Text(k['betreff'] ?? 'Ohne Betreff', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text('${fDatum.isNotEmpty ? fDatum : '-'}\n${k['inhalt'] ?? ''}', style: const TextStyle(fontSize: 12)), isThreeLine: true, dense: true,
      trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
        await widget.apiService.polizeiVorfallAction({'action': 'delete_korrespondenz', 'vorfall_id': widget.vorfallId, 'korrespondenz_id': k['id']});
        _loadData();
      }),
    ));
  }

  Widget _buildZahlungItem(Map<String, dynamic> z) {
    final betrag = double.tryParse(z['betrag']?.toString() ?? '0') ?? 0;
    final status = z['status'] ?? 'offen';
    final faellig = (z['faellig_am'] ?? '').toString();
    final fFaellig = faellig.contains('-') ? faellig.split('-').reversed.join('.') : faellig;
    final isRaten = z['ratenzahlung_beantragt'] == 1 || z['ratenzahlung_beantragt'] == true;
    Color statusColor = Colors.orange;
    if (status == 'bezahlt') statusColor = Colors.green;
    if (status == 'abgelehnt') statusColor = Colors.red;
    if (status == 'genehmigt') statusColor = Colors.blue;

    return Card(margin: const EdgeInsets.only(bottom: 6), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.payment, color: statusColor, size: 20), const SizedBox(width: 8),
        Text('${betrag.toStringAsFixed(2)} €', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: statusColor)), const SizedBox(width: 8),
        Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
          child: Text(_statusLabel(status), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: statusColor))),
        const Spacer(),
        if (fFaellig.isNotEmpty) Text('Fällig: $fFaellig', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        const SizedBox(width: 8),
        IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () async {
          await widget.apiService.polizeiVorfallAction({'action': 'delete_zahlung', 'vorfall_id': widget.vorfallId, 'zahlung_id': z['id']});
          _loadData();
        }),
      ]),
      if (z['beschreibung'] != null && z['beschreibung'].toString().isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(z['beschreibung'], style: const TextStyle(fontSize: 12))),
      if (isRaten) Padding(padding: const EdgeInsets.only(top: 6), child: Container(
        padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6)),
        child: Row(children: [Icon(Icons.calendar_month, size: 16, color: Colors.blue.shade700), const SizedBox(width: 6),
          Text('Ratenzahlung: ${z['raten_anzahl'] ?? '?'} Raten à ${double.tryParse(z['raten_betrag']?.toString() ?? '0')?.toStringAsFixed(2) ?? '?'} €',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700))]))),
    ])));
  }

  String _statusLabel(String? s) => switch(s) { 'offen' => 'Offen', 'in_bearbeitung' => 'In Bearbeitung', 'eingestellt' => 'Eingestellt', 'abgeschlossen' => 'Abgeschlossen',
    'beantragt' => 'Beantragt', 'genehmigt' => 'Genehmigt', 'bezahlt' => 'Bezahlt', 'abgelehnt' => 'Abgelehnt', _ => s ?? '-' };

  String _formatDate(String? d) { if (d == null) return '-'; try { final dt = DateTime.parse(d); return '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year}'; } catch (_) { return d; } }
}
