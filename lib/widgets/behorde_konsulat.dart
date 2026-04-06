import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../screens/webview_screen.dart';

class BehordeKonsulatContent extends StatefulWidget {
  final ApiService apiService;
  final TicketService ticketService;
  final String adminMitgliedernummer;
  final String clientMitgliedernummer;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;

  const BehordeKonsulatContent({
    super.key,
    required this.apiService,
    required this.ticketService,
    required this.adminMitgliedernummer,
    required this.clientMitgliedernummer,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
  });

  @override
  State<BehordeKonsulatContent> createState() => _BehordeKonsulatContentState();
}

class _BehordeKonsulatContentState extends State<BehordeKonsulatContent> {
  static const type = 'konsulat';
  Map<String, dynamic> _localData = {};
  bool _loaded = false;
  bool _editing = false;

  // eConsulat controllers
  late TextEditingController ecEmailC;
  late TextEditingController ecPasswortC;
  // Pasaport verification
  late TextEditingController passCnpC;
  late TextEditingController passDataDepunereC;
  late TextEditingController passNrCerereC;
  bool _ecPasswortVisible = false;
  // Termine + Anträge
  List<Map<String, dynamic>> _termine = [];
  List<Map<String, dynamic>> _antraege = [];

  static const List<String> _antragArten = [
    'Antrag Reisepass',
    'Abholen Reisepass',
    'Antrag Personalausweis (Buletin)',
    'Abholen Personalausweis',
    'Geburtsurkunde (Certificat naștere)',
    'Heiratsurkunde (Certificat căsătorie)',
    'Sterbeurkunde (Certificat deces)',
    'Vollmacht (Procură)',
    'Beglaubigung (Legalizare)',
    'Apostille',
    'Führungszeugnis (Cazier judiciar)',
    'Staatsbürgerschaft (Cetățenie)',
    'Reisetitel (Titlu de călătorie)',
    'Übersetzung / Beglaubigte Kopie',
    'Sonstiges',
  ];
  // Edit mode controllers
  late TextEditingController editNameC;
  late TextEditingController editAdresseC;
  late TextEditingController editPlzOrtC;
  late TextEditingController editTelefonC;
  late TextEditingController editEmailC;
  late TextEditingController editWebsiteC;

  // Hardcoded consulates (Romania in Germany)
  static const List<Map<String, String>> _konsulate = [
    {
      'name': 'Generalkonsulat von Rumänien in Stuttgart',
      'adresse': 'Hauptstätter Str. 70',
      'plz_ort': '70178 Stuttgart',
      'telefon': '+49 711 62008-0',
      'email': 'stuttgart@mae.ro',
      'website': 'https://stuttgart.mae.ro',
      'land': 'Rumänien',
      'oeffnungszeiten': 'Mo-Do: 08:00-14:00 | Fr: 08:00-12:00',
      'callcenter': 'contact@informatiiconsulare.ro',
      'notfall': '',
      'anfahrt': '',
      'feiertage': '',
    },
    {
      'name': 'Generalkonsulat von Rumänien in München',
      'adresse': 'Richard-Strauss-Straße 149',
      'plz_ort': '81679 München',
      'telefon': '+49 89 553307 / +49 89 98106143',
      'email': 'munchen@mae.ro',
      'email_behoerden': 'munchen@mae.ro, Fax: +49 89 553348',
      'callcenter': 'contact@informatiiconsulare.ro',
      'notfall': '+49 160 2087789 (nur dringende Notfälle)',
      'website': 'https://munchen.mae.ro',
      'land': 'Rumänien',
      'oeffnungszeiten': 'Mo-Do: 08:00-14:00 (Notarielle Unterlagen, Reisepass, Personalausweis nur mit Termin; Reisetitel ohne Termin; Abholung Reisepässe)\nFr: 08:00-12:00 (Notarielle Unterlagen, Reisepass, Personalausweis, Staatsangehörigkeit nur mit Termin; Reisetitel ohne Termin)',
      'anfahrt': 'Tram 36 (Effnerplatz), Bus 154/59 (Effnerplatz), Bus 187/188/189 (Richard-Strauß-Str.), U4 (Richard-Strauß-Str.). Parkmöglichkeiten begrenzt — Arabellapark kostenpflichtig.',
      'feiertage': '2025: 1, 2, 6, 7, 24 Jan; 18-21 Apr; 1 Mai; 1, 9 Jun; 15 Aug; 30 Nov; 1, 25, 26 Dez',
    },
    {
      'name': 'Generalkonsulat von Rumänien in Bonn',
      'adresse': 'Legionsweg 14',
      'plz_ort': '53117 Bonn',
      'telefon': '+49 228 68380-0',
      'email': 'bonn@mae.ro',
      'website': 'https://bonn.mae.ro',
      'land': 'Rumänien',
      'oeffnungszeiten': 'Mo-Do: 08:00-14:00 | Fr: 08:00-12:00',
      'callcenter': 'contact@informatiiconsulare.ro',
      'notfall': '',
      'anfahrt': '',
      'feiertage': '',
    },
    {
      'name': 'Botschaft von Rumänien in Berlin',
      'adresse': 'Dorotheenstr. 62-66',
      'plz_ort': '10117 Berlin',
      'telefon': '+49 30 21239-202',
      'email': 'berlin@mae.ro',
      'website': 'https://berlin.mae.ro',
      'land': 'Rumänien',
      'oeffnungszeiten': 'Mo-Fr: 08:30-16:30',
      'callcenter': 'contact@informatiiconsulare.ro',
      'notfall': '',
      'anfahrt': '',
      'feiertage': '',
    },
  ];

