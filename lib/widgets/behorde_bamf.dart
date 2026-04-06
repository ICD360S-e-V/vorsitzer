import 'package:flutter/material.dart';
import '../services/api_service.dart';

class BehordeBamfContent extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;

  const BehordeBamfContent({
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
  State<BehordeBamfContent> createState() => _BehordeBamfContentState();
}

class _BehordeBamfContentState extends State<BehordeBamfContent> {
  static const type = 'bamf';

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
    final aktenzeichenController = TextEditingController(text: data['aktenzeichen'] ?? '');
    final integrationskursNrController = TextEditingController(text: data['integrationskurs_nr'] ?? '');
    final sachbearbeiterController = TextEditingController(text: data['sachbearbeiter'] ?? '');
    final notizenController = TextEditingController(text: data['notizen'] ?? '');
    String verfahrensstatus = data['verfahrensstatus'] ?? 'Keins';
    String sprachniveau = data['sprachniveau'] ?? 'Keins';

    // Integrationskurs-Abfrage Felder
    bool mandantGefragt = data['mandant_gefragt'] == true;
    bool hatMitBamfZuTun = data['hat_mit_bamf_zu_tun'] == true;
    String kursart = data['integrationskurs_art'] ?? 'Allgemeiner Integrationskurs';
    bool sprachkursAbgeschlossen = data['sprachkurs_abgeschlossen'] == true;
    bool orientierungskursAbgeschlossen = data['orientierungskurs_abgeschlossen'] == true;
    bool wiederholungsstunden = data['wiederholungsstunden'] == true;
    final wiederholungsstundenAnzahlC = TextEditingController(text: data['wiederholungsstunden_anzahl'] ?? '');
    bool dtzBestanden = data['dtz_bestanden'] == true;
    String dtzErgebnis = data['dtz_ergebnis'] ?? 'Keins';
    bool lidBestanden = data['lid_bestanden'] == true;
    bool zertifikatErhalten = data['zertifikat_erhalten'] == true;
    final kursTraegerC = TextEditingController(text: data['kurs_traeger'] ?? '');
    final kursTraegerAdresseC = TextEditingController(text: data['kurs_traeger_adresse'] ?? '');
    final kursTraegerTelC = TextEditingController(text: data['kurs_traeger_tel'] ?? '');
    final wiederholungTraegerC = TextEditingController(text: data['wiederholung_traeger'] ?? '');
    final wiederholungTraegerAdresseC = TextEditingController(text: data['wiederholung_traeger_adresse'] ?? '');
    final wiederholungBeginnC = TextEditingController(text: data['wiederholung_beginn'] ?? '');
    final wiederholungEndeC = TextEditingController(text: data['wiederholung_ende'] ?? '');
    final kursBeginnC = TextEditingController(text: data['kurs_beginn'] ?? '');
    final kursEndeC = TextEditingController(text: data['kurs_ende'] ?? '');

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === INTEGRATIONSKURS-ABFRAGE (vor Zuständige Behörde) ===
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.help_outline, color: Colors.teal.shade700, size: 22),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Integrationskurs-Abfrage',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Wurde der Mandant gefragt, ob er mit dem BAMF zu tun hatte?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      subtitle: const Text('Integrationskurs (600 UE Sprachkurs + 100 UE Orientierungskurs)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      value: mandantGefragt,
                      activeThumbColor: Colors.teal,
                      onChanged: (val) => setLocalState(() => mandantGefragt = val),
                    ),
                    if (mandantGefragt) ...[
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Hat der Mandant mit dem BAMF zu tun gehabt?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        subtitle: const Text('Integrationskurs besucht oder begonnen', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        value: hatMitBamfZuTun,
                        activeThumbColor: Colors.teal,
                        onChanged: (val) => setLocalState(() => hatMitBamfZuTun = val),
                      ),
                      if (hatMitBamfZuTun) ...[
                        const SizedBox(height: 12),
                        // Info-Box
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.info_outline, color: Colors.blue.shade600, size: 18),
                              const SizedBox(width: 8),
                              const Expanded(
                                child: Text(
                                  'Standard: 700 UE (600 Sprachkurs + 100 Orientierungskurs)\n'
                                  'Bei Nichtbestehen: bis zu 300 UE Wiederholung möglich\n'
                                  'Prüfungen: DTZ (Deutsch-Test für Zuwanderer) + Leben in Deutschland',
                                  style: TextStyle(fontSize: 11, color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Kursart
                        Text('Kursart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: kursart,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(value: 'Allgemeiner Integrationskurs', child: Text('Allgemeiner Integrationskurs (700 UE)')),
                                DropdownMenuItem(value: 'Intensivkurs', child: Text('Intensivkurs (400 UE)')),
                                DropdownMenuItem(value: 'Alphabetisierungskurs', child: Text('Alphabetisierungskurs (bis 1.300 UE)')),
                                DropdownMenuItem(value: 'Jugendintegrationskurs', child: Text('Jugendintegrationskurs (900 UE)')),
                              ],
                              onChanged: (val) => setLocalState(() => kursart = val!),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Kursträger Sprachkurs (600 UE)
                        Text('Kursträger — Sprachkurs (600 UE)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                        const SizedBox(height: 4),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: widget.apiService.getKursTraeger(),
                          builder: (ctx, snap) {
                            if (snap.hasError) return const Text('Fehler beim Laden');
                            if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                            final liste = snap.data!;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  decoration: BoxDecoration(
                                    border: Border.all(color: Colors.teal.shade300),
                                    borderRadius: BorderRadius.circular(8),
                                    color: Colors.white,
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: null,
                                      isExpanded: true,
                                      hint: const Text('Aus Datenbank auswählen...', style: TextStyle(fontSize: 12)),
                                      items: liste.map((kt) {
                                        final name = kt['name']?.toString() ?? '';
                                        final ort = kt['plz_ort']?.toString() ?? '';
                                        return DropdownMenuItem<String>(
                                          value: kt['id'].toString(),
                                          child: Text('$name${ort.isNotEmpty ? ' ($ort)' : ''}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                                        );
                                      }).toList(),
                                      onChanged: (val) {
                                        if (val == null) return;
                                        for (final kt in liste) {
                                          if (kt['id'].toString() == val) {
                                            setLocalState(() {
                                              kursTraegerC.text = kt['name']?.toString() ?? '';
                                              final str = kt['strasse']?.toString() ?? '';
                                              final plz = kt['plz_ort']?.toString() ?? '';
                                              kursTraegerAdresseC.text = '$str${plz.isNotEmpty ? ', $plz' : ''}';
                                              kursTraegerTelC.text = kt['telefon']?.toString() ?? '';
                                            });
                                            break;
                                          }
                                        }
                                      },
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                            );
                          },
                        ),
                        TextField(
                          controller: kursTraegerC,
                          decoration: InputDecoration(
                            hintText: 'Name der Bildungseinrichtung',
                            prefixIcon: const Icon(Icons.school, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: kursTraegerAdresseC,
                          decoration: InputDecoration(
                            hintText: 'Adresse',
                            prefixIcon: const Icon(Icons.location_on, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: kursTraegerTelC,
                          decoration: InputDecoration(
                            hintText: 'Telefon',
                            prefixIcon: const Icon(Icons.phone, size: 20),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Kursbeginn / Kursende
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Kursbeginn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: kursBeginnC,
                                    decoration: InputDecoration(
                                      hintText: 'TT.MM.JJJJ',
                                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      isDense: true,
                                    ),
                                    readOnly: true,
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2040),
                                        locale: const Locale('de'),
                                      );
                                      if (picked != null) {
                                        setLocalState(() => kursBeginnC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Kursende', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                  const SizedBox(height: 4),
                                  TextField(
                                    controller: kursEndeC,
                                    decoration: InputDecoration(
                                      hintText: 'TT.MM.JJJJ',
                                      prefixIcon: const Icon(Icons.event, size: 18),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      isDense: true,
                                    ),
                                    readOnly: true,
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2040),
                                        locale: const Locale('de'),
                                      );
                                      if (picked != null) {
                                        setLocalState(() => kursEndeC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}');
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        // Sprachkurs & Orientierungskurs Status
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Sprachkurs abgeschlossen (600 UE)', style: TextStyle(fontSize: 13)),
                                subtitle: const Text('6 Module: 3 Basis + 3 Aufbau', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                value: sprachkursAbgeschlossen,
                                activeThumbColor: Colors.green,
                                onChanged: (val) => setLocalState(() => sprachkursAbgeschlossen = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Orientierungskurs abgeschlossen (100 UE)', style: TextStyle(fontSize: 13)),
                                subtitle: const Text('Rechte, Pflichten, Kultur, Geschichte', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                value: orientierungskursAbgeschlossen,
                                activeThumbColor: Colors.green,
                                onChanged: (val) => setLocalState(() => orientierungskursAbgeschlossen = val),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Wiederholungsstunden
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Wiederholungsstunden (bis 300 UE extra)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                          subtitle: const Text('Bei Nichtbestehen der Prüfung', style: TextStyle(fontSize: 11, color: Colors.grey)),
                          value: wiederholungsstunden,
                          activeThumbColor: Colors.orange,
                          onChanged: (val) => setLocalState(() => wiederholungsstunden = val),
                        ),
                        if (wiederholungsstunden) ...[
                          TextField(
                            controller: wiederholungsstundenAnzahlC,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              hintText: 'Anzahl der Wiederholungsstunden (max. 300)',
                              prefixIcon: const Icon(Icons.replay, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text('Kursträger — Wiederholung (300 UE)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                          const SizedBox(height: 4),
                          FutureBuilder<List<Map<String, dynamic>>>(
                            future: widget.apiService.getKursTraeger(),
                            builder: (ctx, snap) {
                              if (!snap.hasData || snap.data!.isEmpty) return const SizedBox.shrink();
                              final liste = snap.data!;
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                    decoration: BoxDecoration(
                                      border: Border.all(color: Colors.orange.shade300),
                                      borderRadius: BorderRadius.circular(8),
                                      color: Colors.white,
                                    ),
                                    child: DropdownButtonHideUnderline(
                                      child: DropdownButton<String>(
                                        value: null,
                                        isExpanded: true,
                                        hint: const Text('Aus Datenbank auswählen...', style: TextStyle(fontSize: 12)),
                                        items: liste.map((kt) {
                                          final name = kt['name']?.toString() ?? '';
                                          final ort = kt['plz_ort']?.toString() ?? '';
                                          return DropdownMenuItem<String>(
                                            value: kt['id'].toString(),
                                            child: Text('$name${ort.isNotEmpty ? ' ($ort)' : ''}', style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val == null) return;
                                          for (final kt in liste) {
                                            if (kt['id'].toString() == val) {
                                              setLocalState(() {
                                                wiederholungTraegerC.text = kt['name']?.toString() ?? '';
                                                final str = kt['strasse']?.toString() ?? '';
                                                final plz = kt['plz_ort']?.toString() ?? '';
                                                wiederholungTraegerAdresseC.text = '$str${plz.isNotEmpty ? ', $plz' : ''}';
                                              });
                                              break;
                                            }
                                          }
                                        },
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              );
                            },
                          ),
                          TextField(
                            controller: wiederholungTraegerC,
                            decoration: InputDecoration(
                              hintText: 'Name der Bildungseinrichtung',
                              prefixIcon: const Icon(Icons.school, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: wiederholungTraegerAdresseC,
                            decoration: InputDecoration(
                              hintText: 'Adresse',
                              prefixIcon: const Icon(Icons.location_on, size: 20),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              isDense: true,
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Wiederholung Beginn / Ende
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Beginn', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: wiederholungBeginnC,
                                      decoration: InputDecoration(
                                        hintText: 'TT.MM.JJJJ',
                                        prefixIcon: const Icon(Icons.calendar_today, size: 18),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      readOnly: true,
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2040),
                                          locale: const Locale('de'),
                                        );
                                        if (picked != null) {
                                          setLocalState(() => wiederholungBeginnC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}');
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Ende', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                    const SizedBox(height: 4),
                                    TextField(
                                      controller: wiederholungEndeC,
                                      decoration: InputDecoration(
                                        hintText: 'TT.MM.JJJJ',
                                        prefixIcon: const Icon(Icons.event, size: 18),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                        isDense: true,
                                      ),
                                      readOnly: true,
                                      onTap: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate: DateTime.now(),
                                          firstDate: DateTime(2000),
                                          lastDate: DateTime(2040),
                                          locale: const Locale('de'),
                                        );
                                        if (picked != null) {
                                          setLocalState(() => wiederholungEndeC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}');
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        const SizedBox(height: 8),
                        // Prüfungen
                        Text('Prüfungen', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: [
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('DTZ bestanden (Deutsch-Test für Zuwanderer)', style: TextStyle(fontSize: 13)),
                                value: dtzBestanden,
                                activeThumbColor: Colors.green,
                                onChanged: (val) => setLocalState(() => dtzBestanden = val),
                              ),
                              if (dtzBestanden) ...[
                                const SizedBox(height: 8),
                                Text('DTZ-Ergebnis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  children: ['A2', 'B1'].map((level) {
                                    return ChoiceChip(
                                      label: Text(level),
                                      selected: dtzErgebnis == level,
                                      selectedColor: Colors.teal.shade200,
                                      onSelected: (sel) => setLocalState(() => dtzErgebnis = sel ? level : 'Keins'),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 8),
                              ],
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('„Leben in Deutschland" bestanden', style: TextStyle(fontSize: 13)),
                                subtitle: const Text('Abschlusstest Orientierungskurs', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                value: lidBestanden,
                                activeThumbColor: Colors.green,
                                onChanged: (val) => setLocalState(() => lidBestanden = val),
                              ),
                              const Divider(height: 1),
                              SwitchListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text('Zertifikat Integrationskurs erhalten', style: TextStyle(fontSize: 13)),
                                subtitle: const Text('Nur bei DTZ B1 + LiD bestanden', style: TextStyle(fontSize: 11, color: Colors.grey)),
                                value: zertifikatErhalten,
                                activeThumbColor: Colors.green,
                                onChanged: (val) => setLocalState(() => zertifikatErhalten = val),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              widget.dienststelleBuilder(type, dienststelleController),
              Text('Aktenzeichen (BAMF)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: aktenzeichenController,
                decoration: InputDecoration(
                  hintText: 'BAMF Aktenzeichen',
                  prefixIcon: const Icon(Icons.folder, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('Verfahrensstatus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: verfahrensstatus,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'Keins', child: Text('Kein Verfahren')),
                      DropdownMenuItem(value: 'Asylverfahren laufend', child: Text('Asylverfahren laufend')),
                      DropdownMenuItem(value: 'Anerkannt', child: Text('Anerkannt (Flüchtling/Asyl)')),
                      DropdownMenuItem(value: 'Subsidiärer Schutz', child: Text('Subsidiärer Schutz')),
                      DropdownMenuItem(value: 'Abschiebungsverbot', child: Text('Abschiebungsverbot')),
                      DropdownMenuItem(value: 'Abgelehnt', child: Text('Abgelehnt')),
                      DropdownMenuItem(value: 'Dublin-Verfahren', child: Text('Dublin-Verfahren')),
                      DropdownMenuItem(value: 'Klage anhängig', child: Text('Klage anhängig')),
                    ],
                    onChanged: (val) => setLocalState(() => verfahrensstatus = val!),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Integrationskurs-Nr.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: integrationskursNrController,
                decoration: InputDecoration(
                  hintText: 'z.B. IK-2026-12345',
                  prefixIcon: const Icon(Icons.school, size: 20),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              Text('Sprachniveau (erreicht)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(border: Border.all(color: Colors.grey.shade400), borderRadius: BorderRadius.circular(8)),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: sprachniveau,
                    isExpanded: true,
                    items: const [
                      DropdownMenuItem(value: 'Keins', child: Text('Keins')),
                      DropdownMenuItem(value: 'A1', child: Text('A1 - Anfänger')),
                      DropdownMenuItem(value: 'A2', child: Text('A2 - Grundlegende Kenntnisse')),
                      DropdownMenuItem(value: 'B1', child: Text('B1 - Fortgeschrittene Sprachverwendung')),
                      DropdownMenuItem(value: 'B2', child: Text('B2 - Selbstständige Sprachverwendung')),
                      DropdownMenuItem(value: 'C1', child: Text('C1 - Fachkundige Sprachkenntnisse')),
                      DropdownMenuItem(value: 'C2', child: Text('C2 - Annähernd muttersprachlich')),
                    ],
                    onChanged: (val) => setLocalState(() => sprachniveau = val!),
                  ),
                ),
              ),
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
                      'mandant_gefragt': mandantGefragt,
                      'hat_mit_bamf_zu_tun': hatMitBamfZuTun,
                      'integrationskurs_art': kursart,
                      'kurs_traeger': kursTraegerC.text.trim(),
                      'kurs_traeger_adresse': kursTraegerAdresseC.text.trim(),
                      'kurs_traeger_tel': kursTraegerTelC.text.trim(),
                      'wiederholung_traeger': wiederholungTraegerC.text.trim(),
                      'wiederholung_traeger_adresse': wiederholungTraegerAdresseC.text.trim(),
                      'wiederholung_beginn': wiederholungBeginnC.text.trim(),
                      'wiederholung_ende': wiederholungEndeC.text.trim(),
                      'kurs_beginn': kursBeginnC.text.trim(),
                      'kurs_ende': kursEndeC.text.trim(),
                      'sprachkurs_abgeschlossen': sprachkursAbgeschlossen,
                      'orientierungskurs_abgeschlossen': orientierungskursAbgeschlossen,
                      'wiederholungsstunden': wiederholungsstunden,
                      'wiederholungsstunden_anzahl': wiederholungsstundenAnzahlC.text.trim(),
                      'dtz_bestanden': dtzBestanden,
                      'dtz_ergebnis': dtzErgebnis,
                      'lid_bestanden': lidBestanden,
                      'zertifikat_erhalten': zertifikatErhalten,
                      'dienststelle': dienststelleController.text.trim(),
                      'aktenzeichen': aktenzeichenController.text.trim(),
                      'verfahrensstatus': verfahrensstatus,
                      'integrationskurs_nr': integrationskursNrController.text.trim(),
                      'sprachniveau': sprachniveau,
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
}
