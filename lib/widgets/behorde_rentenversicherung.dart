import 'package:flutter/material.dart';

class BehordeRentenversicherungContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeRentenversicherungContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
  });

  @override
  State<BehordeRentenversicherungContent> createState() => _State();
}

class _State extends State<BehordeRentenversicherungContent> {
  static const type = 'rentenversicherung';

  static String _formatEurDouble(double amount) {
    final parts = amount.toStringAsFixed(2).split('.');
    return '${parts[0]},${parts[1]} EUR';
  }

  static const Map<int, Map<String, double>> _rentenwertTabelle = {
    2020: {'west': 34.19, 'ost': 33.23},
    2021: {'west': 34.19, 'ost': 33.47}, // Nullrunde West
    2022: {'west': 36.02, 'ost': 35.52},
    2023: {'west': 37.60, 'ost': 37.60}, // Angleichung
    2024: {'west': 39.32, 'ost': 39.32}, // Vollstaendig angeglichen
    2025: {'west': 40.79, 'ost': 40.79},
    2026: {'west': 41.83, 'ost': 41.83}, // Prognose Rentenanpassung 2026
  };

  static double _getRentenwert(int year) {
    final entry = _rentenwertTabelle[year] ?? _rentenwertTabelle.values.last;
    return entry['west']!; // Seit 2023 angeglichen
  }

  static const Map<String, double> _rentenartFaktoren = {
    'altersrente': 1.0,
    'volle_erwerbsminderung': 1.0,
    'teilweise_erwerbsminderung': 0.5,
    'grosse_witwenrente': 0.55,
    'kleine_witwenrente': 0.25,
    'halbwaisenrente': 0.10,
    'vollwaisenrente': 0.20,
  };

  static const double _kvBeitragRentner = 7.3; // halber allgemeiner Beitragssatz
  static const double _kvZusatzbeitrag = 2.5; // durchschnittlicher Zusatzbeitrag 2026
  static const double _pvBeitragRentner = 1.8; // Pflegeversicherung (mit Kindern)
  static const double _pvBeitragKinderlos = 2.3; // Pflegeversicherung (kinderlos ab 23)