  @override
  void initState() {
    super.initState();
    ecEmailC = TextEditingController();
    ecPasswortC = TextEditingController();
    passCnpC = TextEditingController();
    passDataDepunereC = TextEditingController();
    passNrCerereC = TextEditingController();
    editNameC = TextEditingController();
    editAdresseC = TextEditingController();
    editPlzOrtC = TextEditingController();
    editTelefonC = TextEditingController();
    editEmailC = TextEditingController();
    editWebsiteC = TextEditingController();
  }

  @override
  void dispose() {
    ecEmailC.dispose();
    ecPasswortC.dispose();
    passCnpC.dispose();
    passDataDepunereC.dispose();
    passNrCerereC.dispose();
    editNameC.dispose();
    editAdresseC.dispose();
    editPlzOrtC.dispose();
    editTelefonC.dispose();
    editEmailC.dispose();
    editWebsiteC.dispose();
    super.dispose();
  }

  void _initFromData(Map<String, dynamic> data) {
    if (_loaded) return;
    _localData = Map<String, dynamic>.from(data);
    ecEmailC.text = data['econsulat_email'] ?? '';
    ecPasswortC.text = data['econsulat_passwort'] ?? '';
    passCnpC.text = data['pass_cnp'] ?? '';
    passDataDepunereC.text = data['pass_data_depunere'] ?? '';
    passNrCerereC.text = data['pass_nr_cerere'] ?? '';
    if (data['termine'] is List) {
      _termine = (data['termine'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    if (data['antraege'] is List) {
      _antraege = (data['antraege'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }
    _loaded = true;
  }

  void _save() {
    widget.saveData(type, {
      ..._localData,
      'econsulat_email': ecEmailC.text.trim(),
      'econsulat_passwort': ecPasswortC.text.trim(),
      'pass_cnp': passCnpC.text.trim(),
      'pass_data_depunere': passDataDepunereC.text.trim(),
      'pass_nr_cerere': passNrCerereC.text.trim(),
      'termine': _termine,
      'antraege': _antraege,
    });
  }

  void _selectKonsulat(Map<String, String> k) {
    setState(() {
      _localData = {
        ..._localData,
        'konsulat_name': k['name'] ?? '',
        'konsulat_adresse': k['adresse'] ?? '',
        'konsulat_plz_ort': k['plz_ort'] ?? '',
        'konsulat_telefon': k['telefon'] ?? '',
        'konsulat_email': k['email'] ?? '',
        'konsulat_website': k['website'] ?? '',
        'konsulat_land': k['land'] ?? '',
        'konsulat_oeffnungszeiten': k['oeffnungszeiten'] ?? '',
        'konsulat_callcenter': k['callcenter'] ?? '',
        'konsulat_notfall': k['notfall'] ?? '',
        'konsulat_anfahrt': k['anfahrt'] ?? '',
        'konsulat_feiertage': k['feiertage'] ?? '',
      };
    });
    _save();
  }

  void _clearKonsulat() {
    setState(() {
      _localData = {};
      ecEmailC.text = '';
      ecPasswortC.text = '';
      passCnpC.text = '';
      passDataDepunereC.text = '';
      passNrCerereC.text = '';
      _loaded = false;
      _editing = false;
    });
    widget.saveData(type, {});
  }

  void _showDetailsDialog() {
    showDialog(
      context: context,
      builder: (dlgCtx) => AlertDialog(
        title: Row(children: [
          Icon(Icons.account_balance, size: 22, color: Colors.red.shade700),
          const SizedBox(width: 10),
          Expanded(child: Text(_localData['konsulat_name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800))),
        ]),
        content: SizedBox(
          width: 450,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailRow(Icons.flag, 'Land', _localData['konsulat_land'] ?? ''),
                _detailRow(Icons.location_on, 'Adresse', '${_localData['konsulat_adresse'] ?? ''}${(_localData['konsulat_plz_ort'] ?? '').toString().isNotEmpty ? ', ${_localData['konsulat_plz_ort']}' : ''}'),
                _detailRow(Icons.phone, 'Telefon', _localData['konsulat_telefon'] ?? ''),
                _detailRow(Icons.email, 'E-Mail', _localData['konsulat_email'] ?? ''),
                _detailRow(Icons.language, 'Website', _localData['konsulat_website'] ?? ''),
                if (ecEmailC.text.isNotEmpty) ...[
                  const Divider(height: 20),
                  _detailRow(Icons.cloud, 'eConsulat E-Mail', ecEmailC.text),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dlgCtx), child: const Text('Schließen')),
          if ((_localData['konsulat_website'] ?? '').toString().isNotEmpty)
            OutlinedButton.icon(
              icon: const Icon(Icons.language, size: 16),
              label: const Text('Website öffnen'),
              onPressed: () {
                Navigator.pop(dlgCtx);
                Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewScreen(
                  url: _localData['konsulat_website'],
                  title: _localData['konsulat_name'] ?? 'Konsulat',
                )));
              },
            ),
          FilledButton.icon(
            icon: const Icon(Icons.edit, size: 16),
            label: const Text('Bearbeiten'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () {
              Navigator.pop(dlgCtx);
              _startEditing();
            },
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.red.shade400),
        const SizedBox(width: 10),
        SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  void _startEditing() {
    editNameC.text = _localData['konsulat_name'] ?? '';
    editAdresseC.text = _localData['konsulat_adresse'] ?? '';
    editPlzOrtC.text = _localData['konsulat_plz_ort'] ?? '';
    editTelefonC.text = _localData['konsulat_telefon'] ?? '';
    editEmailC.text = _localData['konsulat_email'] ?? '';
    editWebsiteC.text = _localData['konsulat_website'] ?? '';
    setState(() => _editing = true);
  }

  void _saveEdit() {
    setState(() {
      _localData['konsulat_name'] = editNameC.text.trim();
      _localData['konsulat_adresse'] = editAdresseC.text.trim();
      _localData['konsulat_plz_ort'] = editPlzOrtC.text.trim();
      _localData['konsulat_telefon'] = editTelefonC.text.trim();
      _localData['konsulat_email'] = editEmailC.text.trim();
      _localData['konsulat_website'] = editWebsiteC.text.trim();
      _editing = false;
    });
    _save();
  }

  List<Widget> _buildOeffnungszeitenRows() {
    final text = _localData['konsulat_oeffnungszeiten']?.toString() ?? '';
    if (text.isEmpty) return [];
    final lines = text.split('\n');
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          Icon(Icons.access_time, size: 16, color: Colors.red.shade400),
          const SizedBox(width: 8),
          Text('Öffnungszeiten:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
        ]),
      ),
      ...lines.map((line) => Padding(
        padding: const EdgeInsets.only(left: 24, bottom: 4),
        child: Text(line.trim(), style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      )),
    ];
  }

  Widget _infoRow(IconData icon, String label, String value, Color color) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text('$label: ', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  Widget _editField(String label, TextEditingController controller, {IconData icon = Icons.edit, String hint = ''}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          prefixIcon: Icon(icon, size: 20),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          isDense: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.getData(type);
    if (data.isEmpty && !widget.isLoading(type) && !_loaded) {
      widget.loadData(type);
    }
    if (widget.isLoading(type)) {
      return const Center(child: CircularProgressIndicator());
    }

    _initFromData(data);

    final hasKonsulat = (_localData['konsulat_name'] ?? '').toString().isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.red.shade700, Colors.red.shade500]),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.account_balance, size: 32, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Konsulat', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white)),
                Text('Zuständiges Konsulat / Botschaft', style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8))),
              ])),
            ]),
          ),
          const SizedBox(height: 20),

