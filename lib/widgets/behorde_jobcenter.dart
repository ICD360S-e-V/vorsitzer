import 'package:flutter/material.dart';

/// Jobcenter Behörde tab - extracted from behorde_tab_content.dart
class BehordeJobcenterContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final Widget Function({required String behoerdeType, required List<Map<String, dynamic>> antraege, required List<DropdownMenuItem<String>> artItems, required List<DropdownMenuItem<String>> statusItems, required void Function(List<Map<String, dynamic>>) onChanged, required BuildContext context}) antraegeBuilder;
  final Widget Function({required List<Map<String, dynamic>> meldungen, required void Function(List<Map<String, dynamic>>) onChanged, required BuildContext context}) meldungenBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> begutachtungen, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) begutachtungBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> termine, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) termineBuilder;
  final Future<void> Function(String type, String field, dynamic value) autoSaveField;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getTermineListe;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getBegutachtungen;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getMeldungen;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getAntraege;

  const BehordeJobcenterContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    required this.antraegeBuilder,
    required this.meldungenBuilder,
    required this.begutachtungBuilder,
    required this.termineBuilder,
    required this.autoSaveField,
    required this.getTermineListe,
    required this.getBegutachtungen,
    required this.getMeldungen,
    required this.getAntraege,
  });

  @override
  State<BehordeJobcenterContent> createState() => _BehordeJobcenterContentState();
}

class _BehordeJobcenterContentState extends State<BehordeJobcenterContent> {
  static const type = 'jobcenter';

  // Controllers managed with proper lifecycle
  late TextEditingController dienststelleController;
  late TextEditingController bgNummerController;
  late TextEditingController kundennummerController;
  late TextEditingController arbeitsvermittlerController;
  late TextEditingController arbeitsvermittlerTelController;
  late TextEditingController arbeitsvermittlerEmailController;
  late TextEditingController emailController;
  late TextEditingController passkeyAccessController;
  late TextEditingController bescheidVonController;
  late TextEditingController bescheidBisController;
  late TextEditingController bescheidBetragController;
  late TextEditingController regelsatzController;
  late TextEditingController kduController;
  late TextEditingController heizkostenController;
  late TextEditingController mehrbedarfController;
  late TextEditingController mehrbedarfGrundController;
  late TextEditingController egvVonController;
  late TextEditingController egvBisController;
  late TextEditingController egvPflichtenController;
  late TextEditingController massnahmeNameController;
  late TextEditingController massnahmeVonController;
  late TextEditingController massnahmeBisController;
  late TextEditingController massnahmeTraegerController;
  late TextEditingController sanktionNotizController;
  bool _controllersInitialized = false;

  void _initControllers(Map<String, dynamic> data) {
    dienststelleController = TextEditingController(text: data['dienststelle'] ?? '');
    bgNummerController = TextEditingController(text: data['bg_nummer'] ?? '');
    kundennummerController = TextEditingController(text: data['kundennummer'] ?? '');
    arbeitsvermittlerController = TextEditingController(text: data['arbeitsvermittler'] ?? '');
    arbeitsvermittlerTelController = TextEditingController(text: data['arbeitsvermittler_tel'] ?? '');
    arbeitsvermittlerEmailController = TextEditingController(text: data['arbeitsvermittler_email'] ?? '');
    emailController = TextEditingController(text: data['online_email'] ?? '');
    passkeyAccessController = TextEditingController(text: data['passkey_access'] ?? '');
    bescheidVonController = TextEditingController(text: data['bescheid_von'] ?? '');
    bescheidBisController = TextEditingController(text: data['bescheid_bis'] ?? '');
    bescheidBetragController = TextEditingController(text: data['bescheid_betrag'] ?? '');
    regelsatzController = TextEditingController(text: data['regelsatz'] ?? '');
    kduController = TextEditingController(text: data['kdu'] ?? '');
    heizkostenController = TextEditingController(text: data['heizkosten'] ?? '');
    mehrbedarfController = TextEditingController(text: data['mehrbedarf'] ?? '');
    mehrbedarfGrundController = TextEditingController(text: data['mehrbedarf_grund'] ?? '');
    egvVonController = TextEditingController(text: data['egv_von'] ?? '');
    egvBisController = TextEditingController(text: data['egv_bis'] ?? '');
    egvPflichtenController = TextEditingController(text: data['egv_pflichten'] ?? '');
    massnahmeNameController = TextEditingController(text: data['massnahme_name'] ?? '');
    massnahmeVonController = TextEditingController(text: data['massnahme_von'] ?? '');
    massnahmeBisController = TextEditingController(text: data['massnahme_bis'] ?? '');
    massnahmeTraegerController = TextEditingController(text: data['massnahme_traeger'] ?? '');
    sanktionNotizController = TextEditingController(text: data['sanktion_notiz'] ?? '');
    _controllersInitialized = true;
  }

