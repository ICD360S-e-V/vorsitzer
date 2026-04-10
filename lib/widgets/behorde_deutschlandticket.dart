import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';
import '../utils/file_picker_helper.dart';

class BehordeDeutschlandticketContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeDeutschlandticketContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeDeutschlandticketContent> createState() => _BehordeDeutschlandticketContentState();
}

class _BehordeDeutschlandticketContentState extends State<BehordeDeutschlandticketContent> with SingleTickerProviderStateMixin {
  static const type = 'deutschlandticket';

  late TabController _tabController;

  // Ticket-Daten controllers
  late TextEditingController anbieterController;
  late TextEditingController kundennummerController;
  late TextEditingController aboStartController;
  late TextEditingController aboEndeController;
  late TextEditingController sepaIbanController;
  late TextEditingController sepaBicController;
  late TextEditingController sepaKontoinhaberController;
  late TextEditingController sepaMandatsreferenzController;
  late TextEditingController sozialPreisController;
  late TextEditingController jobticketZuschussController;
  late TextEditingController jobticketArbeitgeberController;
  late TextEditingController notizenController;
  bool _controllersInitialized = false;

  // Rechnungen & Korrespondenz documents
  List<Map<String, dynamic>> _rechnungDoks = [];
  List<Map<String, dynamic>> _korrespondenzDoks = [];
  bool _rechnungDoksLoading = false;
  bool _korrespondenzDoksLoading = false;
  bool _uploading = false;

