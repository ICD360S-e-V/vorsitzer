import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BehordeFamilienkasseContent extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeFamilienkasseContent({
    super.key,
    required this.apiService,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  @override
  State<BehordeFamilienkasseContent> createState() => _BehordeFamilienkasseContentState();
}

class _BehordeFamilienkasseContentState extends State<BehordeFamilienkasseContent> {
  static const type = 'familienkasse';

  // Controllers (class-level to avoid memory leaks)
  final _dienststelleController = TextEditingController();
  final _kindergeldNrController = TextEditingController();
  final _kinderzuschlagController = TextEditingController();
  final _sachbearbeiterController = TextEditingController();
  final _notizenController = TextEditingController();
  bool _controllersInitialized = false;

  static String _formatCurrency(int amount) {
    final str = amount.toString();
    final parts = <String>[];
    for (var i = str.length; i > 0; i -= 3) {
      parts.insert(0, str.substring(i - 3 < 0 ? 0 : i - 3, i));
    }
    return '${parts.join(".")} \u20AC';
  }

  static int _getGrundfreibetrag(int year, {bool verheiratet = false}) {
    const tabelle = {2023: 10908, 2024: 11604, 2025: 12084, 2026: 12336};
    final betrag = tabelle[year] ?? tabelle.values.last;
    return verheiratet ? betrag * 2 : betrag;
  }

  static const Map<int, int> _kindergeldTabelle = {
    2020: 204, // 1st+2nd child (3rd: 210, 4th+: 235)
    2021: 219, // 1st+2nd child (3rd: 225, 4th+: 250)
    2022: 219,
    2023: 250, // einheitlich ab 2023
    2024: 250,
    2025: 255,
    2026: 259,
  };

  // Kinderfreibetrag per child per year (both parents together)
  static const Map<int, int> _kinderfreibetragTabelle = {
    2020: 5172,
    2021: 5460,
    2022: 5620,
    2023: 6024,
    2024: 6612,
    2025: 6672,
    2026: 6828,
  };

  // BEA-Freibetrag (Betreuung, Erziehung, Ausbildung) per child per year
  static const Map<int, int> _beaFreibetragTabelle = {
    2020: 2640,
    2021: 2928,
    2022: 2928,
    2023: 2928,
    2024: 2928,
    2025: 2928,
    2026: 2928,
  };

  static int _getKindergeld(int year) => _kindergeldTabelle[year] ?? _kindergeldTabelle.values.last;
  static int _getKinderfreibetrag(int year) => _kinderfreibetragTabelle[year] ?? _kinderfreibetragTabelle.values.last;
  static int _getBeaFreibetrag(int year) => _beaFreibetragTabelle[year] ?? _beaFreibetragTabelle.values.last;

  void _initControllers(Map<String, dynamic> data) {
    if (!_controllersInitialized) {
      _dienststelleController.text = data['dienststelle'] ?? '';
      _kindergeldNrController.text = data['kindergeld_nr'] ?? '';
      _kinderzuschlagController.text = data['kinderzuschlag'] ?? '';
      _sachbearbeiterController.text = data['sachbearbeiter'] ?? '';
      _notizenController.text = data['notizen'] ?? '';
      _controllersInitialized = true;
    }
  }

  @override
  void dispose() {
    _dienststelleController.dispose();
    _kindergeldNrController.dispose();
    _kinderzuschlagController.dispose();
    _sachbearbeiterController.dispose();
    _notizenController.dispose();
    super.dispose();
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
    _initControllers(data);
    final dienststelleController = _dienststelleController;
    final kindergeldNrController = _kindergeldNrController;
    final kinderzuschlagController = _kinderzuschlagController;
    final sachbearbeiterController = _sachbearbeiterController;
    final notizenController = _notizenController;
    bool hatKinderzuschlag = data['hat_kinderzuschlag'] == true;

    // Parse children list from saved data
    List<Map<String, dynamic>> kinderListe = [];
    if (data['kinder_liste'] != null) {
      kinderListe = List<Map<String, dynamic>>.from(
        (data['kinder_liste'] as List).map((k) => Map<String, dynamic>.from(k as Map)),
      );
    }

    const statusLabels = {
      'kind': 'Minderjahriges Kind',
      'schule': 'Schuler/in',
      'ausbildung': 'In Ausbildung',
      'studium': 'Im Studium',
      'fsj': 'FSJ / BFD (Freiwilligendienst)',
      'arbeitssuchend': 'Arbeitssuchend',
      'behinderung': 'Behinderung (nicht erwerbsfahig)',
      'berufstaetig': 'Berufstatig / Keine Ausbildung',
    };

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final now = DateTime.now();
        final currentYear = now.year;
        final kindergeldMonat = _getKindergeld(currentYear);
        final kinderfreibetrag = _getKinderfreibetrag(currentYear);
        final beaFreibetrag = _getBeaFreibetrag(currentYear);
        final gesamtFreibetrag = kinderfreibetrag + beaFreibetrag;
        final kindergeldJahr = kindergeldMonat * 12;

        // Calculate age and eligibility for each child
        int berechtigteKinder = 0;
        for (final kind in kinderListe) {
          final eligible = _isKindergeldBerechtigt(kind, now);
          if (eligible) berechtigteKinder++;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── KINDER LISTE ──
              Row(
                children: [
                  Icon(Icons.child_care, size: 20, color: Colors.orange.shade700),
                  const SizedBox(width: 6),
                  Text('Kinder', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                  const Spacer(),
                  if (kinderListe.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
                      child: Text('${kinderListe.length} ${kinderListe.length == 1 ? 'Kind' : 'Kinder'}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                    ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => setLocalState(() {
                      kinderListe.add({'name': '', 'geburtsdatum': '', 'status': 'kind', 'behinderung': false});
                    }),
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Kind hinzufugen'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Each child card
              ...kinderListe.asMap().entries.map((entry) {
                final idx = entry.key;
                final kind = entry.value;
                final alter = _berechneAlter(kind['geburtsdatum'] ?? '', now);
                final eligible = _isKindergeldBerechtigt(kind, now);
                final status = kind['status'] ?? 'kind';
                final eligInfo = _getKindergeldStatusInfo(kind, now);

                return Container(
                  key: ValueKey('kind_$idx'),
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: eligible ? Colors.green.shade50 : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: eligible ? Colors.green.shade300 : Colors.red.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header with number + delete
                      Row(
                        children: [
                          Container(
                            width: 26, height: 26,
                            decoration: BoxDecoration(color: eligible ? Colors.green.shade600 : Colors.red.shade400, shape: BoxShape.circle),
                            child: Center(child: Text('${idx + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13))),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              (kind['name'] ?? '').toString().isNotEmpty ? kind['name'] : 'Kind ${idx + 1}',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.grey.shade800),
                            ),
                          ),
                          if (alter != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(10)),
                              child: Text('$alter ${alter == 1 ? 'Jahr' : 'Jahre'}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                            ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: eligible ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              eligible ? 'Berechtigt' : 'Kein Anspruch',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: eligible ? Colors.green.shade800 : Colors.red.shade700),
                            ),
                          ),
                          const SizedBox(width: 4),
                          InkWell(
                            onTap: () => setLocalState(() => kinderListe.removeAt(idx)),
                            child: Icon(Icons.close, size: 18, color: Colors.red.shade400),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Name + Geburtsdatum row
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: TextEditingController(text: kind['name'] ?? ''),
                              decoration: InputDecoration(
                                labelText: 'Name',
                                prefixIcon: const Icon(Icons.person_outline, size: 18),
                                isDense: true,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              ),
                              style: const TextStyle(fontSize: 13),
                              onChanged: (v) => kind['name'] = v,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 2,
                            child: GestureDetector(
                              onTap: () async {
                                final initial = _parseDateDE(kind['geburtsdatum'] ?? '');
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: initial ?? DateTime(2010, 1, 1),
                                  firstDate: DateTime(1970),
                                  lastDate: now,
                                  locale: const Locale('de'),
                                );
                                if (picked != null) {
                                  setLocalState(() {
                                    kind['geburtsdatum'] = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                                    // Auto-set status based on age
                                    final age = _berechneAlter(kind['geburtsdatum'], now);
                                    if (age != null && age < 18) {
                                      kind['status'] = 'kind';
                                    }
                                  });
                                }
                              },
                              child: AbsorbPointer(
                                child: TextField(
                                  controller: TextEditingController(text: kind['geburtsdatum'] ?? ''),
                                  decoration: InputDecoration(
                                    labelText: 'Geburtsdatum',
                                    prefixIcon: const Icon(Icons.cake, size: 18),
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                  ),
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Status dropdown (only for 18+)
                      if (alter != null && alter >= 18) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: statusLabels.containsKey(status) ? status : 'berufstaetig',
                              isExpanded: true,
                              style: const TextStyle(fontSize: 13, color: Colors.black87),
                              items: statusLabels.entries.where((e) => e.key != 'kind').map((e) {
                                return DropdownMenuItem(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)));
                              }).toList(),
                              onChanged: (v) => setLocalState(() => kind['status'] = v),
                            ),
                          ),
                        ),
                      ],
                      // ── BEHINDERUNG DETAILS ──
                      if (status == 'behinderung') ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.purple.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.purple.shade300),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.accessible, size: 18, color: Colors.purple.shade700),
                                  const SizedBox(width: 6),
                                  Text('Behinderung - Details', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // GdB
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Grad der Behinderung (GdB)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                                          child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                              value: (kind['gdb'] ?? '').toString().isEmpty ? '' : kind['gdb'].toString(),
                                              isExpanded: true,
                                              style: const TextStyle(fontSize: 12, color: Colors.black87),
                                              items: const [
                                                DropdownMenuItem(value: '', child: Text('Nicht angegeben', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '20', child: Text('GdB 20', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '30', child: Text('GdB 30', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '40', child: Text('GdB 40', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '50', child: Text('GdB 50 (Schwerbehinderung)', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '60', child: Text('GdB 60', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '70', child: Text('GdB 70', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '80', child: Text('GdB 80', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '90', child: Text('GdB 90', style: TextStyle(fontSize: 12))),
                                                DropdownMenuItem(value: '100', child: Text('GdB 100', style: TextStyle(fontSize: 12))),
                                              ],
                                              onChanged: (v) => setLocalState(() => kind['gdb'] = v),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Merkzeichen
                              Text('Merkzeichen im Schwerbehindertenausweis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _merkzeichenChip('H', 'Hilflos', kind, setLocalState),
                                  _merkzeichenChip('Bl', 'Blind', kind, setLocalState),
                                  _merkzeichenChip('B', 'Begleitperson', kind, setLocalState),
                                  _merkzeichenChip('aG', 'Auss. gehbehindert', kind, setLocalState),
                                  _merkzeichenChip('G', 'Gehbehindert', kind, setLocalState),
                                  _merkzeichenChip('Gl', 'Gehorlos', kind, setLocalState),
                                  _merkzeichenChip('TBl', 'Taubblind', kind, setLocalState),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Behinderung eingetreten vor 25
                              Row(
                                children: [
                                  Checkbox(
                                    value: kind['beh_vor_25'] == true,
                                    onChanged: (v) => setLocalState(() => kind['beh_vor_25'] = v),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Behinderung vor Vollendung des 25. Lebensjahres eingetreten',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              ),
                              // Nicht selbst unterhalten
                              Row(
                                children: [
                                  Checkbox(
                                    value: kind['nicht_selbst_unterhalten'] == true,
                                    onChanged: (v) => setLocalState(() => kind['nicht_selbst_unterhalten'] = v),
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                  Expanded(
                                    child: Text(
                                      'Kind kann sich nicht selbst unterhalten (Einkommen unter Grundfreibetrag ${_formatCurrency(_getGrundfreibetrag(DateTime.now().year))})',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // GdB warning
                              if ((kind['gdb'] ?? '').toString().isNotEmpty) ...[
                                () {
                                  final gdb = int.tryParse(kind['gdb'].toString()) ?? 0;
                                  if (gdb < 50) {
                                    return Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade300)),
                                      child: Row(
                                        children: [
                                          Icon(Icons.warning_amber, size: 16, color: Colors.amber.shade700),
                                          const SizedBox(width: 6),
                                          Expanded(child: Text('GdB unter 50 - Kindergeld-Anspruch bei Behinderung erfordert i.d.R. mindestens GdB 50 (Schwerbehinderung)', style: TextStyle(fontSize: 11, color: Colors.amber.shade800))),
                                        ],
                                      ),
                                    );
                                  }
                                  return const SizedBox.shrink();
                                }(),
                              ],
                              // Merkzeichen H info
                              if (_hatMerkzeichen(kind, 'H'))
                                Padding(
                                  padding: const EdgeInsets.only(top: 6),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.green.shade300)),
                                    child: Row(
                                      children: [
                                        Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                                        const SizedBox(width: 6),
                                        Expanded(child: Text('Merkzeichen H (hilflos) vorhanden - Kindergeld-Anspruch wird von der Familienkasse grundsatzlich anerkannt', style: TextStyle(fontSize: 11, color: Colors.green.shade800))),
                                      ],
                                    ),
                                  ),
                                ),
                              // Info box
                              const SizedBox(height: 8),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade200)),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Kindergeld bei Behinderung - Voraussetzungen:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                    const SizedBox(height: 4),
                                    _fkRuleRow(Icons.check_circle, 'Behinderung vor dem 25. Lebensjahr eingetreten', Colors.green),
                                    _fkRuleRow(Icons.check_circle, 'Kind kann sich nicht selbst unterhalten', Colors.green),
                                    _fkRuleRow(Icons.check_circle, 'GdB mindestens 50 (Schwerbehinderung)', Colors.green),
                                    _fkRuleRow(Icons.check_circle, 'Merkzeichen H = automatisch anerkannt', Colors.green),
                                    _fkRuleRow(Icons.check_circle, 'Einkommen unter ${_formatCurrency(_getGrundfreibetrag(DateTime.now().year))}/Jahr', Colors.green),
                                    _fkRuleRow(Icons.check_circle, 'Anspruch unbefristet (lebenslang)', Colors.green),
                                    const SizedBox(height: 4),
                                    Text('Nachweise: Schwerbehindertenausweis, arztliches Gutachten, Pflegegrad-Bescheid', style: TextStyle(fontSize: 10, color: Colors.blue.shade600, fontStyle: FontStyle.italic)),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Status info text
                      if (eligInfo.isNotEmpty && status != 'behinderung') ...[
                        const SizedBox(height: 6),
                        Text(eligInfo, style: TextStyle(fontSize: 11, color: eligible ? Colors.green.shade700 : Colors.red.shade600, fontStyle: FontStyle.italic)),
                      ],
                    ],
                  ),
                );
              }),

              if (kinderListe.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)),
                  child: Column(
                    children: [
                      Icon(Icons.child_care, size: 40, color: Colors.grey.shade400),
                      const SizedBox(height: 8),
                      Text('Keine Kinder eingetragen', style: TextStyle(color: Colors.grey.shade500)),
                      Text('Klicken Sie auf "Kind hinzufugen"', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                    ],
                  ),
                ),
              const SizedBox(height: 16),

              // ── KINDERGELD INFO CARD ──
              if (kinderListe.isNotEmpty) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Colors.orange.shade50, Colors.orange.shade100],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.child_care, color: Colors.orange.shade700, size: 22),
                          const SizedBox(width: 8),
                          Text('Kindergeld $currentYear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: Colors.orange.shade700, borderRadius: BorderRadius.circular(12)),
                            child: Text('$berechtigteKinder / ${kinderListe.length} berechtigt', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _fkInfoRow('Pro Kind / Monat', '$kindergeldMonat EUR', Colors.orange),
                      _fkInfoRow('Pro Kind / Jahr', _formatCurrency(kindergeldJahr), Colors.orange),
                      if (berechtigteKinder > 0) ...[
                        const Divider(height: 16),
                        _fkInfoRow(
                          'Gesamt fur $berechtigteKinder berechtigte${berechtigteKinder == 1 ? 's Kind' : ' Kinder'} / Monat',
                          _formatCurrency(kindergeldMonat * berechtigteKinder),
                          Colors.orange, bold: true,
                        ),
                        _fkInfoRow(
                          'Gesamt fur $berechtigteKinder berechtigte${berechtigteKinder == 1 ? 's Kind' : ' Kinder'} / Jahr',
                          _formatCurrency(kindergeldJahr * berechtigteKinder),
                          Colors.orange, bold: true,
                        ),
                      ],
                      if (berechtigteKinder < kinderListe.length) ...[
                        const SizedBox(height: 6),
                        Text(
                          '${kinderListe.length - berechtigteKinder} ${kinderListe.length - berechtigteKinder == 1 ? 'Kind' : 'Kinder'} ohne Anspruch (uber 25 oder nicht in Ausbildung)',
                          style: TextStyle(fontSize: 11, color: Colors.red.shade400, fontStyle: FontStyle.italic),
                        ),
                      ],
                      const SizedBox(height: 8),
                      // Regeln
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Kindergeld-Anspruch:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                            const SizedBox(height: 4),
                            _fkRuleRow(Icons.check_circle, 'Unter 18 Jahre: immer', Colors.green),
                            _fkRuleRow(Icons.check_circle, '18-25 Jahre: in Ausbildung, Studium, FSJ/BFD', Colors.green),
                            _fkRuleRow(Icons.check_circle, '18-25 Jahre: arbeitssuchend (max. 4 Monate)', Colors.green),
                            _fkRuleRow(Icons.check_circle, 'Uber 25: nur bei Behinderung (vor dem 25. Lj. eingetreten)', Colors.green),
                            _fkRuleRow(Icons.cancel, 'Uber 25 ohne Behinderung: kein Anspruch', Colors.red),
                          ],
                        ),
                      ),
                      // History
                      const SizedBox(height: 8),
                      Theme(
                        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.zero,
                          title: Text('Kindergeld-Verlauf anzeigen', style: TextStyle(fontSize: 12, color: Colors.orange.shade700, fontWeight: FontWeight.w500)),
                          children: [
                            ..._kindergeldTabelle.entries.toList().reversed.map((entry) {
                              final isCurrent = entry.key == currentYear;
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Row(
                                  children: [
                                    SizedBox(width: 50, child: Text('${entry.key}', style: TextStyle(fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.orange.shade800 : Colors.grey.shade600))),
                                    Expanded(
                                      child: Container(
                                        height: 18,
                                        alignment: Alignment.centerLeft,
                                        child: FractionallySizedBox(
                                          widthFactor: entry.value / (_kindergeldTabelle.values.last * 1.15),
                                          child: Container(decoration: BoxDecoration(color: isCurrent ? Colors.orange.shade400 : Colors.orange.shade200, borderRadius: BorderRadius.circular(4))),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text('${entry.value} EUR', style: TextStyle(fontSize: 12, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.orange.shade800 : Colors.grey.shade600)),
                                  ],
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── KINDERFREIBETRAG + BEA CARD ──
                if (berechtigteKinder > 0)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.indigo.shade50, Colors.indigo.shade100],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.indigo.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.account_balance, color: Colors.indigo.shade700, size: 22),
                            const SizedBox(width: 8),
                            Text('Kinderfreibetrage $currentYear', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.indigo.shade200)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Kinderfreibetrag (sachliches Existenzminimum)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                              const SizedBox(height: 4),
                              _fkInfoRow('Pro Kind (beide Eltern)', _formatCurrency(kinderfreibetrag), Colors.indigo),
                              _fkInfoRow('Pro Elternteil', _formatCurrency(kinderfreibetrag ~/ 2), Colors.indigo),
                              if (berechtigteKinder > 1)
                                _fkInfoRow('Gesamt $berechtigteKinder Kinder', _formatCurrency(kinderfreibetrag * berechtigteKinder), Colors.indigo, bold: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('BEA-Freibetrag (Betreuung, Erziehung, Ausbildung)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.purple.shade700)),
                              const SizedBox(height: 4),
                              _fkInfoRow('Pro Kind (beide Eltern)', _formatCurrency(beaFreibetrag), Colors.purple),
                              _fkInfoRow('Pro Elternteil', _formatCurrency(beaFreibetrag ~/ 2), Colors.purple),
                              if (berechtigteKinder > 1)
                                _fkInfoRow('Gesamt $berechtigteKinder Kinder', _formatCurrency(beaFreibetrag * berechtigteKinder), Colors.purple, bold: true),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade400)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Gesamter Freibetrag', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Text('${_formatCurrency(kinderfreibetrag)} + ${_formatCurrency(beaFreibetrag)} = ', style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                                  Text(_formatCurrency(gesamtFreibetrag), style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                                  const Text(' / Kind', style: TextStyle(fontSize: 11)),
                                ],
                              ),
                              if (berechtigteKinder > 1) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Gesamt fur $berechtigteKinder Kinder: ${_formatCurrency(gesamtFreibetrag * berechtigteKinder)}',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
                                  const SizedBox(width: 6),
                                  Text('Kindergeld oder Freibetrag?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Das Finanzamt pruft automatisch (Gunstigerprofung), ob Kindergeld oder Kinderfreibetrag vorteilhafter ist.',
                                style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Kindergeld: ${_formatCurrency(kindergeldJahr * berechtigteKinder)}/Jahr vs. Freibetrag-Ersparnis: max ~${_formatCurrency((gesamtFreibetrag * berechtigteKinder * 0.42).round())}/Jahr (42%)',
                                style: TextStyle(fontSize: 11, color: Colors.blue.shade600, fontStyle: FontStyle.italic),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Theme(
                          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                          child: ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: EdgeInsets.zero,
                            title: Text('Freibetrag-Verlauf anzeigen', style: TextStyle(fontSize: 12, color: Colors.indigo.shade700, fontWeight: FontWeight.w500)),
                            children: [
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  children: [
                                    const SizedBox(width: 40, child: Text('Jahr', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    const Expanded(child: Text('Kinderfreibetrag', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 65, child: Text('BEA', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                    const SizedBox(width: 70, child: Text('Gesamt', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold))),
                                  ],
                                ),
                              ),
                              ..._kinderfreibetragTabelle.entries.toList().reversed.map((entry) {
                                final year = entry.key;
                                final kfb = entry.value;
                                final bea = _beaFreibetragTabelle[year] ?? 2928;
                                final isCurrent = year == currentYear;
                                final style = TextStyle(fontSize: 11, fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, color: isCurrent ? Colors.indigo.shade800 : Colors.grey.shade600);
                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 1),
                                  child: Row(
                                    children: [
                                      SizedBox(width: 40, child: Text('$year', style: style)),
                                      Expanded(child: Text(_formatCurrency(kfb), style: style)),
                                      SizedBox(width: 65, child: Text(_formatCurrency(bea), style: style)),
                                      SizedBox(width: 70, child: Text(_formatCurrency(kfb + bea), style: style)),
                                    ],
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
              ],

              // ── EXISTING FIELDS ──
              widget.dienststelleBuilder(type, dienststelleController),
              Text('Kindergeld-Nummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: kindergeldNrController,
                decoration: InputDecoration(
                  hintText: 'z.B. FK 123 456 789 0',
                  prefixIcon: const Icon(Icons.confirmation_number, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Text('Kinderzuschlag', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(width: 8),
                  Switch(
                    value: hatKinderzuschlag,
                    activeTrackColor: Colors.green.shade300,
                    activeThumbColor: Colors.green,
                    onChanged: (val) => setLocalState(() => hatKinderzuschlag = val),
                  ),
                  Text(hatKinderzuschlag ? 'Ja' : 'Nein', style: TextStyle(color: hatKinderzuschlag ? Colors.green : Colors.grey)),
                ],
              ),
              if (hatKinderzuschlag) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: kinderzuschlagController,
                  decoration: InputDecoration(
                    hintText: 'Betrag / Details',
                    prefixIcon: const Icon(Icons.euro, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Text('Sachbearbeiter/in', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: sachbearbeiterController,
                decoration: InputDecoration(
                  hintText: 'Name des Sachbearbeiters',
                  prefixIcon: const Icon(Icons.person, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: notizenController,
                maxLines: 3,
                decoration: InputDecoration(
                  hintText: 'Weitere Informationen...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) == true ? null : () {
                    widget.saveData(type, {
                      'dienststelle': dienststelleController.text.trim(),
                      'kindergeld_nr': kindergeldNrController.text.trim(),
                      'kinder_liste': kinderListe,
                      'anzahl_kinder': kinderListe.length,
                      'hat_kinderzuschlag': hatKinderzuschlag,
                      'kinderzuschlag': kinderzuschlagController.text.trim(),
                      'sachbearbeiter': sachbearbeiterController.text.trim(),
                      'notizen': notizenController.text.trim(),
                    });
                  },
                  icon: widget.isSaving(type) == true
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _fkInfoRow(String label, String value, MaterialColor color, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 12, color: color.shade700))),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: color.shade800)),
        ],
      ),
    );
  }

  Widget _fkRuleRow(IconData icon, String text, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: color.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 11, color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  /// Parse German date format (DD.MM.YYYY) to DateTime
  DateTime? _parseDateDE(String dateStr) {
    if (dateStr.isEmpty) return null;
    final parts = dateStr.split('.');
    if (parts.length != 3) return null;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return null;
    return DateTime(year, month, day);
  }

  /// Calculate age from German date string
  int? _berechneAlter(String geburtsdatum, DateTime now) {
    final geb = _parseDateDE(geburtsdatum);
    if (geb == null) return null;
    int alter = now.year - geb.year;
    if (now.month < geb.month || (now.month == geb.month && now.day < geb.day)) {
      alter--;
    }
    return alter;
  }

  /// Check if a child is eligible for Kindergeld
  bool _isKindergeldBerechtigt(Map<String, dynamic> kind, DateTime now) {
    final alter = _berechneAlter(kind['geburtsdatum'] ?? '', now);
    if (alter == null) return true; // No birthday = assume eligible
    final status = kind['status'] ?? 'kind';

    // Under 18: always eligible
    if (alter < 18) return true;

    // 18-24 (until 25th birthday): eligible if in training/education/FSJ/job-seeking
    if (alter < 25) {
      return status == 'schule' || status == 'ausbildung' || status == 'studium' ||
             status == 'fsj' || status == 'arbeitssuchend' || status == 'behinderung';
    }

    // 25+: only with disability (that occurred before age 25)
    if (status == 'behinderung') return true;

    return false;
  }

  /// Get info text about Kindergeld eligibility for a child
  String _getKindergeldStatusInfo(Map<String, dynamic> kind, DateTime now) {
    final alter = _berechneAlter(kind['geburtsdatum'] ?? '', now);
    if (alter == null) return 'Geburtsdatum eingeben fur automatische Prufung';
    final status = kind['status'] ?? 'kind';

    if (alter < 18) {
      return 'Unter 18 - Kindergeld-Anspruch besteht automatisch';
    }

    if (alter >= 18 && alter < 25) {
      switch (status) {
        case 'schule': return 'Schuler/in - Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'ausbildung': return 'In Ausbildung - Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'studium': return 'Im Studium - Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'fsj': return 'FSJ/BFD - Kindergeld-Anspruch bis 25. Lebensjahr';
        case 'arbeitssuchend': return 'Arbeitssuchend - Kindergeld max. 4 Monate';
        case 'behinderung': return 'Behinderung - Kindergeld-Anspruch unbefristet';
        case 'berufstaetig': return 'Berufstatig - kein Kindergeld-Anspruch (nicht in Ausbildung)';
        default: return 'Status wahlen fur Kindergeld-Prufung';
      }
    }

    if (alter >= 25) {
      if (status == 'behinderung') {
        return 'Uber 25 mit Behinderung - Kindergeld-Anspruch unbefristet (wenn Behinderung vor 25. Lj.)';
      }
      return 'Uber 25 - kein Kindergeld-Anspruch mehr (nur bei Behinderung vor dem 25. Lebensjahr)';
    }

    return '';
  }

  /// Toggle chip for Merkzeichen in Schwerbehindertenausweis
  Widget _merkzeichenChip(String code, String label, Map<String, dynamic> kind, void Function(void Function()) setLocalState) {
    final merkzeichen = List<String>.from(kind['merkzeichen'] ?? []);
    final selected = merkzeichen.contains(code);
    return FilterChip(
      label: Text('$code ($label)', style: TextStyle(fontSize: 10, color: selected ? Colors.white : Colors.purple.shade700)),
      selected: selected,
      selectedColor: Colors.purple.shade600,
      checkmarkColor: Colors.white,
      backgroundColor: Colors.purple.shade50,
      side: BorderSide(color: selected ? Colors.purple.shade600 : Colors.purple.shade200),
      padding: const EdgeInsets.symmetric(horizontal: 2),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      onSelected: (val) {
        setLocalState(() {
          if (val) {
            merkzeichen.add(code);
          } else {
            merkzeichen.remove(code);
          }
          kind['merkzeichen'] = merkzeichen;
        });
      },
    );
  }

  /// Check if a child has a specific Merkzeichen
  bool _hatMerkzeichen(Map<String, dynamic> kind, String code) {
    final merkzeichen = List<String>.from(kind['merkzeichen'] ?? []);
    return merkzeichen.contains(code);
  }

}