  void _updateControllers(Map<String, dynamic> data) {
    _setIfDifferent(dienststelleController, data['dienststelle'] ?? '');
    _setIfDifferent(bgNummerController, data['bg_nummer'] ?? '');
    _setIfDifferent(kundennummerController, data['kundennummer'] ?? '');
    _setIfDifferent(arbeitsvermittlerController, data['arbeitsvermittler'] ?? '');
    _setIfDifferent(arbeitsvermittlerTelController, data['arbeitsvermittler_tel'] ?? '');
    _setIfDifferent(arbeitsvermittlerEmailController, data['arbeitsvermittler_email'] ?? '');
    _setIfDifferent(emailController, data['online_email'] ?? '');
    _setIfDifferent(passkeyAccessController, data['passkey_access'] ?? '');
    _setIfDifferent(bescheidVonController, data['bescheid_von'] ?? '');
    _setIfDifferent(bescheidBisController, data['bescheid_bis'] ?? '');
    _setIfDifferent(bescheidBetragController, data['bescheid_betrag'] ?? '');
    _setIfDifferent(regelsatzController, data['regelsatz'] ?? '');
    _setIfDifferent(kduController, data['kdu'] ?? '');
    _setIfDifferent(heizkostenController, data['heizkosten'] ?? '');
    _setIfDifferent(mehrbedarfController, data['mehrbedarf'] ?? '');
    _setIfDifferent(mehrbedarfGrundController, data['mehrbedarf_grund'] ?? '');
    _setIfDifferent(egvVonController, data['egv_von'] ?? '');
    _setIfDifferent(egvBisController, data['egv_bis'] ?? '');
    _setIfDifferent(egvPflichtenController, data['egv_pflichten'] ?? '');
    _setIfDifferent(massnahmeNameController, data['massnahme_name'] ?? '');
    _setIfDifferent(massnahmeVonController, data['massnahme_von'] ?? '');
    _setIfDifferent(massnahmeBisController, data['massnahme_bis'] ?? '');
    _setIfDifferent(massnahmeTraegerController, data['massnahme_traeger'] ?? '');
    _setIfDifferent(sanktionNotizController, data['sanktion_notiz'] ?? '');
  }

  void _setIfDifferent(TextEditingController controller, String value) {
    if (controller.text != value) {
      controller.text = value;
    }
  }

  @override
  void dispose() {
    if (_controllersInitialized) {
      dienststelleController.dispose();
      bgNummerController.dispose();
      kundennummerController.dispose();
      arbeitsvermittlerController.dispose();
      arbeitsvermittlerTelController.dispose();
      arbeitsvermittlerEmailController.dispose();
      emailController.dispose();
      passkeyAccessController.dispose();
      bescheidVonController.dispose();
      bescheidBisController.dispose();
      bescheidBetragController.dispose();
      regelsatzController.dispose();
      kduController.dispose();
      heizkostenController.dispose();
      mehrbedarfController.dispose();
      mehrbedarfGrundController.dispose();
      egvVonController.dispose();
      egvBisController.dispose();
      egvPflichtenController.dispose();
      massnahmeNameController.dispose();
      massnahmeVonController.dispose();
      massnahmeBisController.dispose();
      massnahmeTraegerController.dispose();
      sanktionNotizController.dispose();
    }
    super.dispose();
  }