  // Korrespondenz metadata (from deutschlandticket_data.php)
  List<Map<String, dynamic>> _korrespondenz = [];
  bool _korrespondenzLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (_tabController.index == 1 && _rechnungDoks.isEmpty && !_rechnungDoksLoading) {
        _loadRechnungDoks();
      } else if (_tabController.index == 2 && _korrespondenz.isEmpty && !_korrespondenzLoading) {
        _loadKorrespondenz();
        _loadKorrespondenzDoks();
      }
    });
  }

  void _initControllers(Map<String, dynamic> data) {
    anbieterController = TextEditingController(text: data['anbieter']?.toString() ?? '');
    kundennummerController = TextEditingController(text: data['kundennummer']?.toString() ?? '');
    aboStartController = TextEditingController(text: data['abo_start']?.toString() ?? '');
    aboEndeController = TextEditingController(text: data['abo_ende']?.toString() ?? '');
    sepaIbanController = TextEditingController(text: data['sepa_iban']?.toString() ?? '');
    sepaBicController = TextEditingController(text: data['sepa_bic']?.toString() ?? '');
    sepaKontoinhaberController = TextEditingController(text: data['sepa_kontoinhaber']?.toString() ?? '');
    sepaMandatsreferenzController = TextEditingController(text: data['sepa_mandatsreferenz']?.toString() ?? '');
    sozialPreisController = TextEditingController(text: data['sozial_preis']?.toString() ?? '');
    jobticketZuschussController = TextEditingController(text: data['jobticket_zuschuss']?.toString() ?? '');
    jobticketArbeitgeberController = TextEditingController(text: data['jobticket_arbeitgeber']?.toString() ?? '');
    notizenController = TextEditingController(text: data['notizen']?.toString() ?? '');
    _controllersInitialized = true;
  }

  void _updateControllers(Map<String, dynamic> data) {
    _setIfDifferent(anbieterController, data['anbieter']?.toString() ?? '');
    _setIfDifferent(kundennummerController, data['kundennummer']?.toString() ?? '');
    _setIfDifferent(aboStartController, data['abo_start']?.toString() ?? '');
    _setIfDifferent(aboEndeController, data['abo_ende']?.toString() ?? '');
    _setIfDifferent(sepaIbanController, data['sepa_iban']?.toString() ?? '');
    _setIfDifferent(sepaBicController, data['sepa_bic']?.toString() ?? '');
    _setIfDifferent(sepaKontoinhaberController, data['sepa_kontoinhaber']?.toString() ?? '');
    _setIfDifferent(sepaMandatsreferenzController, data['sepa_mandatsreferenz']?.toString() ?? '');
    _setIfDifferent(sozialPreisController, data['sozial_preis']?.toString() ?? '');
    _setIfDifferent(jobticketZuschussController, data['jobticket_zuschuss']?.toString() ?? '');
    _setIfDifferent(jobticketArbeitgeberController, data['jobticket_arbeitgeber']?.toString() ?? '');
    _setIfDifferent(notizenController, data['notizen']?.toString() ?? '');
  }

  void _setIfDifferent(TextEditingController controller, String value) {
    if (controller.text != value) controller.text = value;
  }

  @override
  void dispose() {
    _tabController.dispose();
    if (_controllersInitialized) {
      anbieterController.dispose();
      kundennummerController.dispose();
      aboStartController.dispose();
      aboEndeController.dispose();
      sepaIbanController.dispose();
      sepaBicController.dispose();
      sepaKontoinhaberController.dispose();
      sepaMandatsreferenzController.dispose();
      sozialPreisController.dispose();
      jobticketZuschussController.dispose();
      jobticketArbeitgeberController.dispose();
      notizenController.dispose();
    }
    super.dispose();
  }

  // ==================== RECHNUNGEN DOKUMENTE ====================

  Future<void> _loadRechnungDoks() async {
    setState(() => _rechnungDoksLoading = true);
    try {
      final result = await widget.apiService.listDeutschlandticketDokumente(widget.userId, kategorie: 'rechnung');
      if (mounted && result['success'] == true) {
        _rechnungDoks = List<Map<String, dynamic>>.from(result['dokumente'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _rechnungDoksLoading = false);
  }

  Future<void> _uploadRechnungDoks() async {
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      allowMultiple: true,
      dialogTitle: 'Rechnungen hochladen (max 20)',
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.where((f) => f.path != null).take(20).map((f) => f.path!).toList();
    if (paths.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final uploadResult = await widget.apiService.uploadDeutschlandticketDokumente(widget.userId, paths, 'rechnung');
      if (mounted) {
        final count = (uploadResult['uploaded'] as List?)?.length ?? 0;
        final errors = (uploadResult['errors'] as List?)?.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('$count Rechnung(en) hochgeladen${errors > 0 ? ', $errors Fehler' : ''}'),
          backgroundColor: errors > 0 ? Colors.orange : Colors.green,
        ));
        _loadRechnungDoks();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _uploading = false);
  }

  // ==================== KORRESPONDENZ ====================

  Future<void> _loadKorrespondenz() async {
    setState(() => _korrespondenzLoading = true);
    try {
      final result = await widget.apiService.deutschlandticketAction({
        'action': 'list_korrespondenz', 'user_id': widget.userId,
      });
      if (mounted && result['success'] == true) {
        _korrespondenz = List<Map<String, dynamic>>.from(result['korrespondenz'] ?? []);
      }
    } catch (_) {}
    if (mounted) setState(() => _korrespondenzLoading = false);
  }

  Future<void> _loadKorrespondenzDoks() async {
    setState(() => _korrespondenzDoksLoading = true);
    try {
      final resultEin = await widget.apiService.listDeutschlandticketDokumente(widget.userId, kategorie: 'korrespondenz_eingang');
      final resultAus = await widget.apiService.listDeutschlandticketDokumente(widget.userId, kategorie: 'korrespondenz_ausgang');
      if (mounted) {
        _korrespondenzDoks = [
          ...List<Map<String, dynamic>>.from(resultEin['dokumente'] ?? []),
          ...List<Map<String, dynamic>>.from(resultAus['dokumente'] ?? []),
        ];
      }
    } catch (_) {}
    if (mounted) setState(() => _korrespondenzDoksLoading = false);
  }

  Future<void> _addKorrespondenz() async {
    final betreffC = TextEditingController();
    final inhaltC = TextEditingController();
    final datumC = TextEditingController();
    String richtung = 'eingang';

    final result = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, ss) => AlertDialog(
      title: const Text('Korrespondenz hinzuf\u00FCgen'),
      content: SizedBox(width: 420, child: Column(mainAxisSize: MainAxisSize.min, children: [
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
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white), child: const Text('Speichern')),
      ],
    )));

    if (result == true) {
      final datumParts = datumC.text.trim().split('.');
      String? datumDb;
      if (datumParts.length == 3) datumDb = '${datumParts[2]}-${datumParts[1]}-${datumParts[0]}';

      await widget.apiService.deutschlandticketAction({
        'action': 'add_korrespondenz', 'user_id': widget.userId,
        'richtung': richtung, 'datum': datumDb,
        'betreff': betreffC.text.trim(), 'inhalt': inhaltC.text.trim(),
      });
      _loadKorrespondenz();
    }
  }

  Future<void> _uploadKorrespondenzDoks(String richtung) async {
    final kategorie = richtung == 'eingang' ? 'korrespondenz_eingang' : 'korrespondenz_ausgang';
    final result = await FilePickerHelper.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx'],
      allowMultiple: true,
      dialogTitle: 'Korrespondenz hochladen (max 20)',
    );
    if (result == null || result.files.isEmpty) return;
    final paths = result.files.where((f) => f.path != null).take(20).map((f) => f.path!).toList();
    if (paths.isEmpty) return;

    setState(() => _uploading = true);
    try {
      final uploadResult = await widget.apiService.uploadDeutschlandticketDokumente(widget.userId, paths, kategorie);
      if (mounted) {
        final count = (uploadResult['uploaded'] as List?)?.length ?? 0;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$count Dokument(e) hochgeladen'), backgroundColor: Colors.green));
        _loadKorrespondenzDoks();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _uploading = false);
  }

  Future<void> _deleteKorrespondenz(int id) async {
    await widget.apiService.deutschlandticketAction({'action': 'delete_korrespondenz', 'user_id': widget.userId, 'id': id});
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gel\u00F6scht'), backgroundColor: Colors.green)); _loadKorrespondenz(); }
  }

  // ==================== SHARED: VIEW & DELETE DOC ====================

  Future<void> _viewDoc(Map<String, dynamic> doc) async {
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    final response = await widget.apiService.downloadDeutschlandticketDokument(docId);
    if (response == null || !mounted) return;
    try {
      final tempDir = await getTemporaryDirectory();
      final filePath = '${tempDir.path}/${doc['original_name']}';
      await File(filePath).writeAsBytes(response.bodyBytes);
      if (mounted) await FileViewerDialog.show(context, filePath, doc['original_name']);
    } catch (_) {}
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc, {bool isRechnung = true}) async {
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dokument l\u00F6schen?'),
      content: Text('"${doc['original_name']}" wirklich l\u00F6schen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('L\u00F6schen')),
      ],
    ));
    if (confirmed != true) return;
    final docId = doc['id'] is int ? doc['id'] : int.parse(doc['id'].toString());
    await widget.apiService.deleteDeutschlandticketDokument(widget.userId, docId);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gel\u00F6scht'), backgroundColor: Colors.green));
      if (isRechnung) { _loadRechnungDoks(); } else { _loadKorrespondenzDoks(); }
    }
  }

  // ==================== UI HELPERS ====================

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Padding(padding: const EdgeInsets.only(top: 8, bottom: 4), child: Row(children: [
      Icon(icon, size: 20, color: color), const SizedBox(width: 8),
      Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
      Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
    ]));
  }

  Widget _textField(String label, TextEditingController controller, {String hint = '', IconData icon = Icons.edit, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: controller, maxLines: maxLines,
        decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20), isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        style: const TextStyle(fontSize: 14)),
    ]);
  }

  Widget _dtInfoChip(String label, IconData icon) {
    return Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: Colors.white70), const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w500)),
      ]));
  }

  String _formatDate(String? d) {
    if (d == null || d.isEmpty) return '-';
    if (d.contains('-')) {
      final parts = d.split('-');
      if (parts.length == 3) return '${parts[2]}.${parts[1]}.${parts[0]}';
    }
    return d;
  }

  String _formatDateTime(String? d) {
    if (d == null || d.isEmpty) return '-';
    try { final dt = DateTime.parse(d); return '${dt.day.toString().padLeft(2,'0')}.${dt.month.toString().padLeft(2,'0')}.${dt.year} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}'; } catch (_) { return d; }
  }

  Widget _buildDocItem(Map<String, dynamic> doc, {bool isRechnung = true}) {
    final name = doc['original_name'] ?? 'Unbekannt';
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    IconData icon = Icons.insert_drive_file;
    Color color = Colors.grey;
    if (ext == 'pdf') { icon = Icons.picture_as_pdf; color = Colors.red; }
    else if (['jpg','jpeg','png','tiff','bmp'].contains(ext)) { icon = Icons.image; color = Colors.blue; }
    else if (['doc','docx'].contains(ext)) { icon = Icons.description; color = Colors.indigo; }

    return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
      leading: Icon(icon, color: color), title: Text(name, style: const TextStyle(fontSize: 13)),
      subtitle: Text(_formatDateTime(doc['created_at']), style: const TextStyle(fontSize: 11)),
      dense: true,
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(icon: Icon(Icons.visibility, size: 18, color: Colors.blue.shade600), tooltip: 'Anzeigen', onPressed: () => _viewDoc(doc)),
        IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'L\u00F6schen', onPressed: () => _deleteDoc(doc, isRechnung: isRechnung)),
      ]),
    ));
  }

  // ==================== BUILD ====================

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Container(color: Colors.red.shade50,
        child: TabBar(controller: _tabController, labelColor: Colors.red.shade700, unselectedLabelColor: Colors.grey.shade600, indicatorColor: Colors.red.shade700,
          tabs: [
            Tab(icon: Icon(Icons.train, size: 18, color: Colors.red.shade700), text: 'Ticket-Daten'),
            Tab(icon: Icon(Icons.receipt_long, size: 18, color: Colors.red.shade700), text: 'Rechnungen (${_rechnungDoks.length})'),
            Tab(icon: Icon(Icons.mail, size: 18, color: Colors.red.shade700), text: 'Korrespondenz (${_korrespondenz.length + _korrespondenzDoks.length})'),
          ],
        ),
      ),
      Expanded(child: TabBarView(controller: _tabController, children: [
        _buildTicketDatenTab(),
        _buildRechnungenTab(),
        _buildKorrespondenzTab(),
      ])),
    ]);
  }

  // ==================== TAB 1: TICKET-DATEN ====================

  Widget _buildTicketDatenTab() {
    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type)) widget.loadData(type);
    if (widget.isLoading(type)) return const Center(child: CircularProgressIndicator());
    if (!_controllersInitialized) { _initControllers(data); } else { _updateControllers(data); }

    String aboStatus = data['abo_status']?.toString() ?? '';
    String ticketTyp = data['ticket_typ']?.toString() ?? 'normal';

    return StatefulBuilder(builder: (context, setLocalState) {
      String preisLabel;
      switch (ticketTyp) {
        case 'ermaessigt': preisLabel = '43,00'; break;
        case 'sozial': final sp = sozialPreisController.text.trim(); preisLabel = sp.isNotEmpty ? sp : '???'; break;
        case 'jobticket': final jz = jobticketZuschussController.text.trim(); preisLabel = jz.isNotEmpty ? jz : '~47,25'; break;
        default: preisLabel = '63,00';
      }
      return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Info Card
        Container(padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: LinearGradient(colors: [Colors.red.shade600, Colors.red.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.train, color: Colors.white, size: 28), const SizedBox(width: 12),
              const Expanded(child: Text('Deutschlandticket', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
                child: Text('$preisLabel \u20AC/Monat', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white))),
            ]),
            const SizedBox(height: 12),
            const Text('Monatlich k\u00FCndbares Abo f\u00FCr den gesamten \u00D6PNV & Regionalverkehr in Deutschland.',
              style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 4, children: [
              _dtInfoChip('Normal: 63 \u20AC', Icons.euro), _dtInfoChip('Erm\u00E4\u00DFigt: 43 \u20AC', Icons.school),
              _dtInfoChip('Sozial: regional', Icons.volunteer_activism), _dtInfoChip('Jobticket: ~47 \u20AC', Icons.work),
            ]),
          ]),
        ),

        const SizedBox(height: 20),
        _sectionHeader(Icons.style, 'Ticket-Typ', Colors.deepPurple),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ChoiceChip(avatar: const Icon(Icons.euro, size: 16), label: const Text('Normal (63 \u20AC)'), selected: ticketTyp == 'normal', selectedColor: Colors.blue.shade100, onSelected: (sel) => setLocalState(() => ticketTyp = sel ? 'normal' : 'normal')),
          ChoiceChip(avatar: const Icon(Icons.school, size: 16), label: const Text('Erm\u00E4\u00DFigt (43 \u20AC)'), selected: ticketTyp == 'ermaessigt', selectedColor: Colors.green.shade100, onSelected: (sel) => setLocalState(() => ticketTyp = sel ? 'ermaessigt' : 'normal')),
          ChoiceChip(avatar: const Icon(Icons.volunteer_activism, size: 16), label: const Text('Sozialticket'), selected: ticketTyp == 'sozial', selectedColor: Colors.orange.shade100, onSelected: (sel) => setLocalState(() => ticketTyp = sel ? 'sozial' : 'normal')),
          ChoiceChip(avatar: const Icon(Icons.work, size: 16), label: const Text('Jobticket'), selected: ticketTyp == 'jobticket', selectedColor: Colors.teal.shade100, onSelected: (sel) => setLocalState(() => ticketTyp = sel ? 'jobticket' : 'normal')),
        ]),

        if (ticketTyp == 'sozial') ...[
          const SizedBox(height: 8),
          _textField('Tats\u00E4chlicher Preis (\u20AC/Monat)', sozialPreisController, hint: 'z.B. 27,50', icon: Icons.euro),
        ],
        if (ticketTyp == 'jobticket') ...[
          const SizedBox(height: 8),
          _textField('Arbeitgeber', jobticketArbeitgeberController, hint: 'Name des Arbeitgebers', icon: Icons.business),
          const SizedBox(height: 8),
          _textField('Eigenanteil (\u20AC/Monat)', jobticketZuschussController, hint: 'z.B. 47,25', icon: Icons.euro),
        ],

        const SizedBox(height: 20),
        _sectionHeader(Icons.check_circle_outline, 'Abo-Status', Colors.green.shade700),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Aktiv'), selected: aboStatus == 'aktiv', selectedColor: Colors.green.shade100, onSelected: (sel) => setLocalState(() => aboStatus = sel ? 'aktiv' : '')),
          ChoiceChip(label: const Text('Inaktiv'), selected: aboStatus == 'inaktiv', selectedColor: Colors.grey.shade200, onSelected: (sel) => setLocalState(() => aboStatus = sel ? 'inaktiv' : '')),
          ChoiceChip(label: const Text('Gek\u00FCndigt'), selected: aboStatus == 'gekuendigt', selectedColor: Colors.red.shade100, onSelected: (sel) => setLocalState(() => aboStatus = sel ? 'gekuendigt' : '')),
        ]),

        const SizedBox(height: 16),
        _sectionHeader(Icons.business, 'Anbieter & Abo', Colors.blue.shade700),
        const SizedBox(height: 8),
        _textField('Anbieter', anbieterController, hint: 'z.B. Deutsche Bahn, BVG, MVG...', icon: Icons.storefront),
        const SizedBox(height: 8),
        _textField('Kundennummer', kundennummerController, hint: 'Kundennummer beim Anbieter', icon: Icons.confirmation_number),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _textField('Abo-Beginn', aboStartController, hint: '01.03.2026', icon: Icons.calendar_today)),
          const SizedBox(width: 12),
          Expanded(child: _textField('Abo-Ende', aboEndeController, hint: '31.05.2026', icon: Icons.event_busy)),
        ]),

        const SizedBox(height: 20),
        _sectionHeader(Icons.account_balance, 'SEPA-Lastschrift', Colors.teal),
        const SizedBox(height: 8),
        _textField('Kontoinhaber', sepaKontoinhaberController, hint: 'Name des Kontoinhabers', icon: Icons.person),
        const SizedBox(height: 8),
        _textField('IBAN', sepaIbanController, hint: 'DE89 3704 0044 0532 0130 00', icon: Icons.credit_card),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: _textField('BIC', sepaBicController, hint: 'COBADEFFXXX', icon: Icons.numbers)),
          const SizedBox(width: 12),
          Expanded(child: _textField('Mandatsreferenz', sepaMandatsreferenzController, hint: 'SEPA-Mandatsreferenz', icon: Icons.receipt_long)),
        ]),

        const SizedBox(height: 20),
        _sectionHeader(Icons.notes, 'Notizen', Colors.grey.shade700),
        const SizedBox(height: 8),
        _textField('Notizen', notizenController, hint: 'Weitere Informationen...', icon: Icons.notes, maxLines: 3),

        const SizedBox(height: 24),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          onPressed: widget.isSaving(type) ? null : () {
            widget.saveData(type, {
              'ticket_typ': ticketTyp, 'anbieter': anbieterController.text.trim(),
              'kundennummer': kundennummerController.text.trim(), 'abo_status': aboStatus,
              'abo_start': aboStartController.text.trim(), 'abo_ende': aboEndeController.text.trim(),
              'sozial_preis': sozialPreisController.text.trim(), 'jobticket_arbeitgeber': jobticketArbeitgeberController.text.trim(),
              'jobticket_zuschuss': jobticketZuschussController.text.trim(), 'sepa_kontoinhaber': sepaKontoinhaberController.text.trim(),
              'sepa_iban': sepaIbanController.text.trim(), 'sepa_bic': sepaBicController.text.trim(),
              'sepa_mandatsreferenz': sepaMandatsreferenzController.text.trim(), 'notizen': notizenController.text.trim(),
            });
          },
          icon: widget.isSaving(type) ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 18),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
        )),
      ]));
    });
  }

  // ==================== TAB 2: RECHNUNGEN ====================

  Widget _buildRechnungenTab() {
    if (_rechnungDoksLoading) return const Center(child: CircularProgressIndicator());

    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.receipt_long, color: Colors.red.shade700, size: 22), const SizedBox(width: 8),
        Expanded(child: Text('Rechnungen (${_rechnungDoks.length})', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        ElevatedButton.icon(
          icon: _uploading ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.upload_file, size: 18),
          label: Text(_uploading ? 'Wird hochgeladen...' : 'Hochladen'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700, foregroundColor: Colors.white),
          onPressed: _uploading ? null : _uploadRechnungDoks,
        ),
      ]),
      const Divider(height: 24),
      Expanded(child: _rechnungDoks.isEmpty
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8),
            Text('Keine Rechnungen hochgeladen', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('Laden Sie Ihre Deutschlandticket-Rechnungen hoch (PDF, JPG, PNG)', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]))
        : ListView.builder(itemCount: _rechnungDoks.length, itemBuilder: (_, i) => _buildDocItem(_rechnungDoks[i], isRechnung: true)),
      ),
    ]));
  }

  // ==================== TAB 3: KORRESPONDENZ ====================

  Widget _buildKorrespondenzTab() {
    if (_korrespondenzLoading || _korrespondenzDoksLoading) return const Center(child: CircularProgressIndicator());

    final eingang = _korrespondenz.where((k) => k['richtung'] == 'eingang').toList();
    final ausgang = _korrespondenz.where((k) => k['richtung'] == 'ausgang').toList();
    final eingangDoks = _korrespondenzDoks.where((d) => d['kategorie'] == 'korrespondenz_eingang').toList();
    final ausgangDoks = _korrespondenzDoks.where((d) => d['kategorie'] == 'korrespondenz_ausgang').toList();

    return Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(Icons.mail, color: Colors.red.shade700, size: 22), const SizedBox(width: 8),
        const Expanded(child: Text('Korrespondenz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
        PopupMenuButton<String>(
          icon: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: Colors.red.shade700, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.add, size: 18, color: Colors.white), const SizedBox(width: 4),
              const Text('Hinzuf\u00FCgen', style: TextStyle(color: Colors.white, fontSize: 13)),
            ])),
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'text', child: ListTile(leading: Icon(Icons.edit, size: 20), title: Text('Korrespondenz (Text)'), dense: true)),
            const PopupMenuItem(value: 'upload_eingang', child: ListTile(leading: Icon(Icons.inbox, size: 20, color: Colors.green), title: Text('Eingang hochladen'), dense: true)),
            const PopupMenuItem(value: 'upload_ausgang', child: ListTile(leading: Icon(Icons.outbox, size: 20, color: Colors.orange), title: Text('Ausgang hochladen'), dense: true)),
          ],
          onSelected: (v) {
            if (v == 'text') _addKorrespondenz();
            else if (v == 'upload_eingang') _uploadKorrespondenzDoks('eingang');
            else if (v == 'upload_ausgang') _uploadKorrespondenzDoks('ausgang');
          },
        ),
      ]),
      const Divider(height: 24),
      Expanded(child: (eingang.isEmpty && ausgang.isEmpty && eingangDoks.isEmpty && ausgangDoks.isEmpty)
        ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.mail_outline, size: 48, color: Colors.grey.shade300), const SizedBox(height: 8),
            Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade500)),
            const SizedBox(height: 4),
            Text('F\u00FCgen Sie Korrespondenz hinzu oder laden Sie Dokumente hoch', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]))
        : ListView(children: [
            // EINGANG
            if (eingang.isNotEmpty || eingangDoks.isNotEmpty) ...[
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                Icon(Icons.inbox, size: 18, color: Colors.green.shade700), const SizedBox(width: 6),
                Text('Eingang', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade700)),
              ])),
              ...eingang.map(_buildKorrespondenzTextItem),
              ...eingangDoks.map((d) => _buildDocItem(d, isRechnung: false)),
            ],
            // AUSGANG
            if (ausgang.isNotEmpty || ausgangDoks.isNotEmpty) ...[
              const SizedBox(height: 12),
              Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(children: [
                Icon(Icons.outbox, size: 18, color: Colors.orange.shade700), const SizedBox(width: 6),
                Text('Ausgang', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
              ])),
              ...ausgang.map(_buildKorrespondenzTextItem),
              ...ausgangDoks.map((d) => _buildDocItem(d, isRechnung: false)),
            ],
          ])),
    ]));
  }

  Widget _buildKorrespondenzTextItem(Map<String, dynamic> k) {
    final id = k['id'] is int ? k['id'] as int : int.parse(k['id'].toString());
    final isEingang = k['richtung'] == 'eingang';
    final datum = _formatDate(k['datum']?.toString());
    final betreff = k['betreff'] ?? 'Ohne Betreff';
    final inhalt = k['inhalt'] ?? '';

    return Card(margin: const EdgeInsets.only(bottom: 6), child: ListTile(
      leading: Icon(isEingang ? Icons.inbox : Icons.outbox, color: isEingang ? Colors.green : Colors.orange),
      title: Text(betreff, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(datum, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        if (inhalt.isNotEmpty) Text(inhalt, style: const TextStyle(fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
      ]),
      isThreeLine: inhalt.isNotEmpty, dense: true,
      trailing: IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'L\u00F6schen', onPressed: () => _deleteKorrespondenz(id)),
    ));
  }
}
