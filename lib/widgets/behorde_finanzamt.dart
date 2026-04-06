import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../screens/webview_screen.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import 'behorde_finanzamt_steuerklarung.dart';

class BehordeFinanzamtContent extends StatefulWidget {
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final ApiService? apiService;
  final User? user;

  const BehordeFinanzamtContent({
    super.key,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    this.apiService,
    this.user,
  });

  @override
  State<BehordeFinanzamtContent> createState() => _BehordeFinanzamtContentState();
}

class _BehordeFinanzamtContentState extends State<BehordeFinanzamtContent> {
  static const type = 'finanzamt';
  final Map<String, Map<String, String>> _dbFinanzamtDaten = {};
  bool _showSteuerklarung = false;
  bool _elsterBenutzernameEditing = false;
  bool _elsterAktivierungsIdEditing = false;

  // Controllers (class-level to avoid memory leaks)
  final _dienststelleController = TextEditingController();
  final _steuerIdController = TextEditingController();
  final _finanzamtNameController = TextEditingController();
  final _elsterBenutzernameController = TextEditingController();
  final _elsterAktivierungsIdController = TextEditingController();
  final _elsterPasswortController = TextEditingController();
  bool _controllersInitialized = false;

  // Grundfreibetrag from DB
  List<Map<String, dynamic>> _grundfreibetragAlle = [];
  bool _grundfreibetragLoaded = false;