  Widget _sectionHeader(IconData icon, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color))),
        Expanded(child: Divider(color: color.withValues(alpha: 0.3), thickness: 1)),
      ]),
    );
  }

  Widget _textField(String label, TextEditingController controller, {String hint = '', IconData icon = Icons.edit, int maxLines = 1}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: controller, maxLines: maxLines, decoration: InputDecoration(hintText: hint, prefixIcon: Icon(icon, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)), style: const TextStyle(fontSize: 14)),
    ]);
  }

  Widget _dateField(String label, TextEditingController controller, BuildContext ctx) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
      const SizedBox(height: 4),
      TextField(controller: controller, readOnly: true, decoration: InputDecoration(hintText: 'TT.MM.JJJJ', prefixIcon: const Icon(Icons.calendar_today, size: 20), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
        onTap: () async {
          final picked = await showDatePicker(context: ctx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2040), locale: const Locale('de'));
          if (picked != null) controller.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
        }),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (!false && widget.isLoading(type) != true) {
      widget.loadData(type);
    }
    // Pre-load Rentenversicherung for SV-Nummer auto-fill
    if (widget.getData('rentenversicherung').isEmpty && !widget.isLoading('rentenversicherung')) {
      widget.loadData('rentenversicherung');
    }
    // Pre-load Bundesagentur for shared Meldungen
    if (widget.getData('bundesagentur').isEmpty && !widget.isLoading('bundesagentur')) {
      widget.loadData('bundesagentur');
    }
    if (widget.isLoading(type) == true) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = widget.getData(type);
    final baData = widget.getData('bundesagentur');

    // Initialize or update controllers
    if (!_controllersInitialized) {
      _initControllers(data);
    } else {
      _updateControllers(data);
    }

    // Arbeitsuchendmeldung — shared from Bundesagentur
    List<Map<String, dynamic>> meldungen = widget.getMeldungen(baData);
    // Antraege (list with verlauf)
    List<Map<String, dynamic>> antraege = widget.getAntraege(data);
    List<Map<String, dynamic>> termine = widget.getTermineListe(data);
    List<Map<String, dynamic>> begutachtungen = widget.getBegutachtungen(data);

    bool hasOnlineAccount = data['has_online_account'] == true;
    bool hasPasskey = data['has_passkey'] == true;
    String massnahmeArt = data['massnahme_art'] ?? '';
    String massnahmeStatus = data['massnahme_status'] ?? '';
    bool hasSanktion = data['has_sanktion'] == true;
    bool hasEgv = data['has_egv'] == true;
    bool hasMassnahme = data['has_massnahme'] == true;

    return StatefulBuilder(
      builder: (context, setLocalState) {
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              widget.dienststelleBuilder(type, dienststelleController),

              // === STAMMDATEN ===
              _sectionHeader(Icons.badge, 'Stammdaten', Colors.indigo),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _textField('Kundennummer', kundennummerController, hint: 'z.B. 123D456789', icon: Icons.badge)),
                  const SizedBox(width: 12),
                  Expanded(child: _textField('BG-Nummer', bgNummerController, hint: 'z.B. 12345BG1234567', icon: Icons.numbers)),
                ],
              ),
              const SizedBox(height: 12),

              // Sachbearbeiter / Arbeitsvermittler
              _sectionHeader(Icons.support_agent, 'Sachbearbeiter / Arbeitsvermittler', Colors.teal),
              const SizedBox(height: 8),
              _textField('Arbeitsvermittler/in (pAp)', arbeitsvermittlerController, hint: 'Name des/der Arbeitsvermittler/in', icon: Icons.support_agent),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _textField('Telefon', arbeitsvermittlerTelController, hint: 'Durchwahl', icon: Icons.phone)),
                  const SizedBox(width: 12),
                  Expanded(child: _textField('E-Mail', arbeitsvermittlerEmailController, hint: 'E-Mail Sachbearbeiter', icon: Icons.email)),
                ],
              ),
              const SizedBox(height: 16),

              // === ARBEITSUCHENDMELDUNGEN (shared from Bundesagentur) ===
              widget.meldungenBuilder(
                meldungen: meldungen,
                onChanged: (updated) {
                  setLocalState(() => meldungen = updated);
                  widget.autoSaveField('bundesagentur', 'meldungen', updated);
                },
                context: context,
              ),
              const SizedBox(height: 16),

              // === BEWILLIGUNGSBESCHEID ===
              _sectionHeader(Icons.description, 'Bewilligungsbescheid', Colors.green.shade700),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _dateField('Bewilligungszeitraum von', bescheidVonController, context)),
                        const SizedBox(width: 12),
                        Expanded(child: _dateField('Bewilligungszeitraum bis', bescheidBisController, context)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _textField('Gesamtbetrag (EUR/Monat)', bescheidBetragController, hint: 'z.B. 563.00', icon: Icons.euro)),
                        const SizedBox(width: 12),
                        Expanded(child: _textField('Regelsatz (EUR)', regelsatzController, hint: 'z.B. 563', icon: Icons.account_balance_wallet)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _textField('KdU - Miete (EUR)', kduController, hint: 'Kosten der Unterkunft', icon: Icons.home)),
                        const SizedBox(width: 12),
                        Expanded(child: _textField('Heizkosten (EUR)', heizkostenController, hint: 'Heizkosten', icon: Icons.local_fire_department)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _textField('Mehrbedarf (EUR)', mehrbedarfController, hint: '0.00', icon: Icons.add_circle)),
                        const SizedBox(width: 12),
                        Expanded(child: _textField('Mehrbedarf Grund', mehrbedarfGrundController, hint: 'z.B. Schwangerschaft, Alleinerziehend', icon: Icons.info)),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === ANTRAEGE ===
              widget.antraegeBuilder(
                behoerdeType: type,
                antraege: antraege,
                artItems: const [
                  DropdownMenuItem(value: 'erstantrag', child: Text('Erstantrag', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'weiterbewilligung', child: Text('Weiterbewilligungsantrag (WBA)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'aenderungsantrag', child: Text('Änderungsantrag', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'mehrbedarf', child: Text('Antrag auf Mehrbedarf', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'erstausstattung', child: Text('Antrag auf Erstausstattung', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'umzugskosten', child: Text('Antrag auf Umzugskosten', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'but', child: Text('Bildung und Teilhabe (BuT)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'ueberpruefung', child: Text('Überprüfungsantrag (§44 SGB X)', style: TextStyle(fontSize: 13))),
                ],
                statusItems: const [
                  DropdownMenuItem(value: 'eingereicht', child: Text('Eingereicht', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'unterlagen_nachgefordert', child: Text('Unterlagen nachgefordert', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'bewilligt', child: Text('Bewilligt', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'teilweise_bewilligt', child: Text('Teilweise bewilligt', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'widerspruch', child: Text('Widerspruch eingelegt', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'klage', child: Text('Klage beim Sozialgericht', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'zurueckgezogen', child: Text('Zurückgezogen', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'verweigerung', child: Text('Verweigerung durch Mitglied', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (updated) {
                  setLocalState(() => antraege = updated);
                  widget.autoSaveField(type, 'antraege', updated);
                },
                context: context,
              ),
              const SizedBox(height: 16),

              // === EGV / KOOPERATIONSPLAN ===
              _sectionHeader(Icons.handshake, 'Eingliederungsvereinbarung / Kooperationsplan', Colors.purple.shade700),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.purple.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purple.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.handshake, size: 18, color: Colors.purple.shade700),
                        const SizedBox(width: 8),
                        Text('EGV / Kooperationsplan vorhanden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple.shade700)),
                        const Spacer(),
                        Switch(
                          value: hasEgv,
                          onChanged: (v) => setLocalState(() => hasEgv = v),
                          activeThumbColor: Colors.purple,
                        ),
                      ],
                    ),
                    if (hasEgv) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _dateField('Gültig von', egvVonController, context)),
                          const SizedBox(width: 12),
                          Expanded(child: _dateField('Gültig bis', egvBisController, context)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _textField('Pflichten / Eigenbemühungen', egvPflichtenController, hint: 'z.B. 5 Bewerbungen/Monat, Maßnahme besuchen...', icon: Icons.checklist, maxLines: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === MASSNAHME ===
              _sectionHeader(Icons.school, 'Maßnahme / Programm', Colors.cyan.shade700),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.cyan.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.cyan.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.school, size: 18, color: Colors.cyan.shade700),
                        const SizedBox(width: 8),
                        Text('Aktuelle Maßnahme', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.cyan.shade700)),
                        const Spacer(),
                        Switch(
                          value: hasMassnahme,
                          onChanged: (v) => setLocalState(() => hasMassnahme = v),
                          activeThumbColor: Colors.cyan.shade700,
                        ),
                      ],
                    ),
                    if (hasMassnahme) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Art der Maßnahme', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  initialValue: massnahmeArt.isEmpty ? null : massnahmeArt,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                                  items: const [
                                    DropdownMenuItem(value: 'bewerbungstraining', child: Text('Bewerbungstraining', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'aktivierung', child: Text('Aktivierungsmaßnahme (MAT)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'agh', child: Text('Arbeitsgelegenheit (1-Euro-Job)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'umschulung', child: Text('Umschulung', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'weiterbildung', child: Text('Weiterbildung (FbW)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'sprachkurs', child: Text('Sprachkurs / Integrationskurs', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'berufssprachkurs', child: Text('Berufssprachkurs (BSK)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'praktikum', child: Text('Praktikum (betrieblich)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'coaching', child: Text('Coaching / Beratung (AVGS)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'sonstiges', child: Text('Sonstiges', style: TextStyle(fontSize: 13))),
                                  ],
                                  onChanged: (v) => setLocalState(() => massnahmeArt = v ?? ''),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  initialValue: massnahmeStatus.isEmpty ? null : massnahmeStatus,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  hint: const Text('Status...', style: TextStyle(fontSize: 13)),
                                  items: const [
                                    DropdownMenuItem(value: 'zugewiesen', child: Text('📋 Zugewiesen', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'aktiv', child: Text('▶️ Teilnahme aktiv', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'abgeschlossen', child: Text('✅ Abgeschlossen', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'abgebrochen', child: Text('❌ Abgebrochen', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'nicht_angetreten', child: Text('⚠️ Nicht angetreten', style: TextStyle(fontSize: 13))),
                                  ],
                                  onChanged: (v) => setLocalState(() => massnahmeStatus = v ?? ''),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _textField('Bezeichnung', massnahmeNameController, hint: 'Name der Maßnahme', icon: Icons.label),
                      const SizedBox(height: 8),
                      _textField('Maßnahmeträger', massnahmeTraegerController, hint: 'z.B. DAA, bfz, TÜV Rheinland...', icon: Icons.business),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _dateField('Beginn', massnahmeVonController, context)),
                          const SizedBox(width: 12),
                          Expanded(child: _dateField('Ende', massnahmeBisController, context)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === SANKTION ===
              _sectionHeader(Icons.warning_amber, 'Sanktionen / Leistungsminderung', Colors.red.shade700),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber, size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Text('Sanktion aktiv', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700)),
                        const Spacer(),
                        Switch(
                          value: hasSanktion,
                          onChanged: (v) => setLocalState(() => hasSanktion = v),
                          activeThumbColor: Colors.red,
                        ),
                      ],
                    ),
                    if (hasSanktion) ...[
                      const SizedBox(height: 12),
                      _textField('Details zur Sanktion', sanktionNotizController, hint: 'Grund, Minderung %, Zeitraum, Widerspruch...', icon: Icons.notes, maxLines: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === ONLINE-KONTO ===
              Container(
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
                        Icon(Icons.cloud, size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text('Online-Konto (jobcenter.digital)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700)),
                        const Spacer(),
                        Switch(
                          value: hasOnlineAccount,
                          onChanged: (v) => setLocalState(() => hasOnlineAccount = v),
                          activeThumbColor: Colors.blue,
                        ),
                      ],
                    ),
                    if (hasOnlineAccount) ...[
                      const SizedBox(height: 12),
                      _textField('E-Mail', emailController, hint: 'E-Mail des Online-Kontos', icon: Icons.email),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.key, size: 18, color: Colors.orange.shade700),
                                const SizedBox(width: 8),
                                Text('Passkey aktiviert', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade700)),
                                const Spacer(),
                                Switch(
                                  value: hasPasskey,
                                  onChanged: (v) => setLocalState(() => hasPasskey = v),
                                  activeThumbColor: Colors.orange,
                                ),
                              ],
                            ),
                            if (hasPasskey) ...[
                              const SizedBox(height: 12),
                              _textField('Wer hat Zugang zum Passkey?', passkeyAccessController, hint: 'Name / Rolle der Person mit Zugang', icon: Icons.person_pin),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // === MEDIZINISCHE BEGUTACHTUNG ===
              widget.begutachtungBuilder(
                behoerdeType: type,
                behoerdeLabel: 'Jobcenter',
                begutachtungen: begutachtungen,
                data: data,
                onChanged: (updated) {
                  setLocalState(() => begutachtungen = updated);
                  widget.autoSaveField(type, 'begutachtungen', updated);
                },
                setLocalState: setLocalState,
              ),

              // === TERMINE ===
              widget.termineBuilder(
                behoerdeType: type,
                behoerdeLabel: 'Jobcenter',
                termine: termine,
                data: data,
                onChanged: (updated) {
                  setLocalState(() => termine = updated);
                  widget.autoSaveField(type, 'termine', updated);
                },
                setLocalState: setLocalState,
              ),
              const SizedBox(height: 24),

              // Save button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) == true ? null : () {
                    final saveData = {
                      'dienststelle': dienststelleController.text.trim(),
                      'kundennummer': kundennummerController.text.trim(),
                      'bg_nummer': bgNummerController.text.trim(),
                      'arbeitsvermittler_id': data['arbeitsvermittler_id'],
                      'arbeitsvermittler': arbeitsvermittlerController.text.trim(),
                      'arbeitsvermittler_tel': arbeitsvermittlerTelController.text.trim(),
                      'arbeitsvermittler_email': arbeitsvermittlerEmailController.text.trim(),
                      'bescheid_von': bescheidVonController.text.trim(),
                      'bescheid_bis': bescheidBisController.text.trim(),
                      'bescheid_betrag': bescheidBetragController.text.trim(),
                      'regelsatz': regelsatzController.text.trim(),
                      'kdu': kduController.text.trim(),
                      'heizkosten': heizkostenController.text.trim(),
                      'mehrbedarf': mehrbedarfController.text.trim(),
                      'mehrbedarf_grund': mehrbedarfGrundController.text.trim(),
                      'antraege': antraege,
                      'termine': termine,
                      'begutachtungen': begutachtungen,
                      'has_egv': hasEgv,
                      'egv_von': egvVonController.text.trim(),
                      'egv_bis': egvBisController.text.trim(),
                      'egv_pflichten': egvPflichtenController.text.trim(),
                      'has_massnahme': hasMassnahme,
                      'massnahme_art': massnahmeArt,
                      'massnahme_status': massnahmeStatus,
                      'massnahme_name': massnahmeNameController.text.trim(),
                      'massnahme_traeger': massnahmeTraegerController.text.trim(),
                      'massnahme_von': massnahmeVonController.text.trim(),
                      'massnahme_bis': massnahmeBisController.text.trim(),
                      'has_sanktion': hasSanktion,
                      'sanktion_notiz': sanktionNotizController.text.trim(),
                      'has_online_account': hasOnlineAccount,
                      'online_email': emailController.text.trim(),
                      'has_passkey': hasPasskey,
                      'passkey_access': passkeyAccessController.text.trim(),
                    };
                    widget.saveData(type, saveData);
                  },
                  icon: widget.isSaving(type) == true
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save, size: 18),
                  label: const Text('Speichern'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

}
