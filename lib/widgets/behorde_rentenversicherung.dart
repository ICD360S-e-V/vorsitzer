import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BehordeRentenversicherungContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final Widget Function({
    required String behoerdeType,
    required List<Map<String, dynamic>> antraege,
    required List<DropdownMenuItem<String>> artItems,
    required List<DropdownMenuItem<String>> statusItems,
    required void Function(List<Map<String, dynamic>>) onChanged,
    required BuildContext context,
  }) antraegeBuilder;

  const BehordeRentenversicherungContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    required this.antraegeBuilder,
  });

  @override
  State<BehordeRentenversicherungContent> createState() => _State();
}

class _State extends State<BehordeRentenversicherungContent> with TickerProviderStateMixin {
  static const type = 'rentenversicherung';

  late final TabController _tabCtrl;
  bool _initialized = false;

  // Tab 1 — Zuständige Behörde
  late final TextEditingController _dienststelleC;
  late final TextEditingController _traegerC;

  // Tab 3 — Stammdaten
  late final TextEditingController _rvnrC;
  bool _rvnrEditing = false; // off by default — pencil button toggles it on
  late final TextEditingController _entgeltpunkteC;
  late final TextEditingController _zugangsfaktorC;
  late final TextEditingController _notizenC;
  String _rentenart = '';
  bool _hatKinder = true;

  // Antrage data
  List<Map<String, dynamic>> _antraege = [];

  static const Map<int, Map<String, double>> _rentenwertTabelle = {
    2020: {'west': 34.19, 'ost': 33.23},
    2021: {'west': 34.19, 'ost': 33.47},
    2022: {'west': 36.02, 'ost': 35.52},
    2023: {'west': 37.60, 'ost': 37.60},
    2024: {'west': 39.32, 'ost': 39.32},
    2025: {'west': 40.79, 'ost': 40.79},
    2026: {'west': 41.83, 'ost': 41.83},
  };

  static const Map<String, double> _rentenartFaktoren = {
    'altersrente': 1.0,
    'volle_erwerbsminderung': 1.0,
    'teilweise_erwerbsminderung': 0.5,
    'grosse_witwenrente': 0.55,
    'kleine_witwenrente': 0.25,
    'halbwaisenrente': 0.10,
    'vollwaisenrente': 0.20,
  };

  static const Map<String, String> _rentenartLabels = {
    '': 'Nicht ausgewaehlt',
    'altersrente': 'Altersrente (Regelaltersrente)',
    'volle_erwerbsminderung': 'Volle Erwerbsminderungsrente',
    'teilweise_erwerbsminderung': 'Teilweise Erwerbsminderungsrente',
    'grosse_witwenrente': 'Grosse Witwen-/Witwerrente',
    'kleine_witwenrente': 'Kleine Witwen-/Witwerrente',
    'halbwaisenrente': 'Halbwaisenrente',
    'vollwaisenrente': 'Vollwaisenrente',
  };

  static const double _kvBeitragRentner = 7.3;
  static const double _kvZusatzbeitrag = 2.5;
  static const double _pvBeitragRentner = 1.8;
  static const double _pvBeitragKinderlos = 2.3;

  static const List<({String key, String label})> _antragArten = [
    (key: 'altersrente', label: 'Altersrentenantrag'),
    (key: 'emr_voll', label: 'Erwerbsminderungsrente (voll)'),
    (key: 'emr_teil', label: 'Erwerbsminderungsrente (teilweise)'),
    (key: 'witwen_gross', label: 'Grosse Witwen-/Witwerrente'),
    (key: 'witwen_klein', label: 'Kleine Witwen-/Witwerrente'),
    (key: 'halbwaisen', label: 'Halbwaisenrente'),
    (key: 'vollwaisen', label: 'Vollwaisenrente'),
    (key: 'kontenklaerung', label: 'Kontenklaerung'),
    (key: 'reha', label: 'Reha-Antrag'),
    (key: 'ueberpruefung', label: 'Ueberpruefungsantrag (§44 SGB X)'),
    (key: 'widerspruch', label: 'Widerspruch'),
    (key: 'klage', label: 'Klage'),
  ];