  @override
  Widget build(BuildContext context) {
    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type)) {
      widget.loadData(type);
    }
    if (widget.isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }
    final dienststelleController = TextEditingController(text: data['dienststelle'] ?? '');
    final svNummerController = TextEditingController(text: data['sozialversicherungsnummer'] ?? '');
    final rentenversicherungstraegerController = TextEditingController(text: data['traeger'] ?? '');
    final entgeltpunkteController = TextEditingController(text: data['entgeltpunkte'] ?? '');
    final zugangsfaktorController = TextEditingController(text: data['zugangsfaktor'] ?? '1,0');
    final notizenController = TextEditingController(text: data['notizen'] ?? '');
    String rentenart = data['rentenart'] ?? '';
    bool hatKinder = (data['hat_kinder'] ?? 'ja') == 'ja';

    final rentenarten = {
      '': 'Nicht ausgewaehlt',
      'altersrente': 'Altersrente (Regelaltersrente)',
      'volle_erwerbsminderung': 'Volle Erwerbsminderungsrente',
      'teilweise_erwerbsminderung': 'Teilweise Erwerbsminderungsrente',
      'grosse_witwenrente': 'Grosse Witwen-/Witwerrente',
      'kleine_witwenrente': 'Kleine Witwen-/Witwerrente',
      'halbwaisenrente': 'Halbwaisenrente',
      'vollwaisenrente': 'Vollwaisenrente',
    };

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final currentYear = DateTime.now().year;
        final rentenwert = _getRentenwert(currentYear);
        final rentenartFaktor = _rentenartFaktoren[rentenart] ?? 1.0;

        // Parse Entgeltpunkte
        final epText = entgeltpunkteController.text.trim().replaceAll(',', '.');
        final entgeltpunkte = double.tryParse(epText) ?? 0;

        // Parse Zugangsfaktor
        final zfText = zugangsfaktorController.text.trim().replaceAll(',', '.');
        final zugangsfaktor = double.tryParse(zfText) ?? 1.0;

        // Brutto-Rente = EP × Zugangsfaktor × Rentenwert × Rentenartfaktor
        final bruttoRente = entgeltpunkte * zugangsfaktor * rentenwert * rentenartFaktor;

        // Netto-Rente: KV (7.3% + Zusatzbeitrag halber) + PV
        final kvAbzug = bruttoRente * (_kvBeitragRentner + _kvZusatzbeitrag / 2) / 100;
        final pvSatz = hatKinder ? _pvBeitragRentner : _pvBeitragKinderlos;
        final pvAbzug = bruttoRente * pvSatz / 100;
        final nettoRente = bruttoRente - kvAbzug - pvAbzug;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── RENTENWERT INFO CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.deepPurple.shade50, Colors.deepPurple.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.deepPurple.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.euro, color: Colors.deepPurple.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Aktueller Rentenwert $currentYear',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.deepPurple.shade700,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _formatEurDouble(rentenwert),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Wert eines Entgeltpunktes pro Monat. West und Ost seit 01.07.2024 angeglichen.',
                      style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade600, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),
                    // Verlauf
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          'Rentenwert-Verlauf anzeigen',
                          style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade700, fontWeight: FontWeight.w500),
                        ),
                        children: [
                          ..._rentenwertTabelle.entries.toList().reversed.map((entry) {
                            final isCurrent = entry.key == currentYear;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      '${entry.key}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        color: isCurrent ? Colors.deepPurple.shade800 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 20,
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: entry.value['west']! / (_rentenwertTabelle.values.last['west']! * 1.1),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isCurrent ? Colors.deepPurple.shade400 : Colors.deepPurple.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  SizedBox(
                                    width: 80,
                                    child: Text(
                                      _formatEurDouble(entry.value['west']!),
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        color: isCurrent ? Colors.deepPurple.shade800 : Colors.grey.shade600,
                                      ),
                                    ),
                                  ),
                                  if (entry.value['west'] != entry.value['ost'])
                                    Text(
                                      '(Ost: ${_formatEurDouble(entry.value['ost']!)})',
                                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                    ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                          Text(
                            'Anpassung jaehrlich zum 01.07. durch Bundesregierung.',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // ── STAMMDATEN ──
              widget.dienststelleBuilder(type, dienststelleController),
              Text('Sozialversicherungsnummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: svNummerController,
                decoration: InputDecoration(
                  hintText: '12-stellig, z.B. 12 150865 A 123',
                  prefixIcon: const Icon(Icons.badge, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text('Auf dem Sozialversicherungsausweis', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),

              // Rentenversicherungsträger
              Text('Rentenversicherungstraeger', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: rentenversicherungstraegerController,
                decoration: InputDecoration(
                  hintText: 'z.B. Deutsche Rentenversicherung Bund',
                  prefixIcon: const Icon(Icons.account_balance, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),

              // ── RENTENART & BERECHNUNG ──
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
                        Icon(Icons.calculate, color: Colors.orange.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Rentenberechnung',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Brutto-Rente = Entgeltpunkte x Zugangsfaktor x Rentenwert x Rentenartfaktor',
                      style: TextStyle(fontSize: 11, color: Colors.orange.shade600, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 16),

                    // Rentenart
                    Text('Rentenart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                        color: Colors.white,
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: rentenarten.containsKey(rentenart) ? rentenart : '',
                          isExpanded: true,
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          items: rentenarten.entries.map((e) {
                            final faktor = _rentenartFaktoren[e.key];
                            return DropdownMenuItem<String>(
                              value: e.key,
                              child: Text(
                                faktor != null ? '${e.value} (Faktor: ${faktor.toStringAsFixed(2)})' : e.value,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }).toList(),
                          onChanged: (v) => setLocalState(() => rentenart = v ?? ''),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Entgeltpunkte
                    Text('Entgeltpunkte (EP)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: entgeltpunkteController,
                      decoration: InputDecoration(
                        hintText: 'z.B. 35,5 (aus Renteninformation)',
                        prefixIcon: const Icon(Icons.star, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 14),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setLocalState(() {}),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1 EP = 1 Jahr Durchschnittsverdienst. Steht auf der jaehrlichen Renteninformation.',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),

                    // Zugangsfaktor
                    Text('Zugangsfaktor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: zugangsfaktorController,
                      decoration: InputDecoration(
                        hintText: '1,0 (Standard)',
                        prefixIcon: const Icon(Icons.tune, size: 20),
                        isDense: true,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      ),
                      style: const TextStyle(fontSize: 14),
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setLocalState(() {}),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1,0 = Regelaltersgrenze. Fruehverrentung: -0,003 pro Monat (z.B. 0,892 bei 3 Jahre frueher).',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),

                    // Kinder (fuer PV-Berechnung)
                    Row(
                      children: [
                        Text('Kinder vorhanden?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        const SizedBox(width: 12),
                        ChoiceChip(
                          label: const Text('Ja', style: TextStyle(fontSize: 12)),
                          selected: hatKinder,
                          onSelected: (v) => setLocalState(() => hatKinder = true),
                          selectedColor: Colors.green.shade200,
                        ),
                        const SizedBox(width: 8),
                        ChoiceChip(
                          label: const Text('Nein', style: TextStyle(fontSize: 12)),
                          selected: !hatKinder,
                          onSelected: (v) => setLocalState(() => hatKinder = false),
                          selectedColor: Colors.orange.shade200,
                        ),
                        const Spacer(),
                        Text(
                          'PV: ${hatKinder ? _pvBeitragRentner : _pvBeitragKinderlos}%',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── ERGEBNIS ──
                    if (entgeltpunkte > 0 && rentenart.isNotEmpty) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade300),
                          boxShadow: [BoxShadow(color: Colors.orange.shade100, blurRadius: 6, offset: const Offset(0, 2))],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Rentenberechnung ($currentYear)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                            const SizedBox(height: 10),
                            // Formula display
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${entgeltpunkte.toStringAsFixed(2)} EP  x  ${zugangsfaktor.toStringAsFixed(3)}  x  ${_formatEurDouble(rentenwert)}  x  ${rentenartFaktor.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 13, fontFamily: 'monospace', color: Colors.grey.shade800),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Brutto
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Brutto-Rente (monatlich):', style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                                Text(
                                  _formatEurDouble(bruttoRente),
                                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                                ),
                              ],
                            ),
                            const Divider(height: 16),
                            // Abzuege
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('KV-Beitrag (${(_kvBeitragRentner + _kvZusatzbeitrag / 2).toStringAsFixed(2)}%):', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                Text('- ${_formatEurDouble(kvAbzug)}', style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('PV-Beitrag (${pvSatz.toStringAsFixed(1)}%${hatKinder ? '' : ' kinderlos'}):', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                                Text('- ${_formatEurDouble(pvAbzug)}', style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
                              ],
                            ),
                            const Divider(height: 16),
                            // Netto
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Netto-Rente (ca.):', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: Colors.green.shade400),
                                  ),
                                  child: Text(
                                    _formatEurDouble(nettoRente),
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Jaehrlich
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Brutto jaehrlich:', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                Text(_formatEurDouble(bruttoRente * 12), style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontWeight: FontWeight.w500)),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Netto jaehrlich (ca.):', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                Text(_formatEurDouble(nettoRente * 12), style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w500)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Hinweis: Netto-Berechnung ohne Einkommensteuer. Steuerpflicht haengt vom Gesamteinkommen und Rentenfreibetrag ab.',
                              style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Info: Rentenarten erklaert
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 6),
                        Text('Rentenarten im Ueberblick', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _rentenInfoRow(Icons.elderly, 'Altersrente', 'Ab Regelaltersgrenze (67 J.), Faktor 1,0', Colors.deepPurple),
                    _rentenInfoRow(Icons.accessible, 'Volle Erwerbsminderung', 'Weniger als 3 Std./Tag arbeitsfaehig, Faktor 1,0', Colors.red),
                    _rentenInfoRow(Icons.accessibility_new, 'Teilw. Erwerbsminderung', '3-6 Std./Tag arbeitsfaehig, Faktor 0,5', Colors.orange),
                    _rentenInfoRow(Icons.favorite, 'Grosse Witwenrente', 'Ab 47 J. oder erwerbsgemindert, Faktor 0,55', Colors.pink),
                    _rentenInfoRow(Icons.favorite_border, 'Kleine Witwenrente', 'Unter 47 J., max. 2 Jahre, Faktor 0,25', Colors.pink),
                    _rentenInfoRow(Icons.child_care, 'Halbwaisenrente', 'Ein Elternteil verstorben, Faktor 0,10', Colors.teal),
                    _rentenInfoRow(Icons.child_friendly, 'Vollwaisenrente', 'Beide Elternteile verstorben, Faktor 0,20', Colors.teal),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Notizen
              Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: notizenController,
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

              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) == true ? null : () {
                    widget.saveData(type, {
                      'dienststelle': dienststelleController.text.trim(),
                      'sozialversicherungsnummer': svNummerController.text.trim(),
                      'traeger': rentenversicherungstraegerController.text.trim(),
                      'rentenart': rentenart,
                      'entgeltpunkte': entgeltpunkteController.text.trim(),
                      'zugangsfaktor': zugangsfaktorController.text.trim(),
                      'hat_kinder': hatKinder ? 'ja' : 'nein',
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

  Widget _rentenInfoRow(IconData icon, String title, String desc, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color.shade400),
          const SizedBox(width: 6),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(text: '$title: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                  TextSpan(text: desc, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

}