  Future<void> _loadGrundfreibetrag() async {
    if (_grundfreibetragLoaded || widget.apiService == null) return;
    try {
      final result = await widget.apiService!.getGrundfreibetrag();
      if (result['success'] == true) {
        setState(() {
          if (result['alle'] is List) {
            _grundfreibetragAlle = (result['alle'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
          }
          _grundfreibetragLoaded = true;
        });
      }
    } catch (_) {}
  }

  void _initControllers(Map<String, dynamic> data) {
    if (!_controllersInitialized) {
      _dienststelleController.text = data['dienststelle'] ?? '';
      _steuerIdController.text = data['steuer_id'] ?? '';
      _finanzamtNameController.text = data['finanzamt_name'] ?? '';
      _elsterBenutzernameController.text = data['elster_benutzername'] ?? '';
      _elsterAktivierungsIdController.text = data['elster_aktivierungs_id'] ?? '';
      _elsterPasswortController.text = data['elster_zertifikat_passwort'] ?? '';
      _controllersInitialized = true;
    }
  }

  @override
  void dispose() {
    _dienststelleController.dispose();
    _steuerIdController.dispose();
    _finanzamtNameController.dispose();
    _elsterBenutzernameController.dispose();
    _elsterAktivierungsIdController.dispose();
    _elsterPasswortController.dispose();
    super.dispose();
  }

  int _getGrundfreibetrag(int year, {bool verheiratet = false}) {
    for (final item in _grundfreibetragAlle) {
      if (int.tryParse(item['jahr']?.toString() ?? '') == year) {
        final betrag = double.tryParse((verheiratet ? item['verheiratet_betrag'] : item['betrag'])?.toString() ?? '0') ?? 0;
        return betrag.round();
      }
    }
    // Fallback hardcoded
    const fallback = {2020: 9408, 2021: 9744, 2022: 10347, 2023: 10908, 2024: 11784, 2025: 12096, 2026: 12348};
    final single = fallback[year] ?? fallback.values.last;
    return verheiratet ? single * 2 : single;
  }


  @override
  Widget build(BuildContext context) {
    // Steuererklärung sub-view
    if (_showSteuerklarung && widget.apiService != null && widget.user != null) {
      return FinanzamtSteuerklarungWidget(
        apiService: widget.apiService!,
        user: widget.user!,
        finanzamtData: widget.getData(type),
        onBack: () => setState(() => _showSteuerklarung = false),
      );
    }

    // Auto-load Grundfreibetrag from DB
    if (!_grundfreibetragLoaded) _loadGrundfreibetrag();

    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type)) {
      widget.loadData(type);
    }
    if (widget.isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }
    _initControllers(data);
    final dienststelleController = _dienststelleController;
    // Steuernummer entfernt — nur fuer Firmen/Selbststaendige relevant
    final steuerIdController = _steuerIdController;
    final finanzamtNameController = _finanzamtNameController;
    String steuerklasse = data['steuerklasse'] ?? '';
    bool steuerIdEditing = false;
    bool steuerklasseEditing = false;
    String elsterKonto = data['elster_konto'] ?? '';
    final elsterBenutzernameController = _elsterBenutzernameController;
    final elsterAktivierungsIdController = _elsterAktivierungsIdController;
    final elsterPasswortController = _elsterPasswortController;
    String elsterZertifikatBase64 = data['elster_zertifikat_base64'] ?? '';
    String elsterZertifikatName = data['elster_zertifikat_name'] ?? '';
    bool elsterPasswortVisible = false;

    final steuerklassen = {
      '': 'Nicht ausgewählt',
      'I': 'Klasse I – Ledig, geschieden, verwitwet',
      'II': 'Klasse II – Alleinerziehend mit Kind',
      'III': 'Klasse III – Verheiratet (Alleinverdiener)',
      'IV': 'Klasse IV – Verheiratet (gleich hohes Einkommen)',
      'V': 'Klasse V – Verheiratet (Partner hat Klasse III)',
      'VI': 'Klasse VI – Zweitjob / Nebenbeschäftigung',
    };

    return StatefulBuilder(
      builder: (context, setLocalState) {
        // Grundfreibetrag calculation
        final currentYear = DateTime.now().year;
        final isVerheiratet = steuerklasse == 'III' || steuerklasse == 'IV' || steuerklasse == 'V';
        final grundfreibetrag = _getGrundfreibetrag(currentYear, verheiratet: isVerheiratet);

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // === STEUERERKLÄRUNG BUTTON (TOP) ===
              if (widget.apiService != null && widget.user != null) ...[
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() => _showSteuerklarung = true),
                    icon: const Icon(Icons.receipt_long, size: 20),
                    label: const Text('Steuererklärung erstellen (Anlage N)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text('Daten aus Lohnsteuerbescheinigung (OCR) + XML für ELSTER', style: TextStyle(fontSize: 10, color: Colors.indigo.shade500)),
                const SizedBox(height: 16),
              ],

              // ── GRUNDFREIBETRAG INFO CARD ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade50, Colors.teal.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.teal.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.shield, color: Colors.teal.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'Grundfreibetrag $currentYear',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.teal.shade800),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.teal.shade700,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _formatCurrency(grundfreibetrag),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      isVerheiratet
                          ? 'Zusammenveranlagung (Ehepartner): ${_formatCurrency(grundfreibetrag)}'
                          : 'Einzelveranlagung: ${_formatCurrency(grundfreibetrag)}',
                      style: TextStyle(fontSize: 13, color: Colors.teal.shade700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Einkommen bis zum Grundfreibetrag ist steuerfrei. Änderung jährlich zum 01.01.',
                      style: TextStyle(fontSize: 12, color: Colors.teal.shade600, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),
                    // Expandable history table
                    Theme(
                      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                      child: ExpansionTile(
                        tilePadding: EdgeInsets.zero,
                        childrenPadding: EdgeInsets.zero,
                        title: Text(
                          'Grundfreibetrag-Verlauf anzeigen',
                          style: TextStyle(fontSize: 12, color: Colors.teal.shade700, fontWeight: FontWeight.w500),
                        ),
                        children: [
                          ..._grundfreibetragAlle.map((item) {
                            final jahr = int.tryParse(item['jahr']?.toString() ?? '0') ?? 0;
                            final betrag = (double.tryParse(item['betrag']?.toString() ?? '0') ?? 0).round();
                            final maxBetrag = _grundfreibetragAlle.isNotEmpty ? (double.tryParse(_grundfreibetragAlle.first['betrag']?.toString() ?? '0') ?? 1).round() : 1;
                            final isCurrent = jahr == currentYear;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 50,
                                    child: Text(
                                      '$jahr',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                        color: isCurrent ? Colors.teal.shade800 : Colors.grey.shade700,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Container(
                                      height: 20,
                                      alignment: Alignment.centerLeft,
                                      child: FractionallySizedBox(
                                        widthFactor: betrag / (maxBetrag * 1.1),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: isCurrent ? Colors.teal.shade400 : Colors.teal.shade200,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _formatCurrency(betrag),
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                                      color: isCurrent ? Colors.teal.shade800 : Colors.grey.shade600,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const SizedBox(height: 4),
                          Text(
                            'Wird jahrlich von der Bundesregierung angepasst (Existenzminimumbericht).',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Zuständiges Finanzamt
              Text('Zustaendiges Finanzamt', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Autocomplete<String>(
                initialValue: finanzamtNameController.value,
                optionsBuilder: (textEditingValue) {
                  final q = textEditingValue.text.toLowerCase();
                  final faDaten = _getFinanzamtDatenMap();
                  return faDaten.keys.where((k) => q.isEmpty || k.toLowerCase().contains(q));
                },
                fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                  if (controller.text.isEmpty && finanzamtNameController.text.isNotEmpty) {
                    controller.text = finanzamtNameController.text;
                  }
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: InputDecoration(
                      hintText: 'z.B. Finanzamt Neu-Ulm',
                      prefixIcon: const Icon(Icons.account_balance, size: 20),
                      suffixIcon: const Icon(Icons.arrow_drop_down, size: 24),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 14),
                    onChanged: (v) {
                      finanzamtNameController.text = v;
                      setLocalState(() {});
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 200, maxWidth: 450),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final fa = options.elementAt(index);
                            final info = _getFinanzamtDatenMap()[fa];
                            return ListTile(
                              dense: true,
                              leading: const Icon(Icons.account_balance, size: 18),
                              title: Text(fa, style: const TextStyle(fontSize: 13)),
                              subtitle: info != null ? Text(info['adresse'] ?? '', style: const TextStyle(fontSize: 11)) : null,
                              onTap: () {
                                onSelected(fa);
                                finanzamtNameController.text = fa;
                                setLocalState(() {});
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
                onSelected: (fa) {
                  finanzamtNameController.text = fa;
                  setLocalState(() {});
                },
              ),
              // Kontaktdaten anzeigen wenn Finanzamt bekannt
              Builder(builder: (context) {
                final fa = finanzamtNameController.text.trim();
                final info = _getFinanzamtDatenMap()[fa];
                if (info == null) return const SizedBox(height: 16);
                return Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.contact_phone, size: 16, color: Colors.blue.shade700),
                            const SizedBox(width: 6),
                            Text('Kontaktdaten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (info['adresse'] != null)
                          _finanzamtKontaktRow(Icons.location_on, info['adresse']!),
                        if (info['telefon'] != null)
                          _finanzamtKontaktRow(Icons.phone, 'Tel: ${info['telefon']}'),
                        if (info['fax'] != null)
                          _finanzamtKontaktRow(Icons.fax, 'Fax: ${info['fax']}'),
                        if (info['email'] != null)
                          InkWell(
                            onTap: () {
                              ClipboardHelper.copy(context, info['email']!, 'E-Mail');
                            },
                            child: Row(
                              children: [
                                Icon(Icons.email, size: 14, color: Colors.blue.shade400),
                                const SizedBox(width: 6),
                                Expanded(child: Text(info['email']!, style: TextStyle(fontSize: 12, color: Colors.blue.shade700, decoration: TextDecoration.underline))),
                                Icon(Icons.copy, size: 12, color: Colors.grey.shade400),
                              ],
                            ),
                          ),
                        if (info['website'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: InkWell(
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => WebViewScreen(title: 'Finanzamt', url: info['website']!),
                                ));
                              },
                              child: Row(
                                children: [
                                  Icon(Icons.language, size: 14, color: Colors.blue.shade400),
                                  const SizedBox(width: 6),
                                  Expanded(child: Text(info['website']!, style: TextStyle(fontSize: 12, color: Colors.blue.shade700, decoration: TextDecoration.underline))),
                                  Icon(Icons.open_in_browser, size: 12, color: Colors.grey.shade400),
                                ],
                              ),
                            ),
                          ),
                        if (info['oeffnungszeiten'] != null) ...[
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.access_time, size: 14, color: Colors.blue.shade400),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  info['oeffnungszeiten']!,
                                  style: TextStyle(fontSize: 12, color: Colors.blue.shade700),
                                ),
                              ),
                            ],
                          ),
                        ],
                        // Online Terminvereinbarung
                        if (info['termin_url'] != null) ...[
                          const SizedBox(height: 10),
                          const Divider(height: 1),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Icon(Icons.calendar_month, size: 16, color: Colors.green.shade700),
                              const SizedBox(width: 6),
                              Text('Online Terminvereinbarung', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          if (info['termin_telefon'] != null)
                            _finanzamtKontaktRow(Icons.phone, 'Terminvereinbarung: ${info['termin_telefon']}'),
                          const SizedBox(height: 6),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => WebViewScreen(title: 'Online Termin buchen', url: info['termin_url']!),
                                ));
                              },
                              icon: const Icon(Icons.open_in_new, size: 16),
                              label: const Text('Online Termin buchen (ELSTER)'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green.shade600,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(vertical: 10),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Kein ELSTER-Konto erforderlich — direkter Zugang zur Terminbuchung beim Servicezentrum.',
                            style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }),


              // Steuer-Identifikationsnummer
              Text('Steuer-Identifikationsnummer (Steuer-ID)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: steuerIdController,
                readOnly: !steuerIdEditing,
                decoration: InputDecoration(
                  hintText: '11-stellig, z.B. 12345678901',
                  prefixIcon: const Icon(Icons.fingerprint, size: 20),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  suffixIcon: IconButton(
                    icon: Icon(steuerIdEditing ? Icons.check : Icons.edit, size: 16),
                    onPressed: () => setLocalState(() => steuerIdEditing = !steuerIdEditing),
                    tooltip: steuerIdEditing ? 'Fertig' : 'Bearbeiten',
                  ),
                ),
                style: const TextStyle(fontSize: 14),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 4),
              Text('Lebenslang gueltig — aendert sich NIE, auch nicht bei Umzug oder Heirat. Wird bei Geburt vom Bundeszentralamt fuer Steuern (BZSt) zugeteilt.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
              const SizedBox(height: 16),

              // Steuerklasse
              Text('Steuerklasse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.shade400),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Expanded(child: steuerklasseEditing
                    ? DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: steuerklassen.containsKey(steuerklasse) ? steuerklasse : '',
                          isExpanded: true,
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          items: steuerklassen.entries.map((e) {
                            return DropdownMenuItem<String>(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)));
                          }).toList(),
                          onChanged: (v) => setLocalState(() => steuerklasse = v ?? ''),
                        ),
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          steuerklasse.isNotEmpty ? (steuerklassen[steuerklasse] ?? steuerklasse) : 'Nicht ausgewählt',
                          style: TextStyle(fontSize: 14, color: steuerklasse.isNotEmpty ? Colors.black87 : Colors.grey.shade500),
                        ),
                      ),
                  ),
                  IconButton(
                    icon: Icon(steuerklasseEditing ? Icons.check : Icons.edit, size: 16),
                    onPressed: () => setLocalState(() => steuerklasseEditing = !steuerklasseEditing),
                    tooltip: steuerklasseEditing ? 'Fertig' : 'Bearbeiten',
                  ),
                ]),
              ),
              const SizedBox(height: 4),
              Text(
                'Grundfreibetrag: Einkommen bis zu diesem Betrag ist steuerfrei.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
              ),
              const SizedBox(height: 16),

              // Info: Wann ist Steuererklärung Pflicht?
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
                        Text('Wann ist eine Steuererklarung Pflicht?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade800)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _finanzamtInfoRow(Icons.check_circle_outline, 'Einkommen uber dem Grundfreibetrag (${_formatCurrency(_getGrundfreibetrag(currentYear))})', Colors.green),
                    _finanzamtInfoRow(Icons.check_circle_outline, 'Steuerklasse III/V oder IV mit Faktor', Colors.green),
                    _finanzamtInfoRow(Icons.check_circle_outline, 'Nebeneinkünfte uber 410 EUR/Jahr', Colors.green),
                    _finanzamtInfoRow(Icons.check_circle_outline, 'Lohnersatzleistungen (ALG I, Kurzarbeitergeld, Elterngeld)', Colors.green),
                    _finanzamtInfoRow(Icons.check_circle_outline, 'Mehrere Arbeitgeber gleichzeitig', Colors.green),
                    const SizedBox(height: 8),
                    Text('Nicht erforderlich i.d.R. bei:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.blue.shade700)),
                    const SizedBox(height: 4),
                    _finanzamtInfoRow(Icons.remove_circle_outline, 'Nur Arbeitslohn, Klasse I oder IV, kein Nebenjob', Colors.grey),
                    _finanzamtInfoRow(Icons.remove_circle_outline, 'Burgergeld / Sozialhilfe (steuerfrei)', Colors.grey),
                    _finanzamtInfoRow(Icons.remove_circle_outline, 'Einkommen unter Grundfreibetrag', Colors.grey),
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── ELSTER ONLINE CARD ──
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
                        Icon(Icons.verified_user, color: Colors.indigo.shade700, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          'ELSTER Online',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.indigo.shade800),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: elsterKonto == 'ja' ? Colors.green.shade600 : Colors.grey.shade500,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            elsterKonto == 'ja' ? 'Konto vorhanden' : 'Kein Konto',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Elektronische Steuererklarung (www.elster.de)',
                      style: TextStyle(fontSize: 12, color: Colors.indigo.shade600, fontStyle: FontStyle.italic),
                    ),
                    const SizedBox(height: 12),

                    // ELSTER Konto Toggle
                    Text('ELSTER Online-Konto vorhanden?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
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
                          value: elsterKonto.isEmpty ? '' : elsterKonto,
                          isExpanded: true,
                          style: const TextStyle(fontSize: 14, color: Colors.black87),
                          items: const [
                            DropdownMenuItem(value: '', child: Text('Nicht angegeben', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'ja', child: Text('Ja', style: TextStyle(fontSize: 13))),
                            DropdownMenuItem(value: 'nein', child: Text('Nein', style: TextStyle(fontSize: 13))),
                          ],
                          onChanged: (v) => setLocalState(() => elsterKonto = v ?? ''),
                        ),
                      ),
                    ),

                    // Show ELSTER details only if account exists
                    if (elsterKonto == 'ja') ...[
                      const SizedBox(height: 16),
                      // Benutzername (read-only + pencil)
                      TextField(
                        controller: elsterBenutzernameController,
                        readOnly: !_elsterBenutzernameEditing,
                        decoration: InputDecoration(
                          labelText: 'ELSTER Benutzername',
                          hintText: 'z.B. max.mustermann@elster.de',
                          isDense: true,
                          prefixIcon: const Icon(Icons.person_outline, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: IconButton(
                            icon: Icon(_elsterBenutzernameEditing ? Icons.check : Icons.edit, size: 16),
                            onPressed: () => setState(() => _elsterBenutzernameEditing = !_elsterBenutzernameEditing),
                            tooltip: _elsterBenutzernameEditing ? 'Fertig' : 'Bearbeiten',
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => WebViewScreen(url: 'https://www.elster.de/eportal/login/softpse', title: 'ELSTER Login'),
                        )),
                        child: Row(children: [
                          Icon(Icons.open_in_new, size: 14, color: Colors.indigo.shade600),
                          const SizedBox(width: 4),
                          Text('ELSTER Login (Zertifikatsdatei)', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600, decoration: TextDecoration.underline)),
                        ]),
                      ),
                      const SizedBox(height: 12),
                      // Aktivierungs-ID (read-only + pencil)
                      TextField(
                        controller: elsterAktivierungsIdController,
                        readOnly: !_elsterAktivierungsIdEditing,
                        decoration: InputDecoration(
                          labelText: 'Aktivierungs-ID',
                          hintText: 'z.B. 1234-5678-9012',
                          isDense: true,
                          prefixIcon: const Icon(Icons.key, size: 18),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          suffixIcon: IconButton(
                            icon: Icon(_elsterAktivierungsIdEditing ? Icons.check : Icons.edit, size: 16),
                            onPressed: () => setState(() => _elsterAktivierungsIdEditing = !_elsterAktivierungsIdEditing),
                            tooltip: _elsterAktivierungsIdEditing ? 'Fertig' : 'Bearbeiten',
                          ),
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      InkWell(
                        onTap: () => Navigator.push(context, MaterialPageRoute(
                          builder: (_) => WebViewScreen(url: 'https://www.elster.de/eportal/aktivierung', title: 'ELSTER Aktivierung'),
                        )),
                        child: Row(children: [
                          Icon(Icons.open_in_new, size: 14, color: Colors.indigo.shade600),
                          const SizedBox(width: 4),
                          Text('ELSTER Aktivierung', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600, decoration: TextDecoration.underline)),
                        ]),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Aktivierungs-ID: 11-stellige Nummer (mit Bindestrichen), die per Post nach der ELSTER-Registrierung zugestellt wird.',
                        style: TextStyle(fontSize: 10, color: Colors.indigo.shade500, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 12),

                      // Certificate info box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.indigo.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade200),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.info_outline, size: 16, color: Colors.indigo.shade700),
                                const SizedBox(width: 6),
                                Text('ELSTER-Zertifikat (PFX/P12)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Das ELSTER-Zertifikat ist eine persoenliche Datei im Format .pfx (PKCS#12), '
                              'die beim Erstellen des ELSTER-Kontos heruntergeladen wird. '
                              'Es enthaelt Ihren privaten Schluessel und das X.509-Zertifikat.',
                              style: TextStyle(fontSize: 11, color: Colors.indigo.shade700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Gueltigkeit: 3 Jahre ab Erstellung. Danach muss es erneuert werden.',
                              style: TextStyle(fontSize: 11, color: Colors.indigo.shade600, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Certificate upload
                      Text('Zertifikatsdatei (.pfx / .p12)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: elsterZertifikatBase64.isNotEmpty ? Colors.green.shade400 : Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(8),
                          color: elsterZertifikatBase64.isNotEmpty ? Colors.green.shade50 : Colors.white,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (elsterZertifikatBase64.isNotEmpty) ...[
                              Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green.shade700, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          elsterZertifikatName.isNotEmpty ? elsterZertifikatName : 'Zertifikat hochgeladen',
                                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.green.shade800),
                                        ),
                                        Text(
                                          'Groesse: ${(elsterZertifikatBase64.length * 3 / 4 / 1024).toStringAsFixed(1)} KB',
                                          style: TextStyle(fontSize: 11, color: Colors.green.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(Icons.delete_outline, color: Colors.red.shade400, size: 20),
                                    tooltip: 'Zertifikat entfernen',
                                    onPressed: () => setLocalState(() {
                                      elsterZertifikatBase64 = '';
                                      elsterZertifikatName = '';
                                    }),
                                  ),
                                ],
                              ),
                            ] else ...[
                              Row(
                                children: [
                                  Icon(Icons.upload_file, color: Colors.indigo.shade400, size: 20),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'Kein Zertifikat hochgeladen',
                                      style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: () async {
                                  final result = await FilePicker.platform.pickFiles(
                                    type: FileType.custom,
                                    allowedExtensions: ['pfx', 'p12'],
                                    withData: true,
                                  );
                                  if (result != null && result.files.single.bytes != null) {
                                    final bytes = result.files.single.bytes!;
                                    final name = result.files.single.name;
                                    setLocalState(() {
                                      elsterZertifikatBase64 = base64Encode(bytes);
                                      elsterZertifikatName = name;
                                    });
                                  }
                                },
                                icon: Icon(Icons.folder_open, size: 18, color: Colors.indigo.shade600),
                                label: Text(
                                  elsterZertifikatBase64.isNotEmpty ? 'Anderes Zertifikat waehlen' : 'Zertifikat hochladen (.pfx / .p12)',
                                  style: TextStyle(fontSize: 13, color: Colors.indigo.shade700),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: BorderSide(color: Colors.indigo.shade300),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Certificate password
                      Text('Zertifikats-Passwort (PIN)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                      const SizedBox(height: 4),
                      TextField(
                        controller: elsterPasswortController,
                        obscureText: !elsterPasswortVisible,
                        decoration: InputDecoration(
                          hintText: 'Passwort fuer das PFX-Zertifikat',
                          prefixIcon: const Icon(Icons.lock_outline, size: 20),
                          suffixIcon: IconButton(
                            icon: Icon(
                              elsterPasswortVisible ? Icons.visibility_off : Icons.visibility,
                              size: 20,
                              color: Colors.grey.shade600,
                            ),
                            onPressed: () => setLocalState(() => elsterPasswortVisible = !elsterPasswortVisible),
                          ),
                          isDense: true,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        ),
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Das Passwort wurde beim Erstellen des ELSTER-Zertifikats festgelegt (mind. 6 Zeichen).',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 12),

                      // Warning: Keep certificate safe
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.amber.shade300),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.warning_amber_rounded, size: 18, color: Colors.amber.shade800),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Das Zertifikat und Passwort werden verschluesselt auf dem Server gespeichert. '
                                'Bewahren Sie die Original-PFX-Datei und das Passwort sicher auf — '
                                'bei Verlust muss ein neues Zertifikat bei ELSTER beantragt werden.',
                                style: TextStyle(fontSize: 11, color: Colors.amber.shade900),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ], // end if elsterKonto == 'ja'
                  ],
                ),
              ),
              const SizedBox(height: 24),

              // ── KORRESPONDENZ SECTION ──
              if (widget.apiService != null && widget.user != null) ...[
                _FinanzamtKorrespondenzSection(
                  apiService: widget.apiService!,
                  userId: widget.user!.id,
                ),
                const SizedBox(height: 24),
              ],

              // Save button
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: widget.isSaving(type) == true ? null : () {
                    final saveData = {
                      'dienststelle': dienststelleController.text.trim(),
                      'finanzamt_name': finanzamtNameController.text.trim(),
                      'steuer_id': steuerIdController.text.trim(),
                      'steuernummer': '',
                      'steuerklasse': steuerklasse,
                      'elster_konto': elsterKonto,
                      'elster_benutzername': elsterBenutzernameController.text.trim(),
                      'elster_aktivierungs_id': elsterAktivierungsIdController.text.trim(),
                      'elster_zertifikat_base64': elsterZertifikatBase64,
                      'elster_zertifikat_name': elsterZertifikatName,
                      'elster_zertifikat_passwort': elsterPasswortController.text.trim(),
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

  Widget _finanzamtInfoRow(IconData icon, String text, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
        ],
      ),
    );
  }

  static String _formatCurrency(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write('.');
      buffer.write(str[i]);
    }
    return '$buffer EUR';
  }

  static const Map<String, Map<String, String>> _finanzamtDaten = {
    'Finanzamt Neu-Ulm': {
      'adresse': 'Nelsonallee 5, 89231 Neu-Ulm',
      'telefon': '0731 7045-0',
      'fax': '0731 7045-500',
      'email': 'poststelle.fa-nu@finanzamt.bayern.de',
      'website': 'https://www.finanzamt.bayern.de/Neu-Ulm/',
      'oeffnungszeiten': 'Mo-Mi: 7:30-13:00\nDo: 7:30-13:00, 14:00-18:00\nFr: 7:30-12:00',
      'termin_telefon': '0731 7045-105',
      'termin_url': 'https://elster.de/eportal/nutzerterminvereinbarung?service-zentrum=Neu-Ulm',
    },
  };

  Widget _finanzamtKontaktRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 14, color: Colors.blue.shade400),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: Colors.blue.shade700))),
        ],
      ),
    );
  }

  Map<String, Map<String, String>> _getFinanzamtDatenMap() {
    if (_dbFinanzamtDaten.isNotEmpty) {
      return _dbFinanzamtDaten;
    }
    return _finanzamtDaten;
  }
}