  static const List<({String key, String label})> _antragStati = [
    (key: 'eingereicht', label: 'Eingereicht'),
    (key: 'in_bearbeitung', label: 'In Bearbeitung'),
    (key: 'bewilligt', label: 'Bewilligt'),
    (key: 'teilweise_bewilligt', label: 'Teilweise bewilligt'),
    (key: 'abgelehnt', label: 'Abgelehnt'),
    (key: 'widerspruch', label: 'Widerspruch'),
    (key: 'klage', label: 'Klage'),
    (key: 'zurueckgezogen', label: 'Zurueckgezogen'),
  ];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _dienststelleC = TextEditingController();
    _traegerC = TextEditingController();
    _rvnrC = TextEditingController();
    _entgeltpunkteC = TextEditingController();
    _zugangsfaktorC = TextEditingController(text: '1,0');
    _notizenC = TextEditingController();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _dienststelleC.dispose();
    _traegerC.dispose();
    _rvnrC.dispose();
    _entgeltpunkteC.dispose();
    _zugangsfaktorC.dispose();
    _notizenC.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> data) {
    if (_initialized) return;
    _dienststelleC.text = data['dienststelle']?.toString() ?? '';
    _traegerC.text = data['traeger']?.toString() ?? '';
    _rvnrC.text = (data['rentennummer'] ?? data['sozialversicherungsnummer'] ?? data['versicherungsnummer'] ?? '').toString();
    _entgeltpunkteC.text = data['entgeltpunkte']?.toString() ?? '';
    _zugangsfaktorC.text = data['zugangsfaktor']?.toString() ?? '1,0';
    _notizenC.text = data['notizen']?.toString() ?? '';
    _rentenart = data['rentenart']?.toString() ?? '';
    _hatKinder = (data['hat_kinder'] ?? 'ja') == 'ja';
    final rawAnt = data['antraege'];
    if (rawAnt is List) {
      _antraege = rawAnt.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _initialized = true;
  }

  Map<String, dynamic> _collect() => {
        'dienststelle': _dienststelleC.text.trim(),
        'traeger': _traegerC.text.trim(),
        'rentennummer': _rvnrC.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ''),
        'rentenart': _rentenart,
        'entgeltpunkte': _entgeltpunkteC.text.trim(),
        'zugangsfaktor': _zugangsfaktorC.text.trim(),
        'hat_kinder': _hatKinder ? 'ja' : 'nein',
        'notizen': _notizenC.text.trim(),
        'antraege': _antraege,
      };

  void _save() => widget.saveData(type, _collect());

  // RVNR validator: 12 chars, format AA TTMMJJ B SSS (Bereich + Geburtsdatum + Initiale + Seriennr)
  String? _validateRvnr() {
    final clean = _rvnrC.text.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');
    if (clean.isEmpty) return null;
    final m = RegExp(r'^(\d{2})(\d{2})(\d{2})(\d{2})([A-Z])(\d{3})$').firstMatch(clean);
    if (m == null) return 'Ungueltiges Format. Erwartet: AA TTMMJJ B SSS (12 Zeichen)';
    final day = int.parse(m.group(2)!);
    final month = int.parse(m.group(3)!);
    if (day < 1 || day > 31) return 'Geburtstag (Stellen 3-4) ungueltig';
    if (month < 1 || month > 12) return 'Geburtsmonat (Stellen 5-6) ungueltig';
    return null;
  }

  String _formatEur(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    return '${parts[0]},${parts[1]} EUR';
  }

  double _getRentenwert(int year) {
    final entry = _rentenwertTabelle[year] ?? _rentenwertTabelle.values.last;
    return entry['west']!;
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type)) {
      widget.loadData(type);
    }
    if (widget.isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }
    _hydrate(data);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ─── HEADER ───
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Icon(Icons.elderly, color: Colors.deepPurple.shade700, size: 24),
              const SizedBox(width: 8),
              const Text('Rente', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
              ElevatedButton.icon(
                onPressed: widget.isSaving(type) ? null : _save,
                icon: widget.isSaving(type)
                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save, size: 16),
                label: const Text('Speichern', style: TextStyle(fontSize: 12)),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),

        // ─── TABBAR ───
        TabBar(
          controller: _tabCtrl,
          labelColor: Colors.deepPurple.shade700,
          unselectedLabelColor: Colors.grey.shade600,
          indicatorColor: Colors.deepPurple,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          tabs: const [
            Tab(icon: Icon(Icons.account_balance, size: 18), text: 'Zustaendige Behoerde'),
            Tab(icon: Icon(Icons.assignment, size: 18), text: 'Antraege'),
            Tab(icon: Icon(Icons.badge, size: 18), text: 'Stammdaten'),
          ],
        ),

        // ─── TAB BODIES ───
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: [
              _buildBehoerdeTab(),
              _buildAntraegeTab(),
              _buildStammdatenTab(context),
            ],
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════
  //   TAB 1: Zustaendige Behoerde
  // ═══════════════════════════════════════════════════════
  Widget _buildBehoerdeTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepPurple.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.deepPurple.shade200),
            ),
            child: Row(children: [
              Icon(Icons.info_outline, color: Colors.deepPurple.shade700, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Traeger und Dienststelle der Deutschen Rentenversicherung, die fuer diese Person zustaendig ist.',
                  style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade800),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          Text('Rentenversicherungstraeger', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: _traegerC,
            decoration: InputDecoration(
              hintText: 'z.B. Deutsche Rentenversicherung Bund / Baden-Wuerttemberg',
              prefixIcon: const Icon(Icons.account_balance, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text(
            'Bund, Knappschaft-Bahn-See oder eine der 14 Regionaltraeger.',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
          ),
          const SizedBox(height: 20),

          Text('Dienststelle', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          widget.dienststelleBuilder(type, _dienststelleC),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //   TAB 2: Antraege
  // ═══════════════════════════════════════════════════════
  Widget _buildAntraegeTab() {
    final artItems = _antragArten
        .map((a) => DropdownMenuItem<String>(value: a.key, child: Text(a.label, style: const TextStyle(fontSize: 13))))
        .toList();
    final statusItems = _antragStati
        .map((s) => DropdownMenuItem<String>(value: s.key, child: Text(s.label, style: const TextStyle(fontSize: 13))))
        .toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: widget.antraegeBuilder(
        behoerdeType: type,
        antraege: _antraege,
        artItems: artItems,
        statusItems: statusItems,
        onChanged: (updated) {
          setState(() => _antraege = updated);
          _save();
        },
        context: context,
      ),
    );
  }

  // ═══════════════════════════════════════════════════════
  //   TAB 3: Stammdaten
  // ═══════════════════════════════════════════════════════
  Widget _buildStammdatenTab(BuildContext context) {
    return StatefulBuilder(
      builder: (context, setLocalState) {
        final currentYear = DateTime.now().year;
        final rentenwert = _getRentenwert(currentYear);
        final faktor = _rentenartFaktoren[_rentenart] ?? 1.0;
        final ep = double.tryParse(_entgeltpunkteC.text.trim().replaceAll(',', '.')) ?? 0;
        final zf = double.tryParse(_zugangsfaktorC.text.trim().replaceAll(',', '.')) ?? 1.0;
        final brutto = ep * zf * rentenwert * faktor;
        final kvAbzug = brutto * (_kvBeitragRentner + _kvZusatzbeitrag / 2) / 100;
        final pvSatz = _hatKinder ? _pvBeitragRentner : _pvBeitragKinderlos;
        final pvAbzug = brutto * pvSatz / 100;
        final netto = brutto - kvAbzug - pvAbzug;
        final rvnrError = _validateRvnr();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ─── RENTENNUMMER ───
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.indigo.shade50, Colors.deepPurple.shade50],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.badge, color: Colors.deepPurple.shade700, size: 20),
                      const SizedBox(width: 8),
                      Text('Deutsche Rentennummer (RVNR)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
                    ]),
                    const SizedBox(height: 8),
                    // RVNR field — readonly by default. The pencil toggles
                    // edit mode; the clipboard button copies the current
                    // value to the system clipboard. When the value is
                    // valid we also show the green checkmark inline.
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Expanded(child: TextField(
                        controller: _rvnrC,
                        readOnly: !_rvnrEditing,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: _rvnrEditing ? 'z.B. 15 070649 C 103' : null,
                          prefixIcon: Icon(Icons.badge, size: 20, color: _rvnrEditing ? Colors.deepPurple.shade700 : Colors.grey.shade600),
                          suffixIcon: rvnrError == null && _rvnrC.text.trim().isNotEmpty
                              ? Icon(Icons.check_circle, color: Colors.green.shade600, size: 20)
                              : null,
                          isDense: true,
                          filled: true,
                          fillColor: _rvnrEditing ? Colors.white : Colors.grey.shade100,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          errorText: rvnrError,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          fontFamily: 'monospace',
                          color: _rvnrEditing ? Colors.black : Colors.grey.shade800,
                          fontWeight: _rvnrEditing ? FontWeight.normal : FontWeight.w600,
                        ),
                        onChanged: (_) => setLocalState(() {}),
                      )),
                      const SizedBox(width: 6),
                      // Copy to clipboard.
                      IconButton(
                        tooltip: 'In Zwischenablage kopieren',
                        icon: const Icon(Icons.content_copy, size: 18),
                        color: Colors.deepPurple.shade700,
                        onPressed: _rvnrC.text.trim().isEmpty ? null : () async {
                          await Clipboard.setData(ClipboardData(text: _rvnrC.text.trim()));
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('RVNR kopiert: ${_rvnrC.text.trim()}'),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 2),
                          ));
                        },
                      ),
                      // Edit toggle.
                      IconButton(
                        tooltip: _rvnrEditing ? 'Speichern' : 'Bearbeiten',
                        icon: Icon(_rvnrEditing ? Icons.check : Icons.edit, size: 18),
                        color: _rvnrEditing ? Colors.green.shade700 : Colors.deepPurple.shade700,
                        onPressed: () {
                          setLocalState(() => _rvnrEditing = !_rvnrEditing);
                          setState(() {}); // share with the outer state
                          if (!_rvnrEditing) {
                            // exiting edit mode → persist
                            _save();
                          }
                        },
                      ),
                    ]),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.deepPurple.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Aufbau (12 Zeichen):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                          const SizedBox(height: 4),
                          _formatRow('AA', 'Bereichsnummer des Rentenversicherungstraegers'),
                          _formatRow('TT', 'Geburtstag (01-31)'),
                          _formatRow('MM', 'Geburtsmonat (01-12)'),
                          _formatRow('JJ', 'Geburtsjahr (2-stellig)'),
                          _formatRow('B', 'Anfangsbuchstabe des Geburtsnamens (A-Z)'),
                          _formatRow('SS', 'Seriennummer (00-49 = m / 50-99 = w/d)'),
                          _formatRow('P', 'Pruefziffer'),
                          const SizedBox(height: 8),
                          // Live lookup based on the first two RVNR digits.
                          if (_rvnrC.text.trim().length >= 2) ...[
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Icon(Icons.account_balance, size: 16, color: Colors.green.shade700),
                                const SizedBox(width: 6),
                                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Text('Zuständig laut RVNR-Bereich:',
                                    style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                                  Text(_drvFromBereich(_rvnrC.text.trim().substring(0, 2)),
                                    style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.bold)),
                                ])),
                              ]),
                            ),
                            const SizedBox(height: 8),
                          ],
                          Text('Bereichsnummern (Anlage VKVV — § 2 Abs. 2):',
                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                          const SizedBox(height: 3),
                          Text('Regionalträger (Versicherte vor 2005):', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
                          _bereichRow('02', 'DRV Nord (ehem. LVA Mecklenburg-Vorpommern)'),
                          _bereichRow('03', 'DRV Mitteldeutschland (ehem. Thüringen)'),
                          _bereichRow('04', 'DRV Berlin-Brandenburg'),
                          _bereichRow('08', 'DRV Mitteldeutschland (ehem. Sachsen-Anhalt)'),
                          _bereichRow('09', 'DRV Mitteldeutschland (ehem. Sachsen)'),
                          _bereichRow('10', 'DRV Braunschweig-Hannover (DRV Niedersachsen-Bremen)'),
                          _bereichRow('11', 'DRV Westfalen'),
                          _bereichRow('12', 'DRV Hessen'),
                          _bereichRow('13', 'DRV Rheinland'),
                          _bereichRow('14', 'DRV Oberbayern (DRV Bayern Süd)'),
                          _bereichRow('15', 'DRV Niederbayern-Oberpfalz (DRV Bayern Süd)'),
                          _bereichRow('16', 'DRV Rheinland-Pfalz'),
                          _bereichRow('17', 'DRV Saarland'),
                          _bereichRow('18', 'DRV Ober- und Mittelfranken (DRV Nordbayern)'),
                          _bereichRow('19', 'DRV Nord (ehem. LVA Hamburg)'),
                          _bereichRow('20', 'DRV Unterfranken (DRV Nordbayern)'),
                          _bereichRow('21', 'DRV Schwaben (DRV Bayern Süd)'),
                          _bereichRow('23', 'DRV Baden-Württemberg (ehem. LVA Württemberg)'),
                          _bereichRow('24', 'DRV Baden-Württemberg (ehem. LVA Baden)'),
                          _bereichRow('25', 'DRV Berlin-Brandenburg (ehem. LVA Berlin)'),
                          _bereichRow('26', 'DRV Nord (ehem. LVA Schleswig-Holstein)'),
                          _bereichRow('28', 'DRV Niedersachsen-Bremen (ehem. Oldenburg-Bremen)'),
                          _bereichRow('29', 'DRV Braunschweig-Hannover (ehem. Braunschweig)'),
                          const SizedBox(height: 4),
                          Text('DRV Bund (ehem. BfA — Angestellte / Versicherte nach 2005):', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
                          _bereichRow('42–79', 'DRV Bund — Regional-Bereichsnr. + 40'),
                          _bereichRow('50', 'DRV Bund (Niedersachsen-Bremen, ehem. LVA Hannover)'),
                          _bereichRow('51', 'DRV Bund (Westfalen)'),
                          _bereichRow('52', 'DRV Bund (Hessen)'),
                          _bereichRow('53', 'DRV Bund (Rheinland)'),
                          _bereichRow('54', 'DRV Bund (Oberbayern)'),
                          _bereichRow('60', 'DRV Bund (Unterfranken)'),
                          _bereichRow('61', 'DRV Bund (Schwaben)'),
                          _bereichRow('62', 'DRV Bund (Hamburg)'),
                          _bereichRow('63', 'DRV Bund (ehem. Württemberg) ← häufig bei BW-Versicherten'),
                          _bereichRow('64', 'DRV Bund (ehem. Baden)'),
                          _bereichRow('65', 'DRV Bund (Berlin)'),
                          _bereichRow('66', 'DRV Bund (Schleswig-Holstein)'),
                          _bereichRow('68', 'DRV Bund (Oldenburg-Bremen)'),
                          const SizedBox(height: 4),
                          Text('Knappschaft-Bahn-See & Sondergruppen:', style: TextStyle(fontSize: 9, fontStyle: FontStyle.italic, color: Colors.grey.shade600)),
                          _bereichRow('38/39', 'DRV Knappschaft-Bahn-See (Bergbau / Seeleute)'),
                          _bereichRow('80–82', 'DRV Knappschaft-Bahn-See (Versicherte nach 2005)'),
                          _bereichRow('89', 'DRV Bund (Sonderzuweisung)'),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Text(
                              'Beispiel: 63 070649 C 103 = DRV Bund (ehem. Württemberg), geb. 07.06.1949, Name beginnt mit C, männlich, Prüfziffer 3.',
                              style: TextStyle(fontSize: 11, color: Colors.brown.shade700, fontStyle: FontStyle.italic),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(4)),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(Icons.flag, size: 14, color: Colors.blue.shade700),
                              const SizedBox(width: 6),
                              Expanded(child: Text(
                                'Für ukrainische Versicherte mit Bezug zur Ukraine (Beitragszeiten, Rentenleistungen) ist die Verbindungsstelle Ukraine bei der DRV Bund zuständig. Sonst gilt der reguläre Träger nach RVNR-Bereichsnummer.',
                                style: TextStyle(fontSize: 10, color: Colors.blue.shade800),
                              )),
                            ]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ─── RENTENWERT ───
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.shade200),
                ),
                child: Row(children: [
                  Icon(Icons.euro, color: Colors.deepPurple.shade700, size: 22),
                  const SizedBox(width: 8),
                  Text('Aktueller Rentenwert $currentYear:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(color: Colors.deepPurple.shade700, borderRadius: BorderRadius.circular(20)),
                    child: Text(_formatEur(rentenwert), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13)),
                  ),
                ]),
              ),
              const SizedBox(height: 20),

              // ─── RENTENART ───
              Text('Rentenart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8), color: Colors.white),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _rentenartLabels.containsKey(_rentenart) ? _rentenart : '',
                    isExpanded: true,
                    style: const TextStyle(fontSize: 13, color: Colors.black87),
                    items: _rentenartLabels.entries.map((e) {
                      final f = _rentenartFaktoren[e.key];
                      return DropdownMenuItem<String>(
                        value: e.key,
                        child: Text(f != null ? '${e.value} (Faktor: ${f.toStringAsFixed(2)})' : e.value, style: const TextStyle(fontSize: 13)),
                      );
                    }).toList(),
                    onChanged: (v) => setLocalState(() => _rentenart = v ?? ''),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Entgeltpunkte (EP)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _entgeltpunkteC,
                          decoration: InputDecoration(
                            hintText: 'z.B. 35,5',
                            prefixIcon: const Icon(Icons.star, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setLocalState(() {}),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Zugangsfaktor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        TextField(
                          controller: _zugangsfaktorC,
                          decoration: InputDecoration(
                            hintText: '1,0 (Standard)',
                            prefixIcon: const Icon(Icons.tune, size: 18),
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          style: const TextStyle(fontSize: 14),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: (_) => setLocalState(() {}),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(children: [
                Text('Kinder vorhanden?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('Ja', style: TextStyle(fontSize: 12)),
                  selected: _hatKinder,
                  onSelected: (_) => setLocalState(() => _hatKinder = true),
                  selectedColor: Colors.green.shade200,
                ),
                const SizedBox(width: 8),
                ChoiceChip(
                  label: const Text('Nein', style: TextStyle(fontSize: 12)),
                  selected: !_hatKinder,
                  onSelected: (_) => setLocalState(() => _hatKinder = false),
                  selectedColor: Colors.orange.shade200,
                ),
                const Spacer(),
                Text('PV: ${(_hatKinder ? _pvBeitragRentner : _pvBeitragKinderlos).toStringAsFixed(1)}%', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
              ]),
              const SizedBox(height: 16),

              // ─── BERECHNUNG ───
              if (ep > 0 && _rentenart.isNotEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                    boxShadow: [BoxShadow(color: Colors.orange.shade100, blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(Icons.calculate, color: Colors.orange.shade700, size: 18),
                        const SizedBox(width: 6),
                        Text('Rentenberechnung ($currentYear)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      ]),
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6)),
                        child: Text(
                          '${ep.toStringAsFixed(2)} EP x ${zf.toStringAsFixed(3)} x ${_formatEur(rentenwert)} x ${faktor.toStringAsFixed(2)}',
                          style: TextStyle(fontSize: 12, fontFamily: 'monospace', color: Colors.grey.shade800),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Brutto-Rente (monatlich):', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                        Text(_formatEur(brutto), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                      ]),
                      const Divider(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('KV-Beitrag (${(_kvBeitragRentner + _kvZusatzbeitrag / 2).toStringAsFixed(2)}%):', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('- ${_formatEur(kvAbzug)}', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                      ]),
                      const SizedBox(height: 3),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('PV-Beitrag (${pvSatz.toStringAsFixed(1)}%${_hatKinder ? '' : ' kinderlos'}):', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('- ${_formatEur(pvAbzug)}', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
                      ]),
                      const Divider(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Netto-Rente (ca.):', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade400)),
                          child: Text(_formatEur(netto), style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                        ),
                      ]),
                    ],
                  ),
                ),
              const SizedBox(height: 20),

              Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: _notizenC,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Zusaetzliche Informationen...',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _formatRow(String code, String desc) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 28,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: Colors.deepPurple.shade100, borderRadius: BorderRadius.circular(3)),
          child: Text(code, style: TextStyle(fontSize: 10, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800), textAlign: TextAlign.center),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(desc, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
      ]),
    );
  }

  Widget _bereichRow(String code, String traeger) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 42,
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(3), border: Border.all(color: Colors.indigo.shade200)),
          child: Text(code, style: TextStyle(fontSize: 9, fontFamily: 'monospace', fontWeight: FontWeight.bold, color: Colors.indigo.shade800), textAlign: TextAlign.center),
        ),
        const SizedBox(width: 6),
        Expanded(child: Text(traeger, style: TextStyle(fontSize: 10, color: Colors.grey.shade700))),
      ]),
    );
  }

  /// Lookup of the Rentenversicherungsträger based on the first two
  /// characters of the Versicherungsnummer (Bereichsnummer). Source: VKVV
  /// Anlage 1 (§ 2 Abs. 2 VKVV) — Stand 1.1.2008, plus reorganisations
  /// since then (DRV-Strukturreform 2005).
  String _drvFromBereich(String bereich) {
    const map = {
      '02': 'DRV Nord (ehem. LVA Mecklenburg-Vorpommern)',
      '03': 'DRV Mitteldeutschland (ehem. Thüringen)',
      '04': 'DRV Berlin-Brandenburg',
      '08': 'DRV Mitteldeutschland (ehem. Sachsen-Anhalt)',
      '09': 'DRV Mitteldeutschland (ehem. Sachsen)',
      '10': 'DRV Niedersachsen-Bremen (ehem. Hannover)',
      '11': 'DRV Westfalen',
      '12': 'DRV Hessen',
      '13': 'DRV Rheinland',
      '14': 'DRV Bayern Süd (ehem. Oberbayern)',
      '15': 'DRV Bayern Süd (ehem. Niederbayern-Oberpfalz)',
      '16': 'DRV Rheinland-Pfalz',
      '17': 'DRV Saarland',
      '18': 'DRV Nordbayern (ehem. Ober- und Mittelfranken)',
      '19': 'DRV Nord (ehem. LVA Hamburg)',
      '20': 'DRV Nordbayern (ehem. Unterfranken)',
      '21': 'DRV Bayern Süd (ehem. Schwaben)',
      '23': 'DRV Baden-Württemberg (ehem. Württemberg)',
      '24': 'DRV Baden-Württemberg (ehem. Baden)',
      '25': 'DRV Berlin-Brandenburg (ehem. Berlin)',
      '26': 'DRV Nord (ehem. Schleswig-Holstein)',
      '28': 'DRV Niedersachsen-Bremen (ehem. Oldenburg-Bremen)',
      '29': 'DRV Niedersachsen-Bremen (ehem. Braunschweig)',
      '38': 'DRV Knappschaft-Bahn-See (Bergbau)',
      '39': 'DRV Knappschaft-Bahn-See (Seeleute)',
      // DRV Bund (Bereich = regional + 40), Versicherte nach 2005 / ehem. BfA.
      '50': 'DRV Bund (ehem. Hannover)',
      '51': 'DRV Bund (ehem. Westfalen)',
      '52': 'DRV Bund (ehem. Hessen)',
      '53': 'DRV Bund (ehem. Rheinland)',
      '54': 'DRV Bund (ehem. Oberbayern)',
      '55': 'DRV Bund (ehem. Niederbayern-Oberpfalz)',
      '56': 'DRV Bund (ehem. Rheinland-Pfalz)',
      '57': 'DRV Bund (ehem. Saarland)',
      '58': 'DRV Bund (ehem. Ober-/Mittelfranken)',
      '59': 'DRV Bund (ehem. Hamburg)',
      '60': 'DRV Bund (ehem. Unterfranken)',
      '61': 'DRV Bund (ehem. Schwaben)',
      '62': 'DRV Bund (ehem. Hamburg)',
      '63': 'DRV Bund (ehem. Württemberg) — sehr verbreitet bei BW-Versicherten',
      '64': 'DRV Bund (ehem. Baden)',
      '65': 'DRV Bund (ehem. Berlin)',
      '66': 'DRV Bund (ehem. Schleswig-Holstein)',
      '68': 'DRV Bund (ehem. Oldenburg-Bremen)',
      '69': 'DRV Bund (ehem. Braunschweig)',
      '80': 'DRV Knappschaft-Bahn-See (Versicherte nach 2005)',
      '81': 'DRV Knappschaft-Bahn-See (Versicherte nach 2005)',
      '82': 'DRV Knappschaft-Bahn-See (Versicherte nach 2005)',
      '89': 'DRV Bund (Sonderzuweisung)',
    };
    return map[bereich] ?? 'Bereich $bereich — nicht in VKVV-Anlage 1 katalogisiert';
  }
}