          if (!hasKonsulat) ...[
            // === SELECT CONSULATE ===
            Text('Konsulat auswählen', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
            const SizedBox(height: 8),
            ..._konsulate.map((k) {
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: BorderSide(color: Colors.red.shade100)),
                child: InkWell(
                  onTap: () => _selectKonsulat(k),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(children: [
                      Icon(Icons.account_balance, size: 28, color: Colors.red.shade400),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(k['name']!, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                        Text('${k['adresse']}, ${k['plz_ort']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text(k['email']!, style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ])),
                      Icon(Icons.arrow_forward_ios, size: 16, color: Colors.red.shade300),
                    ]),
                  ),
                ),
              );
            }),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.amber.shade200)),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Icon(Icons.info_outline, size: 18, color: Colors.amber.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text('Falls Ihr Konsulat nicht aufgelistet ist, können Sie es nach Auswahl manuell bearbeiten.',
                    style: TextStyle(fontSize: 11, color: Colors.amber.shade800))),
              ]),
            ),
          ] else ...[
            // === SELECTED CONSULATE ===
            if (_editing) ...[
              // Edit mode
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.red.shade200)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.edit, size: 18, color: Colors.red.shade700),
                    const SizedBox(width: 8),
                    Text('Konsulat bearbeiten', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                  ]),
                  const SizedBox(height: 12),
                  _editField('Name', editNameC, icon: Icons.account_balance),
                  _editField('Adresse', editAdresseC, icon: Icons.location_on),
                  _editField('PLZ / Ort', editPlzOrtC, icon: Icons.place),
                  _editField('Telefon', editTelefonC, icon: Icons.phone),
                  _editField('E-Mail', editEmailC, icon: Icons.email),
                  _editField('Website', editWebsiteC, icon: Icons.language),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    TextButton(onPressed: () => setState(() => _editing = false), child: const Text('Abbrechen')),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      icon: const Icon(Icons.save, size: 16),
                      label: const Text('Speichern'),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: _saveEdit,
                    ),
                  ]),
                ]),
              ),
            ] else ...[
              // Display mode — Konsulat card
              InkWell(
                onTap: _showDetailsDialog,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                    boxShadow: [BoxShadow(color: Colors.red.shade50, blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(color: Colors.red.shade50, borderRadius: BorderRadius.circular(10)),
                        child: Icon(Icons.account_balance, size: 28, color: Colors.red.shade700),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(_localData['konsulat_name'] ?? '', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.red.shade800)),
                        if ((_localData['konsulat_land'] ?? '').toString().isNotEmpty)
                          Text(_localData['konsulat_land'], style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                      ])),
                      PopupMenuButton<String>(
                        icon: Icon(Icons.more_vert, color: Colors.grey.shade500),
                        onSelected: (v) {
                          if (v == 'edit') _startEditing();
                          if (v == 'details') _showDetailsDialog();
                          if (v == 'website') {
                            final url = _localData['konsulat_website']?.toString() ?? '';
                            if (url.isNotEmpty) {
                              Navigator.push(context, MaterialPageRoute(builder: (_) => WebViewScreen(
                                url: url,
                                title: _localData['konsulat_name'] ?? 'Konsulat',
                              )));
                            }
                          }
                          if (v == 'clear') _clearKonsulat();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'details', child: Row(children: [Icon(Icons.info_outline, size: 18), SizedBox(width: 8), Text('Details')])),
                          const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Bearbeiten')])),
                          if ((_localData['konsulat_website'] ?? '').toString().isNotEmpty)
                            const PopupMenuItem(value: 'website', child: Row(children: [Icon(Icons.language, size: 18), SizedBox(width: 8), Text('Website öffnen')])),
                          const PopupMenuItem(value: 'clear', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.red), SizedBox(width: 8), Text('Entfernen', style: TextStyle(color: Colors.red))])),
                        ],
                      ),
                    ]),
                    const SizedBox(height: 12),
                    _infoRow(Icons.location_on, 'Adresse', '${_localData['konsulat_adresse'] ?? ''}${(_localData['konsulat_plz_ort'] ?? '').toString().isNotEmpty ? ', ${_localData['konsulat_plz_ort']}' : ''}', Colors.red.shade400),
                    _infoRow(Icons.phone, 'Telefon', _localData['konsulat_telefon'] ?? '', Colors.red.shade400),
                    _infoRow(Icons.email, 'E-Mail', _localData['konsulat_email'] ?? '', Colors.red.shade400),
                    _infoRow(Icons.language, 'Website', _localData['konsulat_website'] ?? '', Colors.red.shade400),
                    if ((_localData['konsulat_oeffnungszeiten'] ?? '').toString().isNotEmpty) ...[
                      const Divider(height: 16),
                      ..._buildOeffnungszeitenRows(),
                    ],
                    if ((_localData['konsulat_notfall'] ?? '').toString().isNotEmpty)
                      _infoRow(Icons.emergency, 'Notfall', _localData['konsulat_notfall'], Colors.red.shade700),
                    if ((_localData['konsulat_callcenter'] ?? '').toString().isNotEmpty)
                      _infoRow(Icons.call, 'Call-Center', _localData['konsulat_callcenter'], Colors.blue.shade400),
                  ]),
                ),
              ),
              // Anfahrt
              if ((_localData['konsulat_anfahrt'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.directions_bus, size: 16, color: Colors.blue.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text(_localData['konsulat_anfahrt'], style: TextStyle(fontSize: 10, color: Colors.blue.shade700))),
                  ]),
                ),
              ],
              // Feiertage
              if ((_localData['konsulat_feiertage'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity, padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.event_busy, size: 16, color: Colors.amber.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Gesetzliche Feiertage (geschlossen)', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber.shade800)),
                      Text(_localData['konsulat_feiertage'], style: TextStyle(fontSize: 10, color: Colors.amber.shade700)),
                    ])),
                  ]),
                ),
              ],
              const SizedBox(height: 16),
              Text('Hinweis: Klicken Sie auf die Karte für Details', style: TextStyle(fontSize: 11, color: Colors.grey.shade400, fontStyle: FontStyle.italic)),
            ],

            const SizedBox(height: 20),

            const SizedBox(height: 20),

            // === eConsulat.ro Account ===
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.cloud, size: 22, color: Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Text('eConsulat.ro — Online-Konto', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                  const Spacer(),
                  TextButton.icon(
                    icon: Icon(Icons.open_in_browser, size: 16, color: Colors.blue.shade600),
                    label: Text('econsulat.ro', style: TextStyle(fontSize: 11, color: Colors.blue.shade600)),
                    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebViewScreen(
                      url: 'https://econsulat.ro',
                      title: 'eConsulat.ro',
                    ))),
                  ),
                ]),
                const SizedBox(height: 12),
                TextField(
                  controller: ecEmailC,
                  decoration: InputDecoration(
                    labelText: 'E-Mail (eConsulat)',
                    prefixIcon: const Icon(Icons.email, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  onChanged: (_) => _save(),
                ),
                const SizedBox(height: 10),
                StatefulBuilder(builder: (ctx, setPwState) => TextField(
                  controller: ecPasswortC,
                  obscureText: !_ecPasswortVisible,
                  decoration: InputDecoration(
                    labelText: 'Passwort (eConsulat)',
                    prefixIcon: const Icon(Icons.lock, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_ecPasswortVisible ? Icons.visibility_off : Icons.visibility, size: 20),
                      onPressed: () => setPwState(() => _ecPasswortVisible = !_ecPasswortVisible),
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                  onChanged: (_) => _save(),
                )),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    Icon(Icons.security, size: 16, color: Colors.green.shade700),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Zugangsdaten werden verschlüsselt (AES-256) auf dem Server gespeichert.',
                        style: TextStyle(fontSize: 10, color: Colors.green.shade700))),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 20),

            // === Passport Verification ===
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.indigo.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.indigo.shade200),
              ),
              child: StatefulBuilder(builder: (ctx, setPassState) {
                final searchMode = _localData['pass_search_mode']?.toString() ?? 'cnp';
                return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.menu_book, size: 22, color: Colors.indigo.shade700),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Verificare Status Emitere Pașaport ELECTRONIC', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                    TextButton.icon(
                      icon: Icon(Icons.open_in_browser, size: 16, color: Colors.indigo.shade600),
                      label: Text('Verificare', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebViewScreen(
                        url: 'https://hub.mai.gov.ro/epasapoarte/programari/verifica-pasaport/',
                        title: 'Verificare Pașaport',
                      ))),
                    ),
                  ]),
                  const SizedBox(height: 12),

                  // Search mode toggle
                  Row(children: [
                    Expanded(child: InkWell(
                      onTap: () {
                        setPassState(() => _localData['pass_search_mode'] = 'cnp');
                        _save();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: searchMode == 'cnp' ? Colors.indigo.shade600 : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade300),
                        ),
                        child: Center(child: Text('Nach CNP und Datum',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: searchMode == 'cnp' ? Colors.white : Colors.indigo.shade700))),
                      ),
                    )),
                    const SizedBox(width: 8),
                    Expanded(child: InkWell(
                      onTap: () {
                        setPassState(() => _localData['pass_search_mode'] = 'cerere');
                        _save();
                      },
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: searchMode == 'cerere' ? Colors.indigo.shade600 : Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.indigo.shade300),
                        ),
                        child: Center(child: Text('Nach Antragsnummer',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                color: searchMode == 'cerere' ? Colors.white : Colors.indigo.shade700))),
                      ),
                    )),
                  ]),
                  const SizedBox(height: 12),

                  if (searchMode == 'cnp') ...[
                    TextField(
                      controller: passCnpC,
                      decoration: InputDecoration(
                        labelText: 'CNP (ultimele 9 caractere)',
                        prefixIcon: const Icon(Icons.badge, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        hintText: 'XXXXXXXXX',
                        counterText: '${passCnpC.text.length}/9',
                      ),
                      maxLength: 9,
                      keyboardType: TextInputType.number,
                      onChanged: (_) {
                        setPassState(() {});
                        _save();
                      },
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: passDataDepunereC,
                      decoration: InputDecoration(
                        labelText: 'Data Depunerii Cererii',
                        prefixIcon: const Icon(Icons.calendar_today, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                        hintText: 'TT.MM.JJJJ',
                      ),
                      onChanged: (_) => _save(),
                    ),
                  ] else ...[
                    TextField(
                      controller: passNrCerereC,
                      decoration: InputDecoration(
                        labelText: 'Antragsnummer (Număr cerere)',
                        prefixIcon: const Icon(Icons.confirmation_number, size: 20),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      onChanged: (_) => _save(),
                    ),
                  ],
                  const SizedBox(height: 12),

                  // Button to open verification page
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.search, size: 18),
                      label: const Text('Status prüfen (Verificare)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.indigo.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WebViewScreen(
                        url: 'https://hub.mai.gov.ro/epasapoarte/programari/verifica-pasaport/',
                        title: 'Verificare Pașaport',
                      ))),
                    ),
                  ),
                ]);
              }),
            ),
            const SizedBox(height: 20),

            // === Konsularische Anträge ===
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.description, size: 22, color: Colors.teal.shade700),
                  const SizedBox(width: 8),
                  Text('Konsularische Anträge', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Neuer Antrag', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    onPressed: () => _showAntragDialog(),
                  ),
                ]),
                const SizedBox(height: 8),
                // Available services info
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Verfügbare Dienstleistungen:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade700)),
                    const SizedBox(height: 4),
                    Wrap(spacing: 6, runSpacing: 4, children: _antragArten.map((a) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.teal.shade200)),
                      child: Text(a, style: TextStyle(fontSize: 9, color: Colors.teal.shade700)),
                    )).toList()),
                  ]),
                ),
                const SizedBox(height: 12),
                if (_antraege.isEmpty)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      Icon(Icons.folder_open, size: 32, color: Colors.grey.shade400),
                      const SizedBox(height: 6),
                      Text('Keine Anträge vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ]),
                  )
                else
                  ..._antraege.asMap().entries.map((entry) {
                    final i = entry.key;
                    final a = entry.value;
                    final art = a['art']?.toString() ?? '';
                    final datum = a['datum']?.toString() ?? '';
                    final status = a['status']?.toString() ?? 'Eingereicht';
                    final notiz = a['notiz']?.toString() ?? '';

                    Color statusColor;
                    IconData statusIcon;
                    switch (status) {
                      case 'Geplant': statusColor = Colors.purple; statusIcon = Icons.schedule;
                      case 'Eingereicht': statusColor = Colors.blue; statusIcon = Icons.upload;
                      case 'In Bearbeitung': statusColor = Colors.orange; statusIcon = Icons.hourglass_top;
                      case 'Fertig zur Abholung': statusColor = Colors.green; statusIcon = Icons.check_circle;
                      case 'Abgeholt': statusColor = Colors.grey; statusIcon = Icons.done_all;
                      case 'Abgelehnt': statusColor = Colors.red; statusIcon = Icons.cancel;
                      default: statusColor = Colors.grey; statusIcon = Icons.help_outline;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                      ),
                      child: Row(children: [
                        Icon(statusIcon, size: 22, color: statusColor),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(art, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                          Row(children: [
                            Text(datum, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                              decoration: BoxDecoration(color: statusColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                              child: Text(status, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: statusColor)),
                            ),
                          ]),
                          if (notiz.isNotEmpty)
                            Text(notiz, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                        ])),
                        // Edit
                        IconButton(
                          icon: Icon(Icons.edit, size: 16, color: Colors.blueGrey.shade400),
                          onPressed: () => _showAntragDialog(index: i),
                          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                        // Delete
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                          onPressed: () {
                            final ticketId = int.tryParse(a['ticket_id']?.toString() ?? '');
                            if (ticketId != null) _deleteAntragTicket(ticketId);
                            setState(() => _antraege.removeAt(i));
                            _save();
                          },
                          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                      ]),
                    );
                  }),
              ]),
            ),
            const SizedBox(height: 20),

            // === Konsulat Termine ===
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.deepPurple.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.deepPurple.shade200),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.event, size: 22, color: Colors.deepPurple.shade700),
                  const SizedBox(width: 8),
                  Text('Konsulat-Termine', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.deepPurple.shade700)),
                  const Spacer(),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Neuer Termin', style: TextStyle(fontSize: 11)),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6)),
                    onPressed: () => _showTerminDialog(),
                  ),
                ]),
                const SizedBox(height: 12),
                if (_termine.isEmpty)
                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                    child: Column(children: [
                      Icon(Icons.event_busy, size: 32, color: Colors.grey.shade400),
                      const SizedBox(height: 6),
                      Text('Keine Termine vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                    ]),
                  )
                else
                  ..._termine.asMap().entries.map((entry) {
                    final i = entry.key;
                    final t = entry.value;
                    final art = t['art']?.toString() ?? '';
                    final datum = t['datum']?.toString() ?? '';
                    final uhrzeit = t['uhrzeit']?.toString() ?? '';
                    final notiz = t['notiz']?.toString() ?? '';
                    final erledigt = t['erledigt'] == true || t['erledigt'] == 'true';

                    IconData artIcon;
                    Color artColor;
                    switch (art) {
                      case 'Antrag Reisepass': artIcon = Icons.edit_document; artColor = Colors.blue;
                      case 'Abholen Reisepass': artIcon = Icons.check_circle; artColor = Colors.green;
                      case 'Antrag Personalausweis': artIcon = Icons.badge; artColor = Colors.orange;
                      case 'Abholen Personalausweis': artIcon = Icons.verified; artColor = Colors.teal;
                      case 'Beglaubigung': artIcon = Icons.approval; artColor = Colors.purple;
                      case 'Vollmacht': artIcon = Icons.description; artColor = Colors.brown;
                      case 'Sonstiges': artIcon = Icons.more_horiz; artColor = Colors.grey;
                      default: artIcon = Icons.event; artColor = Colors.deepPurple;
                    }

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: erledigt ? Colors.green.shade50 : Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: erledigt ? Colors.green.shade300 : Colors.deepPurple.shade100),
                      ),
                      child: Row(children: [
                        Icon(artIcon, size: 24, color: erledigt ? Colors.green.shade400 : artColor),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(art, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold,
                              color: erledigt ? Colors.green.shade700 : Colors.deepPurple.shade800,
                              decoration: erledigt ? TextDecoration.lineThrough : null)),
                          Text('$datum${uhrzeit.isNotEmpty ? ' um $uhrzeit' : ''}',
                              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                          if (notiz.isNotEmpty)
                            Text(notiz, style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                        ])),
                        // Toggle erledigt
                        IconButton(
                          icon: Icon(erledigt ? Icons.undo : Icons.check, size: 18,
                              color: erledigt ? Colors.orange : Colors.green),
                          tooltip: erledigt ? 'Nicht erledigt' : 'Erledigt',
                          onPressed: () {
                            setState(() => _termine[i]['erledigt'] = !erledigt);
                            _save();
                          },
                        ),
                        // Edit
                        IconButton(
                          icon: Icon(Icons.edit, size: 16, color: Colors.blueGrey.shade400),
                          onPressed: () => _showTerminDialog(index: i),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                        // Delete
                        IconButton(
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                          onPressed: () {
                            setState(() => _termine.removeAt(i));
                            _save();
                          },
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                      ]),
                    );
                  }),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Future<int?> _createAntragTicket(String art, String datum, String notiz) async {
    debugPrint('[Konsulat] Creating ticket: art=$art, datum=$datum');
    try {
      // Parse datum to find next weekday (Mo-Fr) for ticket
      DateTime? terminDate;
      try {
        terminDate = DateFormat('dd.MM.yyyy').parse(datum);
      } catch (_) {
        try {
          terminDate = DateFormat('d.M.yyyy').parse(datum);
        } catch (_) {}
      }

      // If date falls on weekend, move to Monday
      if (terminDate != null) {
        while (terminDate!.weekday == DateTime.saturday || terminDate.weekday == DateTime.sunday) {
          terminDate = terminDate.add(const Duration(days: 1));
        }
      }

      final konsulatName = _localData['konsulat_name']?.toString() ?? 'Konsulat';
      final terminDatum = terminDate != null ? DateFormat('dd.MM.yyyy').format(terminDate) : datum;

      final subject = 'Konsulat: $art — $terminDatum';
      final description = [
        'Konsulat: $konsulatName',
        'Art: $art',
        'Datum: $terminDatum',
        if (notiz.isNotEmpty) 'Notiz: $notiz',
        '',
        'Automatisch erstellt aus Konsulat-Anträge.',
      ].join('\n');

      // Convert dd.MM.yyyy to yyyy-MM-dd for scheduled_date
      String? scheduledDateStr;
      if (terminDate != null) {
        scheduledDateStr = '${terminDate.year}-${terminDate.month.toString().padLeft(2, '0')}-${terminDate.day.toString().padLeft(2, '0')}';
      }

      final result = await widget.ticketService.createTicket(
        mitgliedernummer: widget.clientMitgliedernummer,
        subject: subject,
        message: description,
        priority: 'medium',
        systemTicket: true,
        scheduledDate: scheduledDateStr,
      );

      final ticketId = result['ticket']?.id as int?;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket erstellt: $art — $terminDatum'), backgroundColor: Colors.green.shade600),
        );
      }
      return ticketId;
    } catch (e) {
      debugPrint('[Konsulat] Ticket create error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ticket-Fehler: $e'), backgroundColor: Colors.red),
        );
      }
      return null;
    }
  }

  Future<void> _deleteAntragTicket(int ticketId) async {
    try {
      await widget.ticketService.updateTicket(
        mitgliedernummer: widget.clientMitgliedernummer,
        ticketId: ticketId,
        action: 'close',
      );
      debugPrint('[Konsulat] Ticket $ticketId closed');
    } catch (e) {
      debugPrint('[Konsulat] Ticket close error: $e');
    }
  }

  void _showAntragDialog({int? index}) {
    final existing = index != null ? _antraege[index] : null;
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    String selectedArt = existing?['art']?.toString() ?? _antragArten.first;
    String selectedStatus = existing?['status']?.toString() ?? 'Eingereicht';

    final statusOptionen = ['Geplant', 'Eingereicht', 'In Bearbeitung', 'Fertig zur Abholung', 'Abgeholt', 'Abgelehnt'];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(Icons.description, size: 18, color: Colors.teal.shade700),
          const SizedBox(width: 8),
          Text(index != null ? 'Antrag bearbeiten' : 'Neuer Antrag', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 400, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: _antragArten.contains(selectedArt) ? selectedArt : _antragArten.first,
            decoration: InputDecoration(labelText: 'Art des Antrags', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: _antragArten.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) { if (v != null) setDlg(() => selectedArt = v); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: datumC,
            readOnly: true,
            decoration: InputDecoration(labelText: 'Datum eingereicht', hintText: 'TT.MM.JJJJ', isDense: true,
                prefixIcon: const Icon(Icons.calendar_today, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: ctx2,
                initialDate: now,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                locale: const Locale('de', 'DE'),
              );
              if (picked != null) {
                datumC.text = DateFormat('dd.MM.yyyy').format(picked);
              }
            },
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: statusOptionen.contains(selectedStatus) ? selectedStatus : statusOptionen.first,
            decoration: InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: statusOptionen.map((s) => DropdownMenuItem(value: s, child: Text(s, style: const TextStyle(fontSize: 12)))).toList(),
            onChanged: (v) { if (v != null) setDlg(() => selectedStatus = v); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notizC,
            decoration: InputDecoration(labelText: 'Notiz (optional)', isDense: true,
                prefixIcon: const Icon(Icons.note, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            maxLines: 2,
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: Text(index != null ? 'Speichern' : 'Hinzufügen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white),
            onPressed: () async {
              final datum = datumC.text.trim();
              final notiz = notizC.text.trim();
              final art = selectedArt;
              final status = selectedStatus;
              final antrag = {
                'art': art,
                'datum': datum,
                'status': status,
                'notiz': notiz,
              };
              final isNew = index == null;
              if (index != null) {
                _antraege[index] = antrag;
              } else {
                _antraege.add(antrag);
              }
              _save();
              Navigator.pop(ctx);

              // Update UI + create ticket
              setState(() {});
              if (isNew && datum.isNotEmpty) {
                final ticketId = await _createAntragTicket(art, datum, notiz);
                if (ticketId != null) {
                  _antraege.last['ticket_id'] = ticketId;
                  _save();
                }
              }
            },
          ),
        ],
      )),
    );
  }

  void _showTerminDialog({int? index}) {
    final existing = index != null ? _termine[index] : null;
    final datumC = TextEditingController(text: existing?['datum']?.toString() ?? '');
    final uhrzeitC = TextEditingController(text: existing?['uhrzeit']?.toString() ?? '');
    final notizC = TextEditingController(text: existing?['notiz']?.toString() ?? '');
    String selectedArt = existing?['art']?.toString() ?? 'Antrag Reisepass';

    final terminArten = [
      'Antrag Reisepass',
      'Abholen Reisepass',
      'Antrag Personalausweis',
      'Abholen Personalausweis',
      'Beglaubigung',
      'Vollmacht',
      'Sonstiges',
    ];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(Icons.event, size: 18, color: Colors.deepPurple.shade700),
          const SizedBox(width: 8),
          Text(index != null ? 'Termin bearbeiten' : 'Neuer Konsulat-Termin', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 380, child: Column(mainAxisSize: MainAxisSize.min, children: [
          DropdownButtonFormField<String>(
            initialValue: terminArten.contains(selectedArt) ? selectedArt : terminArten.first,
            decoration: InputDecoration(labelText: 'Art des Termins', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            items: terminArten.map((a) => DropdownMenuItem(value: a, child: Text(a, style: const TextStyle(fontSize: 13)))).toList(),
            onChanged: (v) { if (v != null) setDlg(() => selectedArt = v); },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: datumC,
            readOnly: true,
            decoration: InputDecoration(labelText: 'Datum', hintText: 'TT.MM.JJJJ', isDense: true,
                prefixIcon: const Icon(Icons.calendar_today, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            onTap: () async {
              final now = DateTime.now();
              final picked = await showDatePicker(
                context: ctx2,
                initialDate: now,
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
                locale: const Locale('de', 'DE'),
              );
              if (picked != null) {
                datumC.text = DateFormat('dd.MM.yyyy').format(picked);
              }
            },
          ),
          const SizedBox(height: 12),
          TextField(
            controller: uhrzeitC,
            decoration: InputDecoration(labelText: 'Uhrzeit (optional)', hintText: 'HH:MM', isDense: true,
                prefixIcon: const Icon(Icons.access_time, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notizC,
            decoration: InputDecoration(labelText: 'Notiz (optional)', isDense: true,
                prefixIcon: const Icon(Icons.note, size: 20),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            maxLines: 2,
          ),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          ElevatedButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: Text(index != null ? 'Speichern' : 'Hinzufügen'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white),
            onPressed: () {
              if (datumC.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Datum erforderlich'), backgroundColor: Colors.red));
                return;
              }
              final termin = {
                'art': selectedArt,
                'datum': datumC.text.trim(),
                'uhrzeit': uhrzeitC.text.trim(),
                'notiz': notizC.text.trim(),
                'erledigt': existing?['erledigt'] ?? false,
              };
              setState(() {
                if (index != null) {
                  _termine[index] = termin;
                } else {
                  _termine.add(termin);
                }
              });
              _save();
              Navigator.pop(ctx);
            },
          ),
        ],
      )),
    );
  }
}