// ═══════════════════════════════════════════════════════════
// KORRESPONDENZ — separate widget (eigener State, kein Konflikt)
// ═══════════════════════════════════════════════════════════

class _FinanzamtKorrespondenzSection extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  const _FinanzamtKorrespondenzSection({required this.apiService, required this.userId});
  @override
  State<_FinanzamtKorrespondenzSection> createState() => _FinanzamtKorrespondenzSectionState();
}

class _FinanzamtKorrespondenzSectionState extends State<_FinanzamtKorrespondenzSection> {
  List<Map<String, dynamic>> _docs = [];
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final result = await widget.apiService.getFinanzamtKorrespondenz(widget.userId);
      if (result['success'] == true && result['data'] is List) {
        _docs = (result['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    } catch (e) {
      debugPrint('[Korrespondenz] load error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  String _fmtDateDE(DateTime dt) =>
      '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year}';

  String _toISO(DateTime dt) =>
      '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

  Future<void> _uploadBrief() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'],
      dialogTitle: 'Brief vom Finanzamt hochladen',
    );
    if (result == null || result.files.isEmpty || result.files.first.path == null) return;
    final file = result.files.first;
    if (!mounted) return;
    final titelC = TextEditingController(text: file.name.split('.').first);
    final datumC = TextEditingController(text: _fmtDateDE(DateTime.now()));
    DateTime selectedDate = DateTime.now();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.upload_file, color: Colors.deepPurple.shade700, size: 22),
          const SizedBox(width: 8),
          const Text('Brief hinzufügen', style: TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titelC, decoration: InputDecoration(labelText: 'Betreff / Titel', hintText: 'z.B. Steuerbescheid 2024', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 12),
          StatefulBuilder(builder: (ctx2, setLocal) => TextField(
            controller: datumC, readOnly: true,
            decoration: InputDecoration(labelText: 'Datum des Schreibens', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
                final picked = await showDatePicker(context: ctx2, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)), locale: const Locale('de'));
                if (picked != null) { selectedDate = picked; setLocal(() => datumC.text = _fmtDateDE(picked)); }
              })),
          )),
          const SizedBox(height: 12),
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
            child: Row(children: [Icon(Icons.attach_file, size: 16, color: Colors.grey.shade600), const SizedBox(width: 6),
              Expanded(child: Text(file.name, style: TextStyle(fontSize: 12, color: Colors.grey.shade700), overflow: TextOverflow.ellipsis)),
              Text('${(file.size / 1024).toStringAsFixed(0)} KB', style: TextStyle(fontSize: 11, color: Colors.grey.shade500))])),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.upload, size: 16), label: const Text('Hochladen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.uploadFinanzamtKorrespondenz(userId: widget.userId, typ: 'brief', titel: titelC.text.trim(), datum: _toISO(selectedDate), filePath: file.path!, fileName: file.name);
      if (res['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Brief hochgeladen'), backgroundColor: Colors.green.shade600));
        await _load();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${res['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _addEmail() async {
    if (!mounted) return;
    final titelC = TextEditingController();
    final absenderC = TextEditingController(text: 'Finanzamt');
    final inhaltC = TextEditingController();
    final datumC = TextEditingController(text: _fmtDateDE(DateTime.now()));
    DateTime selectedDate = DateTime.now();
    PlatformFile? attachment;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDialogState) => AlertDialog(
        title: Row(children: [Icon(Icons.email, color: Colors.deepPurple.shade700, size: 22), const SizedBox(width: 8), const Text('E-Mail hinzufügen', style: TextStyle(fontSize: 16))]),
        content: SizedBox(width: 450, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: titelC, decoration: InputDecoration(labelText: 'Betreff', hintText: 'z.B. Ihre Einkommensteuererklärung 2024', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: TextField(controller: absenderC, decoration: InputDecoration(labelText: 'Absender', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: datumC, readOnly: true, decoration: InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.calendar_today, size: 18), onPressed: () async {
                final picked = await showDatePicker(context: ctx2, initialDate: selectedDate, firstDate: DateTime(2020), lastDate: DateTime.now().add(const Duration(days: 30)), locale: const Locale('de'));
                if (picked != null) { selectedDate = picked; setDialogState(() => datumC.text = _fmtDateDE(picked)); }
              })))),
          ]),
          const SizedBox(height: 10),
          TextField(controller: inhaltC, maxLines: 6, decoration: InputDecoration(labelText: 'Inhalt der E-Mail', hintText: 'Text der E-Mail hier einfügen...', alignLabelWithHint: true, isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
          const SizedBox(height: 10),
          Row(children: [
            OutlinedButton.icon(onPressed: () async {
              final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
              if (res != null && res.files.isNotEmpty) setDialogState(() => attachment = res.files.first);
            }, icon: const Icon(Icons.attach_file, size: 16), label: Text(attachment != null ? 'Anhang ändern' : 'Anhang hinzufügen (optional)', style: const TextStyle(fontSize: 11)),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6))),
            if (attachment != null) ...[const SizedBox(width: 8),
              Expanded(child: Text(attachment!.name, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), overflow: TextOverflow.ellipsis)),
              IconButton(icon: Icon(Icons.close, size: 16, color: Colors.red.shade400), onPressed: () => setDialogState(() => attachment = null), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24))],
          ]),
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          ElevatedButton.icon(onPressed: () => Navigator.pop(ctx, true), icon: const Icon(Icons.save, size: 16), label: const Text('Speichern'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple, foregroundColor: Colors.white)),
        ],
      )),
    );
    if (confirmed != true) return;
    setState(() => _loading = true);
    try {
      final res = await widget.apiService.uploadFinanzamtKorrespondenz(
        userId: widget.userId, typ: 'email',
        titel: titelC.text.trim().isEmpty ? 'E-Mail vom ${datumC.text}' : titelC.text.trim(),
        datum: _toISO(selectedDate), absender: absenderC.text.trim(), inhalt: inhaltC.text.trim(),
        filePath: attachment?.path, fileName: attachment?.name);
      debugPrint('[Korrespondenz] Email upload result: $res');
      if (res['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('E-Mail gespeichert'), backgroundColor: Colors.green.shade600));
        await _load();
      } else {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: ${res['message']}'), backgroundColor: Colors.red));
      }
    } catch (e) {
      debugPrint('[Korrespondenz] Email upload error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _viewDoc(Map<String, dynamic> doc) async {
    if (!mounted) return;
    final typ = doc['typ']?.toString() ?? 'brief';
    final isEmail = typ == 'email';
    final inhalt = doc['inhalt']?.toString() ?? '';
    final dateiName = doc['datei_name']?.toString() ?? '';
    final hasFile = dateiName.isNotEmpty;

    await showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(length: 2, child: Dialog(
        insetPadding: const EdgeInsets.all(24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SizedBox(width: 550, height: 500, child: Column(children: [
          Container(padding: const EdgeInsets.fromLTRB(16, 14, 8, 0), child: Row(children: [
            Icon(isEmail ? Icons.email : Icons.mail, size: 22, color: Colors.deepPurple.shade700),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(doc['titel']?.toString() ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${doc['datum'] ?? ''} ${doc['absender']?.toString().isNotEmpty == true ? '· Von: ${doc['absender']}' : ''}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ])),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
          ])),
          TabBar(labelColor: Colors.deepPurple.shade700, unselectedLabelColor: Colors.grey.shade500, indicatorColor: Colors.deepPurple.shade700,
            tabs: const [Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'), Tab(icon: Icon(Icons.folder_open, size: 18), text: 'Dokument')]),
          Expanded(child: TabBarView(children: [
            // Tab 1: Details
            SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: isEmail ? Colors.blue.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(6)),
                  child: Text(isEmail ? 'E-Mail' : 'Brief/Schreiben', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isEmail ? Colors.blue.shade700 : Colors.orange.shade700))),
                const Spacer(),
                Text(doc['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              ]),
              const SizedBox(height: 12),
              Text('Betreff', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
              const SizedBox(height: 2),
              Text(doc['titel']?.toString() ?? '–', style: const TextStyle(fontSize: 14)),
              const SizedBox(height: 12),
              if (doc['absender']?.toString().isNotEmpty == true) ...[
                Text('Absender', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                const SizedBox(height: 2),
                Text(doc['absender'].toString(), style: const TextStyle(fontSize: 14)),
                const SizedBox(height: 12),
              ],
              if (inhalt.isNotEmpty) ...[
                Text('Inhalt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                const SizedBox(height: 4),
                Container(width: double.infinity, padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                  child: SelectableText(inhalt, style: const TextStyle(fontSize: 13, height: 1.5))),
              ],
              if (!isEmail && inhalt.isEmpty) ...[
                const SizedBox(height: 20),
                Center(child: Column(children: [
                  Icon(Icons.description, size: 40, color: Colors.grey.shade300),
                  const SizedBox(height: 8),
                  Text('Schreiben ohne Text — siehe Dokument-Tab', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
                ])),
              ],
            ])),
            // Tab 2: Dokument
            Padding(padding: const EdgeInsets.all(16), child: hasFile
              ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
                    child: Row(children: [
                      Icon(dateiName.toLowerCase().endsWith('.pdf') ? Icons.picture_as_pdf : Icons.image, size: 28,
                        color: dateiName.toLowerCase().endsWith('.pdf') ? Colors.red.shade600 : Colors.blue.shade600),
                      const SizedBox(width: 10),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(dateiName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                        if ((int.tryParse(doc['datei_groesse']?.toString() ?? '0') ?? 0) > 0)
                          Text('${((int.tryParse(doc['datei_groesse']?.toString() ?? '0') ?? 0) / 1024).toStringAsFixed(0)} KB', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ])),
                    ])),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _downloadAndOpen(doc); },
                    icon: const Icon(Icons.visibility, size: 18), label: const Text('Dokument anzeigen'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
                ])
              : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Spacer(),
                  Icon(Icons.folder_off, size: 48, color: Colors.grey.shade300),
                  const SizedBox(height: 10),
                  Text('Kein Dokument angehängt', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
                  const SizedBox(height: 16),
                  SizedBox(width: double.infinity, child: ElevatedButton.icon(
                    onPressed: () async {
                      final res = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png']);
                      if (res == null || res.files.isEmpty || res.files.first.path == null) return;
                      final file = res.files.first;
                      if (!context.mounted) return;
                      Navigator.pop(ctx);
                      final docId = int.tryParse(doc['id']?.toString() ?? '');
                      if (docId == null) return;
                      setState(() => _loading = true);
                      try {
                        final uploadRes = await widget.apiService.uploadFinanzamtKorrespondenz(
                          userId: widget.userId, typ: doc['typ']?.toString() ?? 'email', titel: doc['titel']?.toString() ?? '',
                          datum: doc['datum']?.toString() ?? '', absender: doc['absender']?.toString() ?? '', inhalt: doc['inhalt']?.toString() ?? '',
                          filePath: file.path!, fileName: file.name);
                        if (uploadRes['success'] == true) {
                          await widget.apiService.deleteFinanzamtKorrespondenz(docId);
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Dokument hochgeladen'), backgroundColor: Colors.green.shade600));
                          await _load();
                        }
                      } catch (e) {
                        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                      }
                      if (mounted) setState(() => _loading = false);
                    },
                    icon: const Icon(Icons.upload_file, size: 18), label: const Text('Dokument hochladen'),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 12)))),
                  const Spacer(),
                ])),
          ])),
        ])),
      )),
    );
  }

  Future<void> _downloadAndOpen(Map<String, dynamic> doc) async {
    final docId = int.tryParse(doc['id']?.toString() ?? '');
    if (docId == null) return;
    try {
      final response = await widget.apiService.downloadFinanzamtKorrespondenz(docId);
      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        final fileName = doc['datei_name']?.toString() ?? 'dokument';
        final ext = fileName.split('.').last.toLowerCase();
        if (!mounted) return;
        if (['jpg', 'jpeg', 'png', 'bmp', 'tiff'].contains(ext)) {
          showDialog(context: context, builder: (ctx) {
            double rotation = 0;
            return StatefulBuilder(builder: (ctx2, setDlg) => Dialog(
              insetPadding: const EdgeInsets.all(16),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AppBar(title: Text(fileName, style: const TextStyle(fontSize: 14)), automaticallyImplyLeading: false, actions: [
                  IconButton(icon: const Icon(Icons.rotate_right), onPressed: () => setDlg(() => rotation += 90), tooltip: 'Drehen'),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(ctx)),
                ]),
                Expanded(child: InteractiveViewer(constrained: false, boundaryMargin: const EdgeInsets.all(double.infinity), minScale: 0.5, maxScale: 5,
                  child: Transform.rotate(angle: rotation * 3.14159265 / 180, child: Image.memory(bytes)))),
              ]),
            ));
          });
        } else {
          final dir = await getTemporaryDirectory();
          final tempFile = File('${dir.path}/$fileName');
          await tempFile.writeAsBytes(bytes);
          await OpenFilex.open(tempFile.path);
        }
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteDoc(Map<String, dynamic> doc) async {
    final docId = int.tryParse(doc['id']?.toString() ?? '');
    if (docId == null) return;
    final confirmed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Korrespondenz löschen?', style: TextStyle(fontSize: 16)),
      content: Text('"${doc['titel']}" wirklich löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        ElevatedButton(onPressed: () => Navigator.pop(ctx, true), style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white), child: const Text('Löschen')),
      ],
    ));
    if (confirmed != true) return;
    try {
      final result = await widget.apiService.deleteFinanzamtKorrespondenz(docId);
      if (result['success'] == true) {
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: const Text('Gelöscht'), backgroundColor: Colors.green.shade600));
        await _load();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity, padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [Colors.deepPurple.shade50, Colors.deepPurple.shade100], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.deepPurple.shade200)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.mail, size: 22, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Text('Korrespondenz', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade800)),
          const Spacer(),
          Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: Colors.deepPurple.shade700, borderRadius: BorderRadius.circular(12)),
            child: Text('${_docs.length}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold))),
        ]),
        const SizedBox(height: 4),
        Text('Schreiben und E-Mails vom Finanzamt', style: TextStyle(fontSize: 12, color: Colors.deepPurple.shade500)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: _loading ? null : _addEmail,
            icon: _loading ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.email_outlined, size: 16),
            label: const Text('E-Mail hinzufügen', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple.shade700, side: BorderSide(color: Colors.deepPurple.shade300), padding: const EdgeInsets.symmetric(vertical: 8)))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(
            onPressed: _loading ? null : _uploadBrief,
            icon: const Icon(Icons.upload_file, size: 16),
            label: const Text('Brief hinzufügen', style: TextStyle(fontSize: 11)),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.deepPurple.shade700, side: BorderSide(color: Colors.deepPurple.shade300), padding: const EdgeInsets.symmetric(vertical: 8)))),
        ]),
        const SizedBox(height: 10),
        if (_loading && _docs.isEmpty)
          const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
        else if (_docs.isEmpty)
          Container(width: double.infinity, padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(8)),
            child: Column(children: [Icon(Icons.inbox, size: 32, color: Colors.grey.shade400), const SizedBox(height: 6),
              Text('Keine Korrespondenz vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500))]))
        else
          ...List.generate(_docs.length, (i) {
            final doc = _docs[i];
            final typ = doc['typ']?.toString() ?? 'brief';
            final isEmail = typ == 'email';
            final dateiName = doc['datei_name']?.toString() ?? '';
            final ext = dateiName.isNotEmpty ? dateiName.split('.').last.toLowerCase() : '';
            final isPdf = ext == 'pdf';
            final isImage = ['jpg', 'jpeg', 'png', 'bmp', 'tiff'].contains(ext);
            final groesse = int.tryParse(doc['datei_groesse']?.toString() ?? '0') ?? 0;
            return InkWell(
              onTap: () => _viewDoc(doc),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                margin: EdgeInsets.only(bottom: i < _docs.length - 1 ? 6 : 0),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8), border: Border.all(color: isEmail ? Colors.blue.shade100 : Colors.deepPurple.shade100)),
                child: Row(children: [
                  Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: isEmail ? Colors.blue.shade50 : isPdf ? Colors.red.shade50 : isImage ? Colors.green.shade50 : Colors.grey.shade50, borderRadius: BorderRadius.circular(8)),
                    child: Icon(isEmail ? Icons.email : isPdf ? Icons.picture_as_pdf : isImage ? Icons.image : Icons.description, size: 20,
                      color: isEmail ? Colors.blue.shade600 : isPdf ? Colors.red.shade600 : isImage ? Colors.green.shade600 : Colors.grey.shade600)),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(doc['titel']?.toString() ?? dateiName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey.shade800), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: isEmail ? Colors.blue.shade50 : Colors.orange.shade50, borderRadius: BorderRadius.circular(4)),
                        child: Text(isEmail ? 'E-Mail' : 'Brief', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isEmail ? Colors.blue.shade700 : Colors.orange.shade700))),
                      const SizedBox(width: 6),
                      Text(doc['datum']?.toString() ?? '', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      if (doc['absender']?.toString().isNotEmpty == true) ...[const SizedBox(width: 6), Text('von ${doc['absender']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade400))],
                      if (dateiName.isNotEmpty && !isEmail) ...[const SizedBox(width: 6), Flexible(child: Text(dateiName, style: TextStyle(fontSize: 10, color: Colors.grey.shade400), overflow: TextOverflow.ellipsis))],
                      if (groesse > 0) ...[const SizedBox(width: 4), Text('${(groesse / 1024).toStringAsFixed(0)} KB', style: TextStyle(fontSize: 10, color: Colors.grey.shade400))],
                    ]),
                  ])),
                  IconButton(icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400), onPressed: () => _deleteDoc(doc), tooltip: 'Löschen', padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                ]),
              ),
            );
          }),
      ]),
    );
  }
}
