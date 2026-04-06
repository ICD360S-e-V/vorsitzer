import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:uuid/uuid.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';

class BehordeArbeitsagenturContent extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final Widget Function({required String type, required TextEditingController arbeitsvermittlerController, required TextEditingController arbeitsvermittlerTelController, required TextEditingController arbeitsvermittlerEmailController, required Map<String, dynamic> data, required StateSetter setLocalState}) arbeitsvermittlerBuilder;
  final Widget Function({required String behoerdeType, required List<Map<String, dynamic>> antraege, required List<DropdownMenuItem<String>> artItems, required List<DropdownMenuItem<String>> statusItems, required void Function(List<Map<String, dynamic>>) onChanged, required BuildContext context}) antraegeBuilder;
  final Widget Function({required List<Map<String, dynamic>> meldungen, required void Function(List<Map<String, dynamic>>) onChanged, required BuildContext context}) meldungenBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> begutachtungen, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) begutachtungBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> termine, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) termineBuilder;
  final Future<void> Function(String type, String field, dynamic value) autoSaveField;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getTermineListe;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getBegutachtungen;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getMeldungen;
  final List<Map<String, dynamic>> Function(Map<String, dynamic> data) getAntraege;

  const BehordeArbeitsagenturContent({
    super.key,
    required this.apiService,
    required this.userId,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    required this.arbeitsvermittlerBuilder,
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
  State<BehordeArbeitsagenturContent> createState() => _State();
}

class _State extends State<BehordeArbeitsagenturContent> {
  static const type = 'bundesagentur';

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
    if (widget.isLoading(type) == true) {
      return const Center(child: CircularProgressIndicator());
    }

    final data = widget.getData(type);
    final dienststelleController = TextEditingController(text: data['dienststelle'] ?? '');
    final kundennummerController = TextEditingController(text: data['kundennummer'] ?? '');
    final arbeitsvermittlerController = TextEditingController(text: data['arbeitsvermittler'] ?? '');
    final arbeitsvermittlerTelController = TextEditingController(text: data['arbeitsvermittler_tel'] ?? '');
    final arbeitsvermittlerEmailController = TextEditingController(text: data['arbeitsvermittler_email'] ?? '');
    final emailController = TextEditingController(text: data['online_email'] ?? '');
    final passkeyAccessController = TextEditingController(text: data['passkey_access'] ?? '');
    // Arbeitslosmeldung
    final arbeitssuchendDatumController = TextEditingController(text: data['arbeitssuchend_datum'] ?? '');
    final arbeitslosDatumController = TextEditingController(text: data['arbeitslos_datum'] ?? '');
    final letzterArbeitstagController = TextEditingController(text: data['letzter_arbeitstag'] ?? '');
    // Arbeitsuchendmeldungen (list with verlauf)
    List<Map<String, dynamic>> meldungen = widget.getMeldungen(data);
    // Bewilligungsbescheid ALG I
    final bescheidVonController = TextEditingController(text: data['bescheid_von'] ?? '');
    final bescheidBisController = TextEditingController(text: data['bescheid_bis'] ?? '');
    final leistungssatzController = TextEditingController(text: data['leistungssatz_betrag'] ?? '');
    final bemessungsentgeltController = TextEditingController(text: data['bemessungsentgelt'] ?? '');
    final anspruchsdauerController = TextEditingController(text: data['anspruchsdauer'] ?? '');
    final restanspruchController = TextEditingController(text: data['restanspruch'] ?? '');
    // Sperrzeit
    final sperrzeitVonController = TextEditingController(text: data['sperrzeit_von'] ?? '');
    final sperrzeitBisController = TextEditingController(text: data['sperrzeit_bis'] ?? '');
    final sperrzeitNotizController = TextEditingController(text: data['sperrzeit_notiz'] ?? '');
    // EGV
    final egvVonController = TextEditingController(text: data['egv_von'] ?? '');
    final egvBisController = TextEditingController(text: data['egv_bis'] ?? '');
    final egvPflichtenController = TextEditingController(text: data['egv_pflichten'] ?? '');
    // Bildungsgutschein
    final bgsNameController = TextEditingController(text: data['bgs_name'] ?? '');
    final bgsTraegerController = TextEditingController(text: data['bgs_traeger'] ?? '');
    final bgsVonController = TextEditingController(text: data['bgs_von'] ?? '');
    final bgsBisController = TextEditingController(text: data['bgs_bis'] ?? '');
    // Antraege (list with verlauf)
    List<Map<String, dynamic>> antraege = widget.getAntraege(data);
    List<Map<String, dynamic>> termine = widget.getTermineListe(data);
    List<Map<String, dynamic>> begutachtungen = widget.getBegutachtungen(data);
    bool hasOnlineAccount = data['has_online_account'] == true;
    bool hasPasskey = data['has_passkey'] == true;
    String kuendigungsart = data['kuendigungsart'] ?? '';
    String leistungssatzTyp = data['leistungssatz_typ'] ?? '';
    bool hasSperrzeit = data['has_sperrzeit'] == true;
    String sperrzeitTyp = data['sperrzeit_typ'] ?? '';
    String sperrzeitWiderspruch = data['sperrzeit_widerspruch'] ?? '';
    bool hasEgv = data['has_egv'] == true;
    bool hasBgs = data['has_bgs'] == true;
    String bgsTyp = data['bgs_typ'] ?? '';
    String bgsStatus = data['bgs_status'] ?? '';

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
              _textField('Kundennummer', kundennummerController, hint: 'z.B. 123A456789 (10-stellig)', icon: Icons.badge),
              const SizedBox(height: 12),

              // Sachbearbeiter / Arbeitsvermittler
              widget.arbeitsvermittlerBuilder(
                type: type,
                data: data,
                arbeitsvermittlerController: arbeitsvermittlerController,
                arbeitsvermittlerTelController: arbeitsvermittlerTelController,
                arbeitsvermittlerEmailController: arbeitsvermittlerEmailController,
                setLocalState: setLocalState,
              ),
              const SizedBox(height: 16),

              // === ARBEITSSUCHENDMELDUNG ===
              _sectionHeader(Icons.person_off, 'Arbeitssuchendmeldung', Colors.brown),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.brown.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.brown.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: _dateField('Arbeitssuchend gemeldet am', arbeitssuchendDatumController, context)),
                        const SizedBox(width: 12),
                        Expanded(child: _dateField('Arbeitslos gemeldet am', arbeitslosDatumController, context)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _dateField('Letzter Arbeitstag', letzterArbeitstagController, context)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Kundigungsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: kuendigungsart.isEmpty ? null : kuendigungsart,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                hint: const Text('Auswahlen...', style: TextStyle(fontSize: 13)),
                                items: const [
                                  DropdownMenuItem(value: 'arbeitgeber', child: Text('Arbeitgeberkundigung', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'eigen', child: Text('Eigenkundigung', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'aufhebung', child: Text('Aufhebungsvertrag', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'befristung', child: Text('Befristung ausgelaufen', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: 'insolvenz', child: Text('Insolvenz', style: TextStyle(fontSize: 13))),
                                ],
                                onChanged: (v) => setLocalState(() => kuendigungsart = v ?? ''),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === ARBEITSUCHENDMELDUNGEN ===
              widget.meldungenBuilder(
                meldungen: meldungen,
                onChanged: (updated) {
                  setLocalState(() => meldungen = updated);
                  widget.autoSaveField(type, 'meldungen', updated);
                },
                context: context,
              ),
              const SizedBox(height: 16),

              // === BEWILLIGUNGSBESCHEID ALG I ===
              _sectionHeader(Icons.description, 'Bewilligungsbescheid (ALG I)', Colors.green.shade700),
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
                        Expanded(child: _textField('Taglicher Leistungssatz (EUR)', leistungssatzController, hint: 'z.B. 38.50', icon: Icons.euro)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Leistungssatz', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                              const SizedBox(height: 4),
                              DropdownButtonFormField<String>(
                                initialValue: leistungssatzTyp.isEmpty ? null : leistungssatzTyp,
                                isExpanded: true,
                                decoration: InputDecoration(
                                  isDense: true,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                hint: const Text('Auswahlen...', style: TextStyle(fontSize: 13)),
                                items: const [
                                  DropdownMenuItem(value: '60', child: Text('60% (allgemein)', style: TextStyle(fontSize: 13))),
                                  DropdownMenuItem(value: '67', child: Text('67% (mit Kind)', style: TextStyle(fontSize: 13))),
                                ],
                                onChanged: (v) => setLocalState(() => leistungssatzTyp = v ?? ''),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _textField('Bemessungsentgelt (EUR/Tag)', bemessungsentgeltController, hint: 'Tagliches Bemessungsentgelt', icon: Icons.account_balance_wallet),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _textField('Anspruchsdauer (Tage)', anspruchsdauerController, hint: 'z.B. 360', icon: Icons.timer)),
                        const SizedBox(width: 12),
                        Expanded(child: _textField('Restanspruch (Tage)', restanspruchController, hint: 'Verbleibende Tage', icon: Icons.hourglass_bottom)),
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
                  DropdownMenuItem(value: 'erstantrag', child: Text('Erstantrag ALG I', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'weiterbewilligung', child: Text('Weiterbewilligungsantrag', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'wiederholung', child: Text('Wiederholungsantrag', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'insolvenzantrag', child: Text('Insolvenzantrag', style: TextStyle(fontSize: 13))),
                ],
                statusItems: const [
                  DropdownMenuItem(value: 'neu', child: Text('Neu', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'geplant', child: Text('Geplant', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'eingereicht', child: Text('Eingereicht', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'in_bearbeitung', child: Text('In Bearbeitung', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'unterlagen_fehlen', child: Text('Unterlagen nachgefordert', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'bewilligt', child: Text('Bewilligt', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: 'abgelehnt', child: Text('Abgelehnt', style: TextStyle(fontSize: 13))),
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

              // === SPERRZEIT ===
              _sectionHeader(Icons.block, 'Sperrzeit / Sperrzeitbescheid', Colors.red.shade700),
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
                        Icon(Icons.block, size: 18, color: Colors.red.shade700),
                        const SizedBox(width: 8),
                        Text('Sperrzeit vorhanden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.red.shade700)),
                        const Spacer(),
                        Switch(
                          value: hasSperrzeit,
                          onChanged: (v) => setLocalState(() => hasSperrzeit = v),
                          activeThumbColor: Colors.red,
                        ),
                      ],
                    ),
                    if (hasSperrzeit) ...[
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Sperrzeit-Grund', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: sperrzeitTyp.isEmpty ? null : sperrzeitTyp,
                            isExpanded: true,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                            items: const [
                              DropdownMenuItem(value: 'eigenkuendigung', child: Text('Eigenkündigung (12 Wochen)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'aufhebungsvertrag', child: Text('Aufhebungsvertrag (12 Wochen)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'arbeitsablehnung', child: Text('Arbeitsablehnung (3-12 Wochen)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'meldeversaeumnis', child: Text('Meldeversäumnis (1 Woche)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'massnahmeabbruch', child: Text('Maßnahmeabbruch (3-12 Wochen)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'verspaetete_meldung', child: Text('Verspätete Meldung (1 Woche)', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'eigenbemuehungen', child: Text('Unzureichende Eigenbemühungen (2 Wochen)', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (v) => setLocalState(() => sperrzeitTyp = v ?? ''),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _dateField('Sperrzeit von', sperrzeitVonController, context)),
                          const SizedBox(width: 12),
                          Expanded(child: _dateField('Sperrzeit bis', sperrzeitBisController, context)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Widerspruch', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                          const SizedBox(height: 4),
                          DropdownButtonFormField<String>(
                            initialValue: sperrzeitWiderspruch.isEmpty ? null : sperrzeitWiderspruch,
                            isExpanded: true,
                            decoration: InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            ),
                            hint: const Text('Kein Widerspruch', style: TextStyle(fontSize: 13)),
                            items: const [
                              DropdownMenuItem(value: 'kein', child: Text('Kein Widerspruch', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'eingelegt', child: Text('⚖️ Widerspruch eingelegt', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'stattgegeben', child: Text('✅ Stattgegeben', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'abgelehnt', child: Text('❌ Zurückgewiesen', style: TextStyle(fontSize: 13))),
                              DropdownMenuItem(value: 'klage', child: Text('🏛️ Klage beim Sozialgericht', style: TextStyle(fontSize: 13))),
                            ],
                            onChanged: (v) => setLocalState(() => sperrzeitWiderspruch = v ?? ''),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _textField('Notizen zur Sperrzeit', sperrzeitNotizController, hint: 'Details, Begründung, Fristen...', icon: Icons.notes, maxLines: 2),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === EGV ===
              _sectionHeader(Icons.handshake, 'Eingliederungsvereinbarung (EGV)', Colors.purple.shade700),
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
                        Text('EGV vorhanden', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.purple.shade700)),
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
                      _textField('Pflichten / Eigenbemühungen', egvPflichtenController, hint: 'z.B. 10 Bewerbungen/Monat...', icon: Icons.checklist, maxLines: 3),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // === BILDUNGSGUTSCHEIN / AVGS ===
              _sectionHeader(Icons.school, 'Bildungsgutschein / AVGS', Colors.cyan.shade700),
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
                        Text('Bildungsgutschein / AVGS', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.cyan.shade700)),
                        const Spacer(),
                        Switch(
                          value: hasBgs,
                          onChanged: (v) => setLocalState(() => hasBgs = v),
                          activeThumbColor: Colors.cyan.shade700,
                        ),
                      ],
                    ),
                    if (hasBgs) ...[
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Art', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                const SizedBox(height: 4),
                                DropdownButtonFormField<String>(
                                  initialValue: bgsTyp.isEmpty ? null : bgsTyp,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  hint: const Text('Auswählen...', style: TextStyle(fontSize: 13)),
                                  items: const [
                                    DropdownMenuItem(value: 'bildungsgutschein', child: Text('Bildungsgutschein (BGS)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'avgs_mat', child: Text('AVGS MAT (Coaching)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'avgs_mpav', child: Text('AVGS MPAV (Vermittlung)', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'avgs_mag', child: Text('AVGS MAG (Praktikum)', style: TextStyle(fontSize: 13))),
                                  ],
                                  onChanged: (v) => setLocalState(() => bgsTyp = v ?? ''),
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
                                  initialValue: bgsStatus.isEmpty ? null : bgsStatus,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  hint: const Text('Status...', style: TextStyle(fontSize: 13)),
                                  items: const [
                                    DropdownMenuItem(value: 'beantragt', child: Text('📤 Beantragt', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'bewilligt', child: Text('✅ Bewilligt', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'abgelehnt', child: Text('❌ Abgelehnt', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'laufend', child: Text('▶️ Maßnahme laufend', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'abgeschlossen', child: Text('🎓 Abgeschlossen', style: TextStyle(fontSize: 13))),
                                    DropdownMenuItem(value: 'abgebrochen', child: Text('⚠️ Abgebrochen', style: TextStyle(fontSize: 13))),
                                  ],
                                  onChanged: (v) => setLocalState(() => bgsStatus = v ?? ''),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _textField('Maßnahme / Qualifikation', bgsNameController, hint: 'Name der Weiterbildung', icon: Icons.label),
                      const SizedBox(height: 8),
                      _textField('Bildungsträger', bgsTraegerController, hint: 'z.B. WBS, GFN, Comcave...', icon: Icons.business),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(child: _dateField('Beginn', bgsVonController, context)),
                          const SizedBox(width: 12),
                          Expanded(child: _dateField('Ende', bgsBisController, context)),
                        ],
                      ),
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
                        Text('Online-Konto (arbeitsagentur.de)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade700)),
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
                behoerdeLabel: 'Arbeitsagentur',
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
                behoerdeLabel: 'Arbeitsagentur',
                termine: termine,
                data: data,
                onChanged: (updated) {
                  setLocalState(() => termine = updated);
                  widget.autoSaveField(type, 'termine', updated);
                },
                setLocalState: setLocalState,
              ),
              const SizedBox(height: 16),

              // === KORRESPONDENZ ===
              _AAKorrespondenzSection(apiService: widget.apiService, userId: widget.userId),

              const SizedBox(height: 24),

              // Save button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) == true ? null : () {
                    final saveData = {
                      'dienststelle': dienststelleController.text.trim(),
                      'kundennummer': kundennummerController.text.trim(),
                      'arbeitsvermittler_id': data['arbeitsvermittler_id'],
                      'arbeitsvermittler': arbeitsvermittlerController.text.trim(),
                      'arbeitsvermittler_tel': arbeitsvermittlerTelController.text.trim(),
                      'arbeitsvermittler_email': arbeitsvermittlerEmailController.text.trim(),
                      'arbeitssuchend_datum': arbeitssuchendDatumController.text.trim(),
                      'arbeitslos_datum': arbeitslosDatumController.text.trim(),
                      'letzter_arbeitstag': letzterArbeitstagController.text.trim(),
                      'meldungen': meldungen,
                      'termine': termine,
                      'begutachtungen': begutachtungen,
                      'kuendigungsart': kuendigungsart,
                      'bescheid_von': bescheidVonController.text.trim(),
                      'bescheid_bis': bescheidBisController.text.trim(),
                      'leistungssatz_betrag': leistungssatzController.text.trim(),
                      'leistungssatz_typ': leistungssatzTyp,
                      'bemessungsentgelt': bemessungsentgeltController.text.trim(),
                      'anspruchsdauer': anspruchsdauerController.text.trim(),
                      'restanspruch': restanspruchController.text.trim(),
                      'antraege': antraege,
                      'has_sperrzeit': hasSperrzeit,
                      'sperrzeit_typ': sperrzeitTyp,
                      'sperrzeit_von': sperrzeitVonController.text.trim(),
                      'sperrzeit_bis': sperrzeitBisController.text.trim(),
                      'sperrzeit_widerspruch': sperrzeitWiderspruch,
                      'sperrzeit_notiz': sperrzeitNotizController.text.trim(),
                      'has_egv': hasEgv,
                      'egv_von': egvVonController.text.trim(),
                      'egv_bis': egvBisController.text.trim(),
                      'egv_pflichten': egvPflichtenController.text.trim(),
                      'has_bgs': hasBgs,
                      'bgs_typ': bgsTyp,
                      'bgs_status': bgsStatus,
                      'bgs_name': bgsNameController.text.trim(),
                      'bgs_traeger': bgsTraegerController.text.trim(),
                      'bgs_von': bgsVonController.text.trim(),
                      'bgs_bis': bgsBisController.text.trim(),
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

// ═══════════════════════════════════════════════════════
// ARBEITSAGENTUR KORRESPONDENZ (Eingang / Ausgang)
// ═══════════════════════════════════════════════════════
class _AAKorrespondenzSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _AAKorrespondenzSection({required this.apiService, required this.userId});
  @override
  State<_AAKorrespondenzSection> createState() => _AAKorrespondenzState();
}

class _AAKorrespondenzState extends State<_AAKorrespondenzSection> {
  List<Map<String, dynamic>> _docs = [];
  bool _isLoading = true;
  String _filter = 'alle';

  @override
  void initState() {
    super.initState();
    _loadDocs();
  }

  Future<void> _loadDocs() async {
    setState(() => _isLoading = true);
    try {
      final res = await widget.apiService.getAAKorrespondenz(widget.userId);
      if (res['success'] == true && res['data'] is List) {
        _docs = (res['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[AAKorr] load error: $e');
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _addKorrespondenz(String richtung) async {
    final datumErstelltC = TextEditingController();
    final datumKundeC = TextEditingController();
    final datumWirC = TextEditingController(text: DateFormat('dd.MM.yyyy').format(DateTime.now()));
    final betreffC = TextEditingController();
    final notizC = TextEditingController();
    String methode = richtung == 'eingang' ? 'post' : 'email';
    List<PlatformFile> selectedFiles = [];

    final confirmed = await showDialog<bool>(context: context, builder: (dlgCtx) => StatefulBuilder(
      builder: (dlgCtx, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18, color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(richtung == 'eingang' ? 'Eingang hinzufügen' : 'Ausgang hinzufügen', style: const TextStyle(fontSize: 14)),
        ]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final m in [('email', 'E-Mail', Icons.email), ('post', 'Post', Icons.mail), ('telefon', 'Telefon', Icons.phone), ('fax', 'Fax', Icons.fax), ('online', 'Online-Portal', Icons.language)])
              ChoiceChip(
                label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(m.$3, size: 13, color: methode == m.$1 ? Colors.white : Colors.grey.shade700), const SizedBox(width: 4), Text(m.$2, style: TextStyle(fontSize: 10, color: methode == m.$1 ? Colors.white : Colors.grey.shade700))]),
                selected: methode == m.$1, selectedColor: Colors.indigo.shade600,
                onSelected: (_) => setDlg(() => methode = m.$1),
              ),
          ]),
          const SizedBox(height: 12),
          TextFormField(controller: datumErstelltC, readOnly: true, decoration: InputDecoration(labelText: 'Datum Bescheid erstellt', prefixIcon: Icon(Icons.edit_calendar, size: 16, color: Colors.blue.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) setDlg(() => datumErstelltC.text = DateFormat('dd.MM.yyyy').format(p));
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: datumKundeC, readOnly: true, decoration: InputDecoration(labelText: 'Datum Kunde erhalten', prefixIcon: Icon(Icons.person, size: 16, color: Colors.orange.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) setDlg(() => datumKundeC.text = DateFormat('dd.MM.yyyy').format(p));
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: datumWirC, readOnly: true, decoration: InputDecoration(labelText: 'Datum wir erhalten', prefixIcon: Icon(Icons.business, size: 16, color: Colors.teal.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async {
              final p = await showDatePicker(context: dlgCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de'));
              if (p != null) setDlg(() => datumWirC.text = DateFormat('dd.MM.yyyy').format(p));
            }))),
          const SizedBox(height: 10),
          TextFormField(controller: betreffC, decoration: InputDecoration(labelText: 'Betreff / Titel *', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          TextFormField(controller: notizC, maxLines: 2, decoration: InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: Icon(Icons.attach_file, size: 16, color: Colors.teal.shade600),
            label: Text(selectedFiles.isEmpty ? 'Dokumente anhängen (max. 20)' : '${selectedFiles.length} Datei${selectedFiles.length > 1 ? 'en' : ''} ausgewählt', style: TextStyle(fontSize: 12, color: Colors.teal.shade700)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.teal.shade300)),
            onPressed: () async {
              final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
              if (result != null) {
                setDlg(() {
                  selectedFiles.addAll(result.files);
                  if (selectedFiles.length > 20) selectedFiles = selectedFiles.sublist(0, 20);
                });
              }
            },
          ),
          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...selectedFiles.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(children: [
                Icon(Icons.description, size: 14, color: Colors.grey.shade500),
                const SizedBox(width: 6),
                Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                Text('${(e.value.size / 1024).toStringAsFixed(0)} KB', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => setDlg(() => selectedFiles.removeAt(e.key))),
              ]),
            )),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx, false), child: const Text('Abbrechen')),
          FilledButton(onPressed: () {
            if (betreffC.text.trim().isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bitte Betreff angeben'), backgroundColor: Colors.orange));
              return;
            }
            Navigator.pop(dlgCtx, true);
          }, child: const Text('Speichern')),
        ],
      ),
    ));

    if (confirmed != true) return;

    try {
      int ok = 0, fail = 0;
      final gId = const Uuid().v4();
      if (selectedFiles.isEmpty) {
        final res = await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: richtung, titel: betreffC.text.trim(), datum: datumErstelltC.text, datumErstellt: datumErstelltC.text, datumKundeErhalten: datumKundeC.text, datumWirErhalten: datumWirC.text, betreff: betreffC.text.trim(), notiz: notizC.text.trim(), methode: methode, gruppeId: gId);
        if (res['success'] == true) { ok++; } else { fail++; }
      } else {
        for (final f in selectedFiles) {
          if (f.path == null) continue;
          final res = await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: richtung, titel: betreffC.text.trim(), datum: datumErstelltC.text, datumErstellt: datumErstelltC.text, datumKundeErhalten: datumKundeC.text, datumWirErhalten: datumWirC.text, betreff: betreffC.text.trim(), notiz: notizC.text.trim(), methode: methode, gruppeId: gId, filePath: f.path!, fileName: f.name);
          if (res['success'] == true) { ok++; } else { fail++; }
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fail > 0 ? '$ok gespeichert, $fail fehlgeschlagen' : '${ok > 1 ? '$ok Dokumente' : 'Korrespondenz'} gespeichert'), backgroundColor: fail > 0 ? Colors.orange : Colors.green));
      }
      _loadDocs();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  void _showKorrDetailDialog(List<Map<String, dynamic>> docGroup, Map<String, dynamic> first, List<Map<String, dynamic>> files) {
    final isEingang = first['richtung'] == 'eingang';
    final color = isEingang ? Colors.green : Colors.blue;
    final gruppeId = first['gruppe_id']?.toString();
    const mLabels = {'email': 'E-Mail', 'post': 'Post', 'telefon': 'Telefon', 'fax': 'Fax', 'online': 'Portal'};
    final m = first['methode']?.toString() ?? 'post';
    // Search date fields on any record in group (not just first)
    String dErstellt = '', dKunde = '', dWir = '';
    for (final d in docGroup) {
      if (dErstellt.isEmpty && (d['datum_erstellt']?.toString() ?? '').isNotEmpty) dErstellt = d['datum_erstellt'].toString();
      if (dKunde.isEmpty && (d['datum_kunde_erhalten']?.toString() ?? '').isNotEmpty) dKunde = d['datum_kunde_erhalten'].toString();
      if (dWir.isEmpty && (d['datum_wir_erhalten']?.toString() ?? '').isNotEmpty) dWir = d['datum_wir_erhalten'].toString();
    }
    String wFrist = '';
    if (dKunde.isNotEmpty) { try { DateTime k; if (dKunde.contains('.')) { final p = dKunde.split('.'); k = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); } else { k = DateTime.parse(dKunde); } wFrist = DateFormat('dd.MM.yyyy').format(DateTime(k.year, k.month + 1, k.day)); } catch (_) {} }
    Map<String, dynamic> wData = {};
    // Search widerspruch_data on ANY record in the group
    for (final d in docGroup) {
      try {
        final raw = d['widerspruch_data'];
        if (raw is String && raw.isNotEmpty) {
          wData = Map<String, dynamic>.from(jsonDecode(raw) as Map);
          break;
        } else if (raw is Map && raw.isNotEmpty) {
          wData = Map<String, dynamic>.from(raw);
          break;
        }
      } catch (_) {}
    }
    final hasW = wData.isNotEmpty;
    final kFiles = docGroup.where((d) => (d['file_name']?.toString() ?? '').isNotEmpty && (d['doc_type']?.toString() ?? 'korrespondenz') == 'korrespondenz').toList();
    final wFiles = docGroup.where((d) => d['doc_type'] == 'widerspruch' && (d['file_name']?.toString() ?? '').isNotEmpty).toList();
    final ebFiles = docGroup.where((d) => d['doc_type'] == 'eingangsbestaetigung' && (d['file_name']?.toString() ?? '').isNotEmpty).toList();

    showDialog(context: context, builder: (dlgCtx) => DefaultTabController(length: 3, child: AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      contentPadding: EdgeInsets.zero,
      title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18, color: color.shade700),
          const SizedBox(width: 8),
          Expanded(child: Text(first['betreff']?.toString() ?? '', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color.shade800), overflow: TextOverflow.ellipsis)),
          if (hasW) Container(margin: const EdgeInsets.only(right: 4), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.gavel, size: 10, color: Colors.red.shade700), const SizedBox(width: 3), Text('W', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.red.shade700))])),
          IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), tooltip: 'Löschen', onPressed: () async { Navigator.pop(dlgCtx); for (final d in docGroup) { await widget.apiService.deleteAAKorrespondenz(d['id'] is int ? d['id'] : int.parse(d['id'].toString())); } _loadDocs(); }),
          IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => Navigator.pop(dlgCtx)),
        ]),
        const SizedBox(height: 4),
        TabBar(labelColor: color.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: color.shade700, tabs: [
          const Tab(icon: Icon(Icons.info_outline, size: 16), text: 'Details'),
          Tab(icon: const Icon(Icons.folder_open, size: 16), text: 'Unterlagen (${kFiles.length})'),
          Tab(icon: Icon(Icons.gavel, size: 16, color: hasW ? Colors.red.shade600 : null), text: 'Widerspruch'),
        ]),
      ]),
      content: SizedBox(width: 550, height: 450, child: TabBarView(children: [
        // ═══ TAB 1: Details ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: double.infinity, padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _korrInfoRow(isEingang ? Icons.call_received : Icons.call_made, 'Richtung', isEingang ? 'Eingang' : 'Ausgang', isEingang ? Colors.green : Colors.blue),
            _korrInfoRow(Icons.mail, 'Methode', mLabels[m] ?? m, Colors.indigo),
            if (dErstellt.isNotEmpty) _korrInfoRow(Icons.edit_calendar, 'Bescheid erstellt', dErstellt, Colors.blue),
            if (dKunde.isNotEmpty) _korrInfoRow(Icons.person, 'Kunde erhalten', dKunde, Colors.orange),
            if (dWir.isNotEmpty) _korrInfoRow(Icons.business, 'Wir erhalten', dWir, Colors.teal),
            if (wFrist.isNotEmpty) ...[
              const Divider(height: 12),
              Row(children: [
                Icon(Icons.gavel, size: 14, color: Colors.red.shade600), const SizedBox(width: 8),
                Text('Widerspruchsfrist: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                Text(wFrist, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                const SizedBox(width: 6),
                Builder(builder: (_) { try { final p = wFrist.split('.'); final d = DateTime(int.parse(p[2]), int.parse(p[1]), int.parse(p[0])); final left = d.difference(DateTime.now()).inDays; final exp = left < 0; return Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), decoration: BoxDecoration(color: exp ? Colors.red.shade100 : (left <= 7 ? Colors.orange.shade100 : Colors.green.shade100), borderRadius: BorderRadius.circular(4)), child: Text(exp ? 'Abgelaufen!' : '$left Tage', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: exp ? Colors.red.shade800 : (left <= 7 ? Colors.orange.shade800 : Colors.green.shade800)))); } catch (_) { return const SizedBox.shrink(); } }),
              ]),
            ],
          ])),
          if ((first['notiz']?.toString() ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
              child: Text(first['notiz'].toString(), style: const TextStyle(fontSize: 12))),
          ],
        ])),

        // ═══ TAB 2: Unterlagen ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.folder_open, size: 16, color: Colors.teal.shade700), const SizedBox(width: 6),
            Text('Unterlagen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
            const Spacer(),
            OutlinedButton.icon(icon: Icon(Icons.upload_file, size: 14, color: Colors.teal.shade600), label: Text('Hinzufügen', style: TextStyle(fontSize: 11, color: Colors.teal.shade600)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, side: BorderSide(color: Colors.teal.shade300)),
              onPressed: () async {
                final result = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                if (result == null || result.files.isEmpty) return;
                final gId = gruppeId ?? const Uuid().v4();
                for (final f in result.files) { if (f.path == null) continue; await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: first['richtung']?.toString() ?? 'eingang', titel: first['titel']?.toString() ?? '', datum: first['datum']?.toString() ?? '', betreff: first['betreff']?.toString() ?? '', notiz: '', methode: m, gruppeId: gId, filePath: f.path!, fileName: f.name); }
                _loadDocs(); if (dlgCtx.mounted) Navigator.pop(dlgCtx);
              }),
          ]),
          const SizedBox(height: 10),
          if (kFiles.isEmpty) Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8)), child: Text('Keine Unterlagen', style: TextStyle(fontSize: 12, color: Colors.grey.shade400), textAlign: TextAlign.center))
          else ...kFiles.map((f) => Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
            child: Row(children: [
              Icon(Icons.description, size: 16, color: Colors.grey.shade500), const SizedBox(width: 8),
              Expanded(child: Text(f['file_name'].toString(), style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
              IconButton(icon: Icon(Icons.visibility, size: 16, color: Colors.indigo.shade500), tooltip: 'Ansehen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
              IconButton(icon: Icon(Icons.download, size: 16, color: Colors.teal.shade600), tooltip: 'Download', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
            ]))),
        ])),

        // ═══ TAB 3: Widerspruch ═══
        SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (hasW) ...[
            // ── Schritt 1: Vorbereitet ──
            _wStep(Icons.description, '1. Widerspruch vorbereitet', Colors.red, true, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((wData['datum']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.calendar_today, 'Datum', wData['datum'].toString(), Colors.red),
              if ((wData['frist']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.timer, 'Frist', wData['frist'].toString(), Colors.orange),
              if ((wData['grund']?.toString() ?? '').isNotEmpty) ...[const SizedBox(height: 4), Text('Begründung: ${wData['grund']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade700))],
              if (wFiles.isNotEmpty) ...[const SizedBox(height: 6),
                ...wFiles.map((f) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
                  Icon(Icons.description, size: 14, color: Colors.red.shade400), const SizedBox(width: 6),
                  Expanded(child: Text(f['file_name'].toString(), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade500), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                  IconButton(icon: Icon(Icons.download, size: 14, color: Colors.teal.shade600), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                ]))),
              ],
            ])),
            const SizedBox(height: 8),
            // ── Schritt 2: Gedruckt? ──
            _wStep(Icons.print, '2. Gedruckt?', Colors.blue, wData['gedruckt'] == true, Row(children: [
              Icon(wData['gedruckt'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: wData['gedruckt'] == true ? Colors.green.shade700 : Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(wData['gedruckt'] == true ? 'Ja${(wData['gedruckt_datum']?.toString() ?? '').isNotEmpty ? ' – ${wData['gedruckt_datum']}' : ''}' : 'Noch nicht gedruckt', style: TextStyle(fontSize: 12, color: wData['gedruckt'] == true ? Colors.green.shade700 : Colors.grey.shade500)),
            ])),
            const SizedBox(height: 8),
            // ── Schritt 3: Unterschrieben? ──
            _wStep(Icons.draw, '3. Kunde unterschrieben?', Colors.purple, wData['unterschrieben'] == true, Row(children: [
              Icon(wData['unterschrieben'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: wData['unterschrieben'] == true ? Colors.green.shade700 : Colors.grey.shade400),
              const SizedBox(width: 6),
              Text(wData['unterschrieben'] == true ? 'Ja${(wData['unterschrieben_datum']?.toString() ?? '').isNotEmpty ? ' – ${wData['unterschrieben_datum']}' : ''}' : 'Noch nicht unterschrieben', style: TextStyle(fontSize: 12, color: wData['unterschrieben'] == true ? Colors.green.shade700 : Colors.grey.shade500)),
            ])),
            const SizedBox(height: 8),
            // ── Schritt 4: Versendet ──
            _wStep(Icons.send, '4. Versendet / Abgegeben', Colors.indigo, (wData['versandart']?.toString() ?? '').isNotEmpty, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if ((wData['versandart']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.send, 'Versandart', wData['versandart'].toString(), Colors.indigo),
              if ((wData['abgabe_datum']?.toString() ?? '').isNotEmpty) _korrInfoRow(Icons.calendar_today, 'Versanddatum', wData['abgabe_datum'].toString(), Colors.indigo),
              if ((wData['versandart']?.toString() ?? '').isEmpty) Text('Noch nicht versendet', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ])),
            const SizedBox(height: 8),
            // ── Schritt 5: Eingangsbestätigung ──
            _wStep(Icons.verified, '5. Eingangsbestätigung', Colors.green, wData['eingangsbestaetigung'] == true, Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(wData['eingangsbestaetigung'] == true ? Icons.check_circle : Icons.cancel, size: 16, color: wData['eingangsbestaetigung'] == true ? Colors.green.shade700 : Colors.grey.shade400),
                const SizedBox(width: 6),
                Text(wData['eingangsbestaetigung'] == true ? 'Erhalten' : 'Noch nicht erhalten', style: TextStyle(fontSize: 12, color: wData['eingangsbestaetigung'] == true ? Colors.green.shade700 : Colors.grey.shade500)),
              ]),
              if (ebFiles.isNotEmpty) ...[const SizedBox(height: 6),
                ...ebFiles.map((f) => Padding(padding: const EdgeInsets.only(bottom: 3), child: Row(children: [
                  Icon(Icons.description, size: 14, color: Colors.green.shade400), const SizedBox(width: 6),
                  Expanded(child: Text(f['file_name'].toString(), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)),
                  IconButton(icon: Icon(Icons.visibility, size: 14, color: Colors.indigo.shade500), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _viewDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                  IconButton(icon: Icon(Icons.download, size: 14, color: Colors.teal.shade600), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => _downloadDoc(f['id'] is int ? f['id'] : int.parse(f['id'].toString()), f['file_name'].toString())),
                ]))),
              ],
            ])),
            const SizedBox(height: 12),
          ],
          // Create/Edit Widerspruch button
          OutlinedButton.icon(icon: Icon(hasW ? Icons.edit : Icons.add, size: 14, color: Colors.red.shade600),
            label: Text(hasW ? 'Widerspruch bearbeiten' : 'Widerspruch erstellen', style: TextStyle(fontSize: 11, color: Colors.red.shade600)),
            style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero, side: BorderSide(color: Colors.red.shade300)),
            onPressed: () {
              final wDatumC = TextEditingController(text: wData['datum']?.toString() ?? DateFormat('dd.MM.yyyy').format(DateTime.now()));
              final wFristC = TextEditingController(text: wData['frist']?.toString() ?? wFrist);
              final wGrundC = TextEditingController(text: wData['grund']?.toString() ?? '');
              bool wGedruckt = wData['gedruckt'] == true;
              final wGedrucktDatumC = TextEditingController(text: wData['gedruckt_datum']?.toString() ?? '');
              bool wUnterschrieben = wData['unterschrieben'] == true;
              final wUnterschriebenDatumC = TextEditingController(text: wData['unterschrieben_datum']?.toString() ?? '');
              String wVersandart = ''; List<PlatformFile> newWDocs = []; List<PlatformFile> newEbDocs = [];
              final wAbgabeC = TextEditingController(text: wData['abgabe_datum']?.toString() ?? '');
              bool wEb = wData['eingangsbestaetigung'] == true;
              if ((wData['versandart']?.toString() ?? '').isNotEmpty) { const rev = {'Online': 'online', 'Post': 'post', 'Persönlich': 'persoenlich', 'Fax': 'fax'}; wVersandart = rev[wData['versandart']] ?? ''; }

              showDialog(context: dlgCtx, builder: (wCtx) => StatefulBuilder(builder: (wCtx, setW) => AlertDialog(
                title: Row(children: [Icon(Icons.gavel, size: 18, color: Colors.red.shade700), const SizedBox(width: 8), const Expanded(child: Text('Widerspruch', style: TextStyle(fontSize: 14)))]),
                content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Step 1
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.red.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.description, size: 16, color: Colors.red.shade700), const SizedBox(width: 6), Text('1. Widerspruch vorbereiten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade700))]),
                      const SizedBox(height: 10),
                      Row(children: [
                        Expanded(child: TextFormField(controller: wDatumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) wDatumC.text = DateFormat('dd.MM.yyyy').format(p); })))),
                        const SizedBox(width: 8),
                        Expanded(child: TextFormField(controller: wFristC, readOnly: true, decoration: InputDecoration(labelText: 'Frist bis', prefixIcon: Icon(Icons.timer, size: 16, color: Colors.orange.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now().add(const Duration(days: 30)), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) wFristC.text = DateFormat('dd.MM.yyyy').format(p); })))),
                      ]),
                      const SizedBox(height: 10),
                      TextFormField(controller: wGrundC, maxLines: 3, decoration: InputDecoration(labelText: 'Begründung', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(icon: Icon(Icons.upload_file, size: 14, color: Colors.red.shade600), label: Text(newWDocs.isEmpty ? 'Widerspruch-Dokumente' : '${newWDocs.length} Dok.', style: TextStyle(fontSize: 11, color: Colors.red.shade700)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300)),
                        onPressed: () async { final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setW(() { newWDocs.addAll(r.files); }); }),
                      ...newWDocs.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [Icon(Icons.description, size: 13, color: Colors.red.shade400), const SizedBox(width: 6), Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)), IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setW(() => newWDocs.removeAt(e.key)))]))),
                    ])),
                  const SizedBox(height: 10),
                  // Step 2: Gedruckt
                  InkWell(onTap: () => setW(() => wGedruckt = !wGedruckt), borderRadius: BorderRadius.circular(8),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: wGedruckt ? Colors.blue.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: wGedruckt ? Colors.blue.shade300 : Colors.grey.shade200)),
                      child: Row(children: [
                        Icon(wGedruckt ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: wGedruckt ? Colors.blue.shade700 : Colors.grey.shade400), const SizedBox(width: 8),
                        Text('2. Gedruckt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wGedruckt ? Colors.blue.shade800 : Colors.grey.shade600)),
                        if (wGedruckt) ...[const Spacer(), SizedBox(width: 130, height: 32, child: TextFormField(controller: wGedrucktDatumC, readOnly: true, style: const TextStyle(fontSize: 11), decoration: InputDecoration(hintText: 'Datum', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 12), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setW(() => wGedrucktDatumC.text = DateFormat('dd.MM.yyyy').format(p)); }))))],
                      ]))),
                  const SizedBox(height: 8),
                  // Step 3: Unterschrieben
                  InkWell(onTap: () => setW(() => wUnterschrieben = !wUnterschrieben), borderRadius: BorderRadius.circular(8),
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: wUnterschrieben ? Colors.purple.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: wUnterschrieben ? Colors.purple.shade300 : Colors.grey.shade200)),
                      child: Row(children: [
                        Icon(wUnterschrieben ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: wUnterschrieben ? Colors.purple.shade700 : Colors.grey.shade400), const SizedBox(width: 8),
                        Text('3. Kunde unterschrieben', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wUnterschrieben ? Colors.purple.shade800 : Colors.grey.shade600)),
                        if (wUnterschrieben) ...[const Spacer(), SizedBox(width: 130, height: 32, child: TextFormField(controller: wUnterschriebenDatumC, readOnly: true, style: const TextStyle(fontSize: 11), decoration: InputDecoration(hintText: 'Datum', isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6), border: OutlineInputBorder(borderRadius: BorderRadius.circular(6)),
                          suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 12), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) setW(() => wUnterschriebenDatumC.text = DateFormat('dd.MM.yyyy').format(p)); }))))],
                      ]))),
                  const SizedBox(height: 10),
                  // Step 4: Versand
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.indigo.shade200)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [Icon(Icons.send, size: 16, color: Colors.indigo.shade700), const SizedBox(width: 6), Text('2. Versand', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)), const Spacer(), Text('(optional)', style: TextStyle(fontSize: 9, color: Colors.grey.shade500))]),
                      const SizedBox(height: 10),
                      Wrap(spacing: 6, runSpacing: 4, children: [for (final v in <(String, String, IconData, MaterialColor)>[('online', 'Online', Icons.language, Colors.blue), ('post', 'Post', Icons.mail, Colors.brown), ('persoenlich', 'Persönlich', Icons.person, Colors.green), ('fax', 'Fax', Icons.fax, Colors.grey)])
                        ChoiceChip(label: Row(mainAxisSize: MainAxisSize.min, children: [Icon(v.$3, size: 13, color: wVersandart == v.$1 ? Colors.white : v.$4.shade700), const SizedBox(width: 4), Text(v.$2, style: TextStyle(fontSize: 10, color: wVersandart == v.$1 ? Colors.white : v.$4.shade700))]), selected: wVersandart == v.$1, selectedColor: v.$4.shade600, onSelected: (_) => setW(() => wVersandart = wVersandart == v.$1 ? '' : v.$1))]),
                      const SizedBox(height: 10),
                      TextFormField(controller: wAbgabeC, readOnly: true, decoration: InputDecoration(labelText: 'Abgabe / Versand', prefixIcon: Icon(Icons.send, size: 16, color: Colors.indigo.shade600), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)), suffixIcon: IconButton(icon: const Icon(Icons.edit_calendar, size: 14), onPressed: () async { final p = await showDatePicker(context: wCtx, initialDate: DateTime.now(), firstDate: DateTime(2000), lastDate: DateTime(2060), locale: const Locale('de')); if (p != null) wAbgabeC.text = DateFormat('dd.MM.yyyy').format(p); }))),
                      const SizedBox(height: 10),
                      InkWell(onTap: () => setW(() => wEb = !wEb), borderRadius: BorderRadius.circular(8), child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10), decoration: BoxDecoration(color: wEb ? Colors.green.shade50 : Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: wEb ? Colors.green.shade300 : Colors.grey.shade200)),
                        child: Row(children: [Icon(wEb ? Icons.check_box : Icons.check_box_outline_blank, size: 18, color: wEb ? Colors.green.shade700 : Colors.grey.shade400), const SizedBox(width: 8), Expanded(child: Text('Eingangsbestätigung erhalten', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: wEb ? Colors.green.shade800 : Colors.grey.shade700)))]))),
                      if (wEb) ...[const SizedBox(height: 8),
                        OutlinedButton.icon(icon: Icon(Icons.attach_file, size: 14, color: Colors.green.shade600), label: Text(newEbDocs.isEmpty ? 'EB anhängen' : '${newEbDocs.length} Datei(en)', style: TextStyle(fontSize: 11, color: Colors.green.shade700)), style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.green.shade300)),
                          onPressed: () async { final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']); if (r != null) setW(() { newEbDocs.addAll(r.files); }); }),
                        ...newEbDocs.asMap().entries.map((e) => Padding(padding: const EdgeInsets.only(top: 3), child: Row(children: [Icon(Icons.description, size: 13, color: Colors.green.shade500), const SizedBox(width: 6), Expanded(child: Text(e.value.name, style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis)), IconButton(icon: Icon(Icons.close, size: 14, color: Colors.red.shade400), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24), onPressed: () => setW(() => newEbDocs.removeAt(e.key)))]))),
                      ],
                    ])),
                ]))),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(wCtx), child: const Text('Abbrechen')),
                  FilledButton.icon(icon: const Icon(Icons.gavel, size: 14), label: const Text('Speichern'), style: FilledButton.styleFrom(backgroundColor: Colors.red.shade600),
                    onPressed: () async {
                      Navigator.pop(wCtx);
                      final fId = first['id'] is int ? first['id'] : int.parse(first['id'].toString());
                      final gId = gruppeId ?? const Uuid().v4();
                      const vLabels = {'online': 'Online', 'post': 'Post', 'persoenlich': 'Persönlich', 'fax': 'Fax'};
                      await widget.apiService.updateAAWiderspruch(fId, {'datum': wDatumC.text, 'frist': wFristC.text, 'grund': wGrundC.text.trim(), 'gedruckt': wGedruckt, 'gedruckt_datum': wGedrucktDatumC.text, 'unterschrieben': wUnterschrieben, 'unterschrieben_datum': wUnterschriebenDatumC.text, 'versandart': wVersandart.isNotEmpty ? (vLabels[wVersandart] ?? wVersandart) : '', 'abgabe_datum': wAbgabeC.text, 'eingangsbestaetigung': wEb});
                      for (final f in newWDocs) { if (f.path == null) continue; await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: first['richtung']?.toString() ?? 'eingang', titel: first['titel']?.toString() ?? '', datum: first['datum']?.toString() ?? '', betreff: first['betreff']?.toString() ?? '', notiz: '', methode: m, gruppeId: gId, docType: 'widerspruch', filePath: f.path!, fileName: f.name); }
                      for (final f in newEbDocs) { if (f.path == null) continue; await widget.apiService.uploadAAKorrespondenz(userId: widget.userId, richtung: first['richtung']?.toString() ?? 'eingang', titel: first['titel']?.toString() ?? '', datum: first['datum']?.toString() ?? '', betreff: first['betreff']?.toString() ?? '', notiz: '', methode: m, gruppeId: gId, docType: 'eingangsbestaetigung', filePath: f.path!, fileName: f.name); }
                      _loadDocs(); if (dlgCtx.mounted) { ScaffoldMessenger.of(dlgCtx).showSnackBar(const SnackBar(content: Text('Widerspruch gespeichert'), backgroundColor: Colors.green)); Navigator.pop(dlgCtx); }
                    }),
                ],
              )));
            }),
          const SizedBox(height: 10),
          Container(width: double.infinity, padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.red.shade100)),
            child: Row(children: [Icon(Icons.info_outline, size: 14, color: Colors.red.shade400), const SizedBox(width: 8), Expanded(child: Text('Widerspruchsfrist: In der Regel 1 Monat nach Zustellung.', style: TextStyle(fontSize: 11, color: Colors.red.shade700)))])),
        ])),
      ])),
    )));
  }

  Future<void> _viewDoc(int docId, String fileName) async {
    try {
      final response = await widget.apiService.downloadAAKorrespondenzDoc(docId);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        if (mounted) FileViewerDialog.showFromBytes(context, response.bodyBytes, fileName);
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler (${response.statusCode})'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _downloadDoc(int docId, String fileName) async {
    try {
      final response = await widget.apiService.downloadAAKorrespondenzDoc(docId);
      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        final String downloadsPath;
        if (Platform.isMacOS) {
          downloadsPath = '${Platform.environment['HOME']}/Downloads';
        } else if (Platform.isWindows) {
          downloadsPath = '${Platform.environment['USERPROFILE']}\\Downloads';
        } else {
          downloadsPath = Directory.systemTemp.path;
        }
        var destFile = File('$downloadsPath${Platform.pathSeparator}$fileName');
        int counter = 1;
        while (destFile.existsSync()) {
          final ext = fileName.contains('.') ? '.${fileName.split('.').last}' : '';
          final base = fileName.contains('.') ? fileName.substring(0, fileName.lastIndexOf('.')) : fileName;
          destFile = File('$downloadsPath${Platform.pathSeparator}${base}_($counter)$ext');
          counter++;
        }
        await destFile.writeAsBytes(response.bodyBytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$fileName gespeichert'), backgroundColor: Colors.green, duration: const Duration(seconds: 3),
            action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () { Process.run('open', [destFile.path]); })));
        }
        Process.run('open', [destFile.path]);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Widget _wStep(IconData icon, String title, MaterialColor c, bool done, Widget content) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: done ? c.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: done ? c.shade300 : Colors.grey.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: done ? c.shade700 : Colors.grey.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: done ? c.shade700 : Colors.grey.shade500))),
          Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 16, color: done ? Colors.green.shade600 : Colors.grey.shade300),
        ]),
        const SizedBox(height: 6),
        content,
      ]),
    );
  }

  Widget _korrInfoRow(IconData icon, String label, String value, MaterialColor c) {
    return Padding(padding: const EdgeInsets.only(bottom: 4), child: Row(children: [
      Icon(icon, size: 14, color: c.shade600), const SizedBox(width: 8),
      Text('$label: ', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
      Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.shade800)),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));

    // Group docs by gruppe_id
    final filteredRaw = _filter == 'alle' ? _docs : _docs.where((d) => d['richtung'] == _filter).toList();
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final doc in filteredRaw) {
      final gId = doc['gruppe_id']?.toString() ?? 'single_${doc['id']}';
      grouped.putIfAbsent(gId, () => []).add(doc);
    }
    final groups = grouped.values.toList();
    final eingangCount = grouped.values.where((g) => g.first['richtung'] == 'eingang').length;
    final ausgangCount = grouped.values.where((g) => g.first['richtung'] == 'ausgang').length;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 8),
      Row(children: [
        Icon(Icons.email, size: 20, color: Colors.teal.shade700),
        const SizedBox(width: 8),
        Text('Korrespondenz', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
        const Spacer(),
        FilledButton.icon(
          icon: const Icon(Icons.call_received, size: 14),
          label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorrespondenz('eingang'),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          icon: const Icon(Icons.call_made, size: 14),
          label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _addKorrespondenz('ausgang'),
        ),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        ChoiceChip(label: Text('Alle (${_docs.length})', style: TextStyle(fontSize: 10, color: _filter == 'alle' ? Colors.white : Colors.grey.shade700)), selected: _filter == 'alle', selectedColor: Colors.teal.shade600, onSelected: (_) => setState(() => _filter = 'alle')),
        const SizedBox(width: 6),
        ChoiceChip(label: Text('Eingang ($eingangCount)', style: TextStyle(fontSize: 10, color: _filter == 'eingang' ? Colors.white : Colors.green.shade700)), selected: _filter == 'eingang', selectedColor: Colors.green.shade600, onSelected: (_) => setState(() => _filter = 'eingang')),
        const SizedBox(width: 6),
        ChoiceChip(label: Text('Ausgang ($ausgangCount)', style: TextStyle(fontSize: 10, color: _filter == 'ausgang' ? Colors.white : Colors.blue.shade700)), selected: _filter == 'ausgang', selectedColor: Colors.blue.shade600, onSelected: (_) => setState(() => _filter = 'ausgang')),
      ]),
      const SizedBox(height: 10),

      if (groups.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Icon(Icons.email_outlined, size: 36, color: Colors.grey.shade300),
            const SizedBox(height: 6),
            Text('Keine Korrespondenz vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ]),
        )
      else
        ...groups.map((docGroup) {
          final first = docGroup.first;
          final isEingang = first['richtung'] == 'eingang';
          final color = isEingang ? Colors.green : Colors.blue;
          const methodeIcons = {'email': Icons.email, 'post': Icons.mail, 'telefon': Icons.phone, 'fax': Icons.fax, 'online': Icons.language};
          const methodeLabels = {'email': 'E-Mail', 'post': 'Post', 'telefon': 'Telefon', 'fax': 'Fax', 'online': 'Portal'};
          final m = first['methode']?.toString() ?? 'post';
          final datumStr = first['datum']?.toString() ?? '';
          final datumFmt = datumStr.isNotEmpty ? (() { try { return DateFormat('dd.MM.yyyy').format(DateTime.parse(datumStr)); } catch (_) { return datumStr; } })() : '';
          final files = docGroup.where((d) => (d['file_name']?.toString() ?? '').isNotEmpty).toList();

          return InkWell(
            onTap: () => _showKorrDetailDialog(docGroup, first, files),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: color.shade200)),
              child: Row(children: [
                Container(padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(8)),
                  child: Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18, color: color.shade700)),
                const SizedBox(width: 10),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(first['betreff']?.toString() ?? first['titel']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color.shade800), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 8),
                    Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: color.shade100, borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(methodeIcons[m] ?? Icons.mail, size: 10, color: color.shade700), const SizedBox(width: 3), Text(methodeLabels[m] ?? m, style: TextStyle(fontSize: 9, color: color.shade700))])),
                    if (files.isNotEmpty) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(4)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.attach_file, size: 10, color: Colors.grey.shade600), const SizedBox(width: 2), Text('${files.length}', style: TextStyle(fontSize: 9, color: Colors.grey.shade700))]))],
                  ]),
                  Text(datumFmt, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                ])),
                Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
              ]),
            ),
          );
        }),
    ]);
  }
}
