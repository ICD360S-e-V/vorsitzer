import 'package:flutter/material.dart';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';
import '../services/ticket_service.dart';
import '../models/user.dart';
import '../utils/file_picker_helper.dart';
import 'pflegebox_widget.dart';

class BehordeKrankenkasseContent extends StatefulWidget {
  final ApiService apiService;
  final TicketService ticketService;
  final User user;
  final String adminMitgliedernummer;
  final Map<String, dynamic> Function(String type) getData;
  final bool Function(String type) isLoading;
  final bool Function(String type) isSaving;
  final void Function(String type) loadData;
  final void Function(String type, Map<String, dynamic> data) saveData;
  final Widget Function(String type, TextEditingController controller) dienststelleBuilder;
  final Widget Function({required String behoerdeType, required String behoerdeLabel, required List<Map<String, dynamic>> termine, required Map<String, dynamic> data, required void Function(List<Map<String, dynamic>>) onChanged, required StateSetter setLocalState}) termineBuilder;
  final Future<void> Function(String type, String field, dynamic value) autoSaveField;

  const BehordeKrankenkasseContent({
    super.key,
    required this.apiService,
    required this.ticketService,
    required this.user,
    required this.adminMitgliedernummer,
    required this.getData,
    required this.isLoading,
    required this.isSaving,
    required this.loadData,
    required this.saveData,
    required this.dienststelleBuilder,
    required this.termineBuilder,
    required this.autoSaveField,
  });

  @override
  State<BehordeKrankenkasseContent> createState() => _BehordeKrankenkasseContentState();
}

class _BehordeKrankenkasseContentState extends State<BehordeKrankenkasseContent> {
  static const type = 'krankenkasse';

  // DB-loaded data (populated at runtime)
  final Map<int, Map<String, double>> _dbKrankenkassenZusatzbeitrag = {};
  final Map<String, double> _dbKrankenkassenRating = {};

  // Controllers (class-level to avoid memory leaks)
  final _dienststelleController = TextEditingController();
  final _krankenkasseNameController = TextEditingController();
  final _versichertennummerController = TextEditingController();
  final _kvnrController = TextEditingController();
  final _kartennummerController = TextEditingController();
  final _kartenfolgenummerController = TextEditingController();
  final _egkGueltigAbController = TextEditingController();
  final _egkGueltigBisController = TextEditingController();
  final _ehicKennummerController = TextEditingController();
  final _ehicInstitutionskennzeichenController = TextEditingController();
  final _pflegekasseNameController = TextEditingController();
  final _pflegegradSeitController = TextEditingController();
  final _befreiungGueltigBisController = TextEditingController();
  final _pflegeboxFirmaController = TextEditingController();
  final _pflegeboxDatumController = TextEditingController();
  final _pflegeboxNotizenController = TextEditingController();
  bool _controllersInitialized = false;

  // Class-level state (persists across tabs)
  String _versicherungsart = '';
  String _versichertenstatus = '';
  bool _befreiungskarte = false;
  String _befreiungJahr = '';
  String _pflegegrad = '';
  String _pflegeboxVersandart = '';
  String _pflegeboxStatus = '';
  int? _pflegeboxFirmaId;
  String _pflegeboxFirmaName = '';
  List<Map<String, dynamic>> _termine = [];

  void _initControllers(Map<String, dynamic> data) {
    if (!_controllersInitialized) {
      _dienststelleController.text = data['dienststelle'] ?? '';
      _krankenkasseNameController.text = data['name'] ?? '';
      _versichertennummerController.text = data['versichertennummer'] ?? '';
      _kvnrController.text = data['kvnr'] ?? '';
      _kartennummerController.text = data['kartennummer'] ?? '';
      _kartenfolgenummerController.text = data['kartenfolgenummer'] ?? '';
      _egkGueltigAbController.text = data['egk_gueltig_ab'] ?? '';
      _egkGueltigBisController.text = data['egk_gueltig_bis'] ?? '';
      _ehicKennummerController.text = data['ehic_kennnummer'] ?? '';
      _ehicInstitutionskennzeichenController.text = data['ehic_institutionskennzeichen'] ?? '';
      _pflegekasseNameController.text = (data['pflegekasse_name'] ?? '').toString().isNotEmpty ? data['pflegekasse_name'] : (data['name'] ?? '');
      _pflegegradSeitController.text = data['pflegegrad_seit'] ?? '';
      _befreiungGueltigBisController.text = data['befreiung_gueltig_bis'] ?? '';
      _pflegeboxFirmaController.text = data['pflegebox_firma'] ?? '';
      _pflegeboxDatumController.text = data['pflegebox_datum'] ?? '';
      _pflegeboxNotizenController.text = data['pflegebox_notizen'] ?? '';
      _versicherungsart = data['versicherungsart'] ?? '';
      _versichertenstatus = data['versichertenstatus'] ?? '';
      _befreiungskarte = data['befreiungskarte'] == true || data['befreiungskarte'] == 'true' || data['befreiungskarte'] == '1';
      _befreiungJahr = data['befreiung_jahr'] ?? DateTime.now().year.toString();
      _pflegegrad = data['pflegegrad'] ?? '';
      _pflegeboxVersandart = data['pflegebox_versandart'] ?? '';
      _pflegeboxStatus = data['pflegebox_status'] ?? '';
      final fid = data['pflegebox_firma_id'];
      _pflegeboxFirmaId = fid is int ? fid : (fid is String ? int.tryParse(fid) : null);
      _pflegeboxFirmaName = data['pflegebox_firma'] ?? '';
      _termine = _getTermineListe(data);
      _controllersInitialized = true;
    }
  }

  @override
  void dispose() {
    _dienststelleController.dispose();
    _krankenkasseNameController.dispose();
    _versichertennummerController.dispose();
    _kvnrController.dispose();
    _kartennummerController.dispose();
    _kartenfolgenummerController.dispose();
    _egkGueltigAbController.dispose();
    _egkGueltigBisController.dispose();
    _ehicKennummerController.dispose();
    _ehicInstitutionskennzeichenController.dispose();
    _pflegekasseNameController.dispose();
    _pflegegradSeitController.dispose();
    _befreiungGueltigBisController.dispose();
    _pflegeboxFirmaController.dispose();
    _pflegeboxDatumController.dispose();
    _pflegeboxNotizenController.dispose();
    super.dispose();
  }

  // Korrespondenz loaded from server DB (not from behoerde_data)
  List<Map<String, dynamic>> _kkKorrespondenz = [];
  bool _kkKorrLoaded = false;

  Future<void> _loadKKKorrespondenz() async {
    try {
      final result = await widget.apiService.getKKKorrespondenz(widget.user.id);
      if (result['success'] == true && result['data'] is List) {
        if (mounted) {
          setState(() {
            _kkKorrespondenz = (result['data'] as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
            _kkKorrLoaded = true;
          });
        }
      }
    } catch (e) {
      debugPrint('[KK Korrespondenz] load error: $e');
    }
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

  List<Map<String, dynamic>> _getTermineListe(Map<String, dynamic> data) {
    final raw = data['termine'];
    if (raw is List) return List<Map<String, dynamic>>.from(raw.whereType<Map>());
    return [];
  }

  static const double _gkvAllgemeinerBeitrag = 14.6;

  static const Map<int, Map<String, double>> _krankenkassenZusatzbeitrag = {
    // 2025
    2025: {
      'TK - Techniker Krankenkasse': 2.45,
      'BARMER': 2.99,
      'DAK-Gesundheit': 2.80,
      'AOK Baden-Wuerttemberg': 2.70,
      'AOK Bayern': 2.69,
      'AOK Bremen/Bremerhaven': 2.99,
      'AOK Hessen': 2.69,
      'AOK Niedersachsen': 2.79,
      'AOK Nordost': 3.50,
      'AOK NordWest': 2.69,
      'AOK PLUS (Sachsen/Thueringen)': 3.10,
      'AOK Rheinland-Pfalz/Saarland': 2.10,
      'AOK Rheinland/Hamburg': 3.29,
      'AOK Sachsen-Anhalt': 2.49,
      'IKK classic': 2.88,
      'IKK gesund plus': 2.98,
      'IKK Suedwest': 2.45,
      'IKK - Die Innovationskasse': 3.69,
      'KKH Kaufmaennische Krankenkasse': 3.28,
      'hkk Krankenkasse': 1.98,
      'SBK Siemens-Betriebskrankenkasse': 3.29,
      'Knappschaft': 3.90,
      'BKK firmus': 2.18,
      'BIG direkt gesund': 3.47,
      'Audi BKK': 2.40,
      'BMW BKK': 3.40,
      'Bosch BKK': 2.88,
      'Mobil Krankenkasse': 3.49,
      'mhplus BKK': 3.39,
      'Pronova BKK': 3.49,
      'VIACTIV Krankenkasse': 3.99,
      'mkk - Meine Krankenkasse': 3.10,
      'Heimat Krankenkasse': 3.40,
      'BKK Linde': 2.90,
      'BKK VBU': 3.30,
      'BKK24': 4.19,
      'Debeka BKK': 2.80,
      'energie-BKK': 3.69,
      'Novitas BKK': 3.50,
      'Salus BKK': 2.79,
      'vivida bkk': 2.40,
      'WMF BKK': 2.40,
      'BKK Pfalz': 2.49,
      'BKK Scheufelen': 1.98,
      'R+V BKK': 2.89,
      'SKD BKK': 2.69,
      'BKK Technoform': 2.21,
      'BKK ZF & Partner': 2.28,
      'Continentale BKK': 3.50,
      'BKK Akzo Nobel': 2.60,
      'BKK Freudenberg': 2.40,
      'BKK Melitta HMR': 2.49,
      'BKK ProVita': 3.50,
      'BKK Werra-Meissner': 2.49,
      'BKK Wirtschaft & Finanzen': 3.20,
      'Bertelsmann BKK': 2.95,
    },
    // 2026
    2026: {
      'TK - Techniker Krankenkasse': 2.69,
      'BARMER': 3.29,
      'DAK-Gesundheit': 3.20,
      'AOK Baden-Wuerttemberg': 2.99,
      'AOK Bayern': 2.69,
      'AOK Bremen/Bremerhaven': 3.29,
      'AOK Hessen': 2.98,
      'AOK Niedersachsen': 2.98,
      'AOK Nordost': 3.50,
      'AOK NordWest': 2.99,
      'AOK PLUS (Sachsen/Thueringen)': 3.10,
      'AOK Rheinland-Pfalz/Saarland': 2.47,
      'AOK Rheinland/Hamburg': 3.29,
      'AOK Sachsen-Anhalt': 2.89,
      'IKK classic': 3.40,
      'IKK gesund plus': 3.39,
      'IKK Suedwest': 2.75,
      'IKK - Die Innovationskasse': 4.30,
      'KKH Kaufmaennische Krankenkasse': 3.78,
      'hkk Krankenkasse': 2.59,
      'SBK Siemens-Betriebskrankenkasse': 3.80,
      'Knappschaft': 4.30,
      'BKK firmus': 2.18,
      'BIG direkt gesund': 3.69,
      'Audi BKK': 2.60,
      'BMW BKK': 3.90,
      'Bosch BKK': 3.18,
      'Mobil Krankenkasse': 3.89,
      'mhplus BKK': 3.86,
      'Pronova BKK': 3.70,
      'VIACTIV Krankenkasse': 4.19,
      'mkk - Meine Krankenkasse': 3.50,
      'Heimat Krankenkasse': 3.90,
      'BKK Linde': 3.10,
      'BKK VBU': 3.50,
      'BKK24': 4.39,
      'Debeka BKK': 2.99,
      'energie-BKK': 3.99,
      'Novitas BKK': 3.69,
      'Salus BKK': 2.99,
      'vivida bkk': 2.80,
      'WMF BKK': 2.60,
      'BKK Pfalz': 2.79,
      'BKK Scheufelen': 2.10,
      'R+V BKK': 3.19,
      'SKD BKK': 2.69,
      'BKK Technoform': 2.40,
      'BKK ZF & Partner': 2.48,
      'Continentale BKK': 3.80,
      'BKK Akzo Nobel': 2.80,
      'BKK Freudenberg': 2.80,
      'BKK Melitta HMR': 2.69,
      'BKK ProVita': 3.80,
      'BKK Werra-Meissner': 2.69,
      'BKK Wirtschaft & Finanzen': 3.50,
      'Bertelsmann BKK': 3.25,
    },
  };

  /// Get sorted list of Krankenkassen for current year (DB first, then static fallback)
  List<String> _getKrankenkassenListe(int year) {
    final dbKassen = _dbKrankenkassenZusatzbeitrag[year];
    if (dbKassen != null && dbKassen.isNotEmpty) {
      return dbKassen.keys.toList()..sort();
    }
    // Fallback: static data
    final kassen = _krankenkassenZusatzbeitrag[year] ?? _krankenkassenZusatzbeitrag.values.last;
    return kassen.keys.toList()..sort();
  }

  /// Get Zusatzbeitrag for a specific Krankenkasse and year (DB first, then static fallback)
  double? _getZusatzbeitrag(String kasse, int year) {
    final dbKassen = _dbKrankenkassenZusatzbeitrag[year];
    if (dbKassen != null && dbKassen.containsKey(kasse)) {
      return dbKassen[kasse];
    }
    // Fallback: static data
    final kassen = _krankenkassenZusatzbeitrag[year] ?? _krankenkassenZusatzbeitrag.values.last;
    return kassen[kasse];
  }

  /// Get Gesamtbeitrag (allgemeiner + Zusatzbeitrag)
  double _getGesamtbeitrag(String kasse, int year) {
    final zusatz = _getZusatzbeitrag(kasse, year) ?? 0;
    return _gkvAllgemeinerBeitrag + zusatz;
  }

  /// Get Krankenkassen rating (DB first, then static fallback)
  double _getKrankenkassenRatingValue(String kasse) {
    if (_dbKrankenkassenRating.containsKey(kasse)) {
      return _dbKrankenkassenRating[kasse]!;
    }
    return _krankenkassenRating[kasse] ?? 3.0;
  }

  static const Map<String, double> _krankenkassenRating = {
    // Exzellent (200+ Punkte) → 5.0★
    'AOK Rheinland-Pfalz/Saarland': 5.0, // 216.6 Pkt - Platz 1
    'TK - Techniker Krankenkasse': 5.0,   // 206.7 Pkt - Platz 2
    // Sehr Gut (185-200 Punkte) → 4.5★
    'AOK PLUS (Sachsen/Thueringen)': 4.5, // 194.2 Pkt - Platz 7
    'DAK-Gesundheit': 4.5,                // 191.5 Pkt - Platz 8
    'AOK Bayern': 4.5,                    // 188.6 Pkt - Platz 9
    'AOK Hessen': 4.5,                    // 185.7 Pkt - Platz 10
    // Gut (165-185 Punkte) → 4.0★
    'hkk Krankenkasse': 4.0,              // 181.2 Pkt - Platz 11
    'IKK classic': 4.0,                   // 177.4 Pkt - Platz 13
    'AOK Baden-Wuerttemberg': 4.0,        // 174.3 Pkt - Platz 14
    'BARMER': 4.0,                        // 172.6 Pkt - Platz 15
    'AOK Rheinland/Hamburg': 4.0,         // 172.2 Pkt - Platz 16
    'Audi BKK': 4.0,                      // 169.5 Pkt - Platz 17
    'R+V BKK': 4.0,                       // 168.3 Pkt - Platz 18
    'KKH Kaufmaennische Krankenkasse': 4.0, // 166.4 Pkt - Platz 19
    'VIACTIV Krankenkasse': 4.0,          // 164.5 Pkt - Platz 20
    // Gut (145-165 Punkte) → 3.5★
    'AOK Bremen/Bremerhaven': 3.5,        // 163.4 Pkt - Platz 21
    'mhplus BKK': 3.5,                    // 163.2 Pkt - Platz 22
    'energie-BKK': 3.5,                   // 159.8 Pkt - Platz 24
    'SBK Siemens-Betriebskrankenkasse': 3.5, // 159.5 Pkt - Platz 25
    'Pronova BKK': 3.5,                   // 157.0 Pkt - Platz 26
    'mkk - Meine Krankenkasse': 3.5,      // 151.9 Pkt - Platz 27
    'AOK NordWest': 3.5,                  // 146.5 Pkt - Platz 29
    'BIG direkt gesund': 3.5,             // 146.5 Pkt - Platz 29
    'vivida bkk': 3.5,                    // 146.2 Pkt - Platz 31
    'Salus BKK': 3.5,                     // 145.7 Pkt - Platz 32
    'IKK Suedwest': 4.5,                  // 195.9 Pkt - Platz 6
    'Mobil Krankenkasse': 5.0,            // 200.8 Pkt - Platz 4
    // Befriedigend (125-145 Punkte) → 3.0★
    'Novitas BKK': 3.0,                   // 144.8 Pkt - Platz 33
    'IKK gesund plus': 3.0,              // 137.9 Pkt - Platz 34
    'BKK VBU': 3.0,                       // 134.7 Pkt - Platz 36 (BKK VDN)
    'BKK Wirtschaft & Finanzen': 3.0,     // 132.7 Pkt - Platz 37
    'BKK ZF & Partner': 3.0,             // 132.5 Pkt - Platz 38
    'AOK Niedersachsen': 3.0,            // 130.3 Pkt - Platz 41
    'AOK Sachsen-Anhalt': 3.0,           // 128.8 Pkt - Platz 43
    'BKK firmus': 3.0,                    // 124.6 Pkt - Platz 44
    'Heimat Krankenkasse': 3.0,           // 124.4 Pkt - Platz 45
    'Debeka BKK': 3.0,                    // ~130 Pkt
    // Befriedigend (115-125 Punkte) → 2.5★
    'BKK24': 2.5,                         // 121.2 Pkt - Platz 46
    'Knappschaft': 2.5,                   // 120.4 Pkt - Platz 47
    'BKK ProVita': 2.5,                   // 118.8 Pkt - Platz 49
    'BKK Freudenberg': 2.5,              // 117.5 Pkt - Platz 51
    'WMF BKK': 2.5,                       // 116.8 Pkt - Platz 53
    'AOK Nordost': 2.5,                   // 116.4 Pkt - Platz 54
    'BMW BKK': 2.5,                       // ~118 Pkt
    'Bosch BKK': 3.0,                     // ~130 Pkt
    'Bertelsmann BKK': 3.0,              // ~128 Pkt
    // Ausreichend (95-115 Punkte) → 2.0★
    'BKK Akzo Nobel': 2.0,               // 111.0 Pkt - Platz 56
    'BKK Linde': 2.0,                     // 108.9 Pkt - Platz 57
    'BKK Technoform': 2.0,               // 102.9 Pkt - Platz 59
    'Continentale BKK': 2.0,             // 101.2 Pkt - Platz 60
    'SKD BKK': 2.0,                       // 98.6 Pkt - Platz 61
    'BKK Scheufelen': 2.0,               // 97.3 Pkt - Platz 62
    'BKK Pfalz': 2.0,                     // 96.3 Pkt - Platz 63
    // Ausreichend (<95 Punkte) → 1.5★
    'BKK Melitta HMR': 1.5,              // 93.5 Pkt - Platz 65
    'BKK Werra-Meissner': 1.5,           // 93.2 Pkt - Platz 66
    'IKK - Die Innovationskasse': 1.5,   // 91.2 Pkt - Platz 67
  };

  static Widget _starRating(double rating, {double size = 14}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        if (i < rating.floor()) {
          return Icon(Icons.star, size: size, color: Colors.amber.shade600);
        } else if (i < rating) {
          return Icon(Icons.star_half, size: size, color: Colors.amber.shade600);
        } else {
          return Icon(Icons.star_border, size: size, color: Colors.grey.shade400);
        }
      }),
    );
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

    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.blue.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade700,
            isScrollable: true,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.local_hospital, size: 16), const SizedBox(width: 4), const Text('Krankenkasse')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _getTermineListe(data).isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.calendar_month, size: 16), const SizedBox(width: 4), const Text('Termine')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _kkKorrespondenz.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.mail, size: 16), const SizedBox(width: 4), const Text('Korrespondenz')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['pflegegrad']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.elderly, size: 16), const SizedBox(width: 4), const Text('Pflegegrad')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['versicherungsart']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.shield, size: 16), const SizedBox(width: 4), const Text('Versicherung')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['befreiungskarte'] == true || data['befreiungskarte'] == 'true' || data['befreiungskarte'] == '1') ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.card_membership, size: 16), const SizedBox(width: 4), const Text('Befreiungskarte')])),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildKrankenkasseTab(data),
                _buildTermineTab(data),
                _buildKorrespondenzTab(data),
                _buildPflegegradTab(data),
                _buildVersicherungTab(data),
                _buildBefreiungskarteTab(data),
              ],
            ),
          ),
          _buildSaveFooter(),
        ],
      ),
    );
  }

  // ============ TAB 1: KRANKENKASSE ============
  Widget _buildKrankenkasseTab(Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.local_hospital, 'Krankenkasse', Colors.blue),
          const SizedBox(height: 8),
          widget.dienststelleBuilder(type, _dienststelleController),
          Text('Krankenkasse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Builder(builder: (context) {
            final currentYear = DateTime.now().year;
            final kassenListe = _getKrankenkassenListe(currentYear);
            return Autocomplete<String>(
              initialValue: _krankenkasseNameController.value,
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return kassenListe;
                final query = textEditingValue.text.toLowerCase();
                return kassenListe.where((k) => k.toLowerCase().contains(query));
              },
              fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                if (controller.text.isEmpty && _krankenkasseNameController.text.isNotEmpty) {
                  controller.text = _krankenkasseNameController.text;
                }
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: InputDecoration(
                    hintText: 'Krankenkasse suchen (z.B. AOK, TK, Barmer...)',
                    prefixIcon: const Icon(Icons.local_hospital, size: 20),
                    suffixIcon: const Icon(Icons.arrow_drop_down, size: 24),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 14),
                  onChanged: (v) => _krankenkasseNameController.text = v,
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(8),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 250, maxWidth: 500),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, index) {
                          final kasse = options.elementAt(index);
                          final zusatz = _getZusatzbeitrag(kasse, currentYear);
                          final gesamt = _getGesamtbeitrag(kasse, currentYear);
                          final rating = _getKrankenkassenRatingValue(kasse);
                          return ListTile(
                            dense: true,
                            title: Text(kasse, style: const TextStyle(fontSize: 13)),
                            subtitle: _starRating(rating, size: 12),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${gesamt.toStringAsFixed(2)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                Text('+${zusatz?.toStringAsFixed(2)}% Zusatz', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                              ],
                            ),
                            onTap: () {
                              onSelected(kasse);
                              _krankenkasseNameController.text = kasse;
                              setState(() {});
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
              onSelected: (kasse) {
                _krankenkasseNameController.text = kasse;
                setState(() {});
              },
            );
          }),
          Builder(builder: (context) {
            final currentYear = DateTime.now().year;
            final kasseName = _krankenkasseNameController.text.trim();
            final zusatz = _getZusatzbeitrag(kasseName, currentYear);
            if (zusatz == null) return const SizedBox(height: 16);
            final gesamt = _getGesamtbeitrag(kasseName, currentYear);
            final arbeitnehmerAnteil = gesamt / 2;
            return Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.green.shade50, Colors.green.shade100],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.green.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(Icons.euro, color: Colors.green.shade700, size: 18),
                      const SizedBox(width: 6),
                      Text('Beitragssaetze $currentYear', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                      const Spacer(),
                      _starRating(_getKrankenkassenRatingValue(kasseName), size: 16),
                    ]),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Allgemeiner Beitrag', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('$_gkvAllgemeinerBeitrag%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey.shade800)),
                      ])),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Zusatzbeitrag', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('${zusatz.toStringAsFixed(2)}%', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.orange.shade800)),
                      ])),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                        Text('Gesamtbeitrag', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        Text('${gesamt.toStringAsFixed(2)}%', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                      ])),
                    ]),
                    const Divider(height: 16),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Arbeitnehmeranteil (halber Beitrag):', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
                      Text('${arbeitnehmerAnteil.toStringAsFixed(2)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      'Arbeitgeber und Arbeitnehmer teilen sich den Beitrag je zur Haelfte.',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic),
                    ),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          Text('Versichertennummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: _versichertennummerController,
            decoration: InputDecoration(
              hintText: 'Versichertennummer (auf der Gesundheitskarte)',
              prefixIcon: const Icon(Icons.credit_card, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
        ],
      ),
    );
  }

  // ============ TAB 2: TERMINE ============
  Widget _buildTermineTab(Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: StatefulBuilder(builder: (context, setLocalState) {
        return widget.termineBuilder(
          behoerdeType: type,
          behoerdeLabel: 'Krankenkasse',
          termine: _termine,
          data: data,
          onChanged: (updated) {
            setState(() => _termine = updated);
            widget.autoSaveField(type, 'termine', updated);
          },
          setLocalState: setLocalState,
        );
      }),
    );
  }

  // ============ TAB 3: KORRESPONDENZ ============
  Widget _buildKorrespondenzTab(Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: StatefulBuilder(builder: (context, setLocalState) {
        return _buildKorrespondenzSection(type, data, setLocalState);
      }),
    );
  }

  // ============ TAB 4: PFLEGEGRAD ============
  Widget _buildPflegegradTab(Map<String, dynamic> data) {
    final pflegegrade = {
      '': 'Kein Pflegegrad',
      '1': 'Pflegegrad 1 – Geringe Beeinträchtigung',
      '2': 'Pflegegrad 2 – Erhebliche Beeinträchtigung',
      '3': 'Pflegegrad 3 – Schwere Beeinträchtigung',
      '4': 'Pflegegrad 4 – Schwerste Beeinträchtigung',
      '5': 'Pflegegrad 5 – Schwerste Beeinträchtigung mit besonderen Anforderungen',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.elderly, 'Pflegekasse', Colors.purple),
          const SizedBox(height: 8),
          Text('Pflegekasse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: _pflegekasseNameController,
            decoration: InputDecoration(
              hintText: 'Meist identisch mit der Krankenkasse',
              prefixIcon: const Icon(Icons.elderly, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Von Krankenkasse übernehmen',
                onPressed: () {
                  setState(() {
                    _pflegekasseNameController.text = _krankenkasseNameController.text;
                  });
                },
              ),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 16),
          Text('Pflegegrad', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: pflegegrade.containsKey(_pflegegrad) ? _pflegegrad : '',
                isExpanded: true,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: pflegegrade.entries.map((e) {
                  return DropdownMenuItem<String>(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 12)));
                }).toList(),
                onChanged: (v) => setState(() => _pflegegrad = v ?? ''),
              ),
            ),
          ),
          if (_pflegegrad.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('Pflegegrad seit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 4),
            TextField(
              controller: _pflegegradSeitController,
              readOnly: true,
              decoration: InputDecoration(
                hintText: 'Datum wählen...',
                prefixIcon: const Icon(Icons.calendar_today, size: 18),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
              style: const TextStyle(fontSize: 13),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                  locale: const Locale('de', 'DE'),
                );
                if (picked != null) {
                  setState(() {
                    _pflegegradSeitController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                  });
                }
              },
            ),
          ],
          if (_pflegegrad.isNotEmpty && int.tryParse(_pflegegrad) != null && int.parse(_pflegegrad) >= 1) ...[
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.medical_services, size: 20, color: Colors.green.shade700),
                    const SizedBox(width: 8),
                    Text('Pflegebox', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.green.shade700)),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                      child: Text('Ab Pflegegrad 1', style: TextStyle(fontSize: 10, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                    ),
                  ]),
                  const SizedBox(height: 4),
                  Text('Anspruch auf kostenlose Pflegehilfsmittel (bis 40€/Monat)', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                  const Divider(height: 20),
                  PflegeboxSection(
                    apiService: widget.apiService,
                    userId: widget.user.id,
                    selectedFirmaId: _pflegeboxFirmaId,
                    selectedFirmaName: _pflegeboxFirmaName,
                    onFirmaChanged: (firma) {
                      setState(() {
                        _pflegeboxFirmaId = firma == null ? null : firma['id'] as int?;
                        _pflegeboxFirmaName = firma == null ? '' : (firma['firma_name']?.toString() ?? '');
                        _pflegeboxFirmaController.text = _pflegeboxFirmaName;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Antrag gestellt am', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _pflegeboxDatumController,
                    readOnly: true,
                    decoration: InputDecoration(
                      hintText: 'Datum wählen...',
                      prefixIcon: const Icon(Icons.calendar_today, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                        locale: const Locale('de', 'DE'),
                      );
                      if (picked != null) {
                        setState(() {
                          _pflegeboxDatumController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  Text('Antrag gestellt per', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final v in [('online', 'Online', Icons.language), ('telefonisch', 'Telefonisch', Icons.phone), ('persoenlich', 'Persönlich', Icons.person), ('postalisch', 'Postalisch', Icons.local_post_office)])
                      ChoiceChip(
                        label: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(v.$3, size: 14, color: _pflegeboxVersandart == v.$1 ? Colors.white : Colors.grey.shade700),
                          const SizedBox(width: 4),
                          Text(v.$2, style: TextStyle(fontSize: 11, color: _pflegeboxVersandart == v.$1 ? Colors.white : Colors.black87)),
                        ]),
                        selected: _pflegeboxVersandart == v.$1,
                        selectedColor: Colors.green.shade600,
                        onSelected: (_) => setState(() => _pflegeboxVersandart = v.$1),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final s in [('beantragt', 'Beantragt', Colors.orange), ('genehmigt', 'Genehmigt', Colors.green), ('abgelehnt', 'Abgelehnt', Colors.red), ('wird_geliefert', 'Wird geliefert', Colors.blue), ('aktiv', 'Aktiv (monatlich)', Colors.teal)])
                      ChoiceChip(
                        label: Text(s.$2, style: TextStyle(fontSize: 11, color: _pflegeboxStatus == s.$1 ? Colors.white : Colors.black87)),
                        selected: _pflegeboxStatus == s.$1,
                        selectedColor: s.$3,
                        onSelected: (_) => setState(() => _pflegeboxStatus = s.$1),
                      ),
                  ]),
                  const SizedBox(height: 12),
                  Text('Notizen', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  TextField(
                    controller: _pflegeboxNotizenController,
                    maxLines: 2,
                    decoration: InputDecoration(
                      hintText: 'Weitere Informationen...',
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ============ TAB 5: VERSICHERUNG ============
  Widget _buildVersicherungTab(Map<String, dynamic> data) {
    final versicherungsarten = {
      '': 'Nicht ausgewählt',
      'gesetzlich': 'Gesetzlich versichert (GKV)',
      'privat': 'Privat versichert (PKV)',
      'familienversichert': 'Familienversichert',
    };
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.shield, 'Versicherungsart & Status', Colors.blue),
          const SizedBox(height: 8),
          Text('Versicherungsart', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: versicherungsarten.containsKey(_versicherungsart) ? _versicherungsart : '',
                isExpanded: true,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: versicherungsarten.entries.map((e) {
                  return DropdownMenuItem<String>(value: e.key, child: Text(e.value, style: const TextStyle(fontSize: 13)));
                }).toList(),
                onChanged: (v) => setState(() => _versicherungsart = v ?? ''),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Versichertenstatus', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade400),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: const {
                  '', '1000000', '1010000', '1060000',
                  '3000000', '3010000',
                  '5000000', '5010000',
                  '9000000',
                }.contains(_versichertenstatus) ? _versichertenstatus : '',
                isExpanded: true,
                style: const TextStyle(fontSize: 14, color: Colors.black87),
                items: const [
                  DropdownMenuItem(value: '', child: Text('Nicht ausgewählt', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '1000000', child: Text('1000000 — Mitglied (GKV pflichtversichert)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '1010000', child: Text('1010000 — Mitglied (BVG-Kennzeichen)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '1060000', child: Text('1060000 — Mitglied (BSHG / Sozialhilfe)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '3000000', child: Text('3000000 — Familienversicherter', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '3010000', child: Text('3010000 — Familienversicherter (BVG)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '5000000', child: Text('5000000 — Rentner (KVdR)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '5010000', child: Text('5010000 — Rentner (BVG-Kennzeichen)', style: TextStyle(fontSize: 13))),
                  DropdownMenuItem(value: '9000000', child: Text('9000000 — Sonstiger Kostenträger', style: TextStyle(fontSize: 13))),
                ],
                onChanged: (v) => setState(() => _versichertenstatus = v ?? ''),
              ),
            ),
          ),
          if (_versichertenstatus.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(children: [
                Icon(Icons.verified_user, size: 14, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Text('Versicherungsstatus-Code: ', style: TextStyle(fontSize: 11, color: Colors.blue.shade800)),
                Text(_versichertenstatus, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.blue.shade900)),
              ]),
            ),
          ],
          const SizedBox(height: 24),
          _sectionHeader(Icons.credit_card, 'Elektronische Gesundheitskarte (eGK)', Colors.teal),
          const SizedBox(height: 8),
          Text('Krankenversichertennummer (KVNR)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: _kvnrController,
            decoration: InputDecoration(
              hintText: 'z.B. A123456789 (1 Buchstabe + 9 Ziffern)',
              prefixIcon: const Icon(Icons.badge, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          const SizedBox(height: 4),
          Text('Lebenslang gueltig — bleibt auch bei Kassenwechsel gleich.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kartennummer', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: _kartennummerController,
                decoration: InputDecoration(
                  hintText: 'Auf der Vorderseite',
                  prefixIcon: const Icon(Icons.numbers, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Kartenfolge-Nr.', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: _kartenfolgenummerController,
                decoration: InputDecoration(
                  hintText: 'z.B. 01',
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 14),
                keyboardType: TextInputType.number,
              ),
            ])),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gültig ab', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: _egkGueltigAbController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Datum...',
                  prefixIcon: const Icon(Icons.calendar_today, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2040),
                    locale: const Locale('de', 'DE'),
                  );
                  if (picked != null) {
                    setState(() {
                      _egkGueltigAbController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                    });
                  }
                },
              ),
            ])),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Gültig bis', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
              const SizedBox(height: 4),
              TextField(
                controller: _egkGueltigBisController,
                readOnly: true,
                decoration: InputDecoration(
                  hintText: 'Datum...',
                  prefixIcon: const Icon(Icons.event_busy, size: 18),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                style: const TextStyle(fontSize: 13),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: DateTime.now().add(const Duration(days: 365 * 5)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2040),
                    locale: const Locale('de', 'DE'),
                  );
                  if (picked != null) {
                    setState(() {
                      _egkGueltigBisController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                    });
                  }
                },
              ),
            ])),
          ]),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.indigo.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.indigo.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.language, size: 18, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Text('EHIC — Europäische Krankenversicherungskarte', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                ]),
                const SizedBox(height: 4),
                Text('Rückseite der eGK — gültig in allen EU-/EWR-Ländern + Schweiz', style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontStyle: FontStyle.italic)),
                const SizedBox(height: 10),
                Text('Persönliche Kennnummer', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                TextField(
                  controller: _ehicKennummerController,
                  decoration: InputDecoration(
                    hintText: 'Kennnummer auf der EHIC-Rückseite',
                    prefixIcon: const Icon(Icons.person_pin, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 10),
                Text('Kennnummer der Institution (IK)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                TextField(
                  controller: _ehicInstitutionskennzeichenController,
                  decoration: InputDecoration(
                    hintText: 'Institutionskennzeichen der Krankenkasse',
                    prefixIcon: const Icon(Icons.business, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============ TAB 6: BEFREIUNGSKARTE ============
  Widget _buildBefreiungskarteTab(Map<String, dynamic> data) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(Icons.card_membership, 'Befreiungsausweis (Zuzahlungsbefreiung)', Colors.green),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade100)),
            child: Row(children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Befreiung von Zuzahlungen bei Arznei-, Heil- und Hilfsmitteln, '
                  'Krankenhausaufenthalten und Fahrkosten. Gültig ein Kalenderjahr. '
                  'Neuantrag jährlich ab November.',
                  style: TextStyle(fontSize: 11, color: Colors.blue.shade900),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          _buildBefreiungsausweis(),
        ],
      ),
    );
  }

  // ============ Befreiungsausweis sub-widget ============
  Widget _buildBefreiungsausweis() {
    final now = DateTime.now();
    final befreiungJahrInt = int.tryParse(_befreiungJahr) ?? now.year;
    final nov1 = DateTime(befreiungJahrInt, 11, 1);
    final firstMondayNov = nov1.weekday == DateTime.monday
        ? nov1
        : nov1.add(Duration(days: (DateTime.monday - nov1.weekday + 7) % 7));
    final isExpiringSoon = _befreiungskarte && befreiungJahrInt == now.year && now.isAfter(firstMondayNov.subtract(const Duration(days: 1)));
    final isExpired = _befreiungskarte && befreiungJahrInt < now.year;

    final borderColor = isExpired
        ? Colors.red.shade400
        : isExpiringSoon
            ? Colors.orange.shade400
            : _befreiungskarte
                ? Colors.green.shade300
                : Colors.grey.shade300;
    final bgColor = isExpired
        ? Colors.red.shade50
        : isExpiringSoon
            ? Colors.orange.shade50
            : _befreiungskarte
                ? Colors.green.shade50
                : Colors.grey.shade50;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor, width: isExpiringSoon || isExpired ? 2 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.card_membership, size: 20, color: _befreiungskarte ? Colors.green.shade700 : Colors.grey.shade600),
            const SizedBox(width: 8),
            Text('Befreiungsausweis', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _befreiungskarte ? Colors.green.shade700 : Colors.grey.shade700)),
            if (_befreiungskarte) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: isExpired ? Colors.red : isExpiringSoon ? Colors.orange : Colors.green,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _befreiungJahr,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
            const Spacer(),
            Switch(
              value: _befreiungskarte,
              activeTrackColor: Colors.green.shade200,
              onChanged: (v) => setState(() => _befreiungskarte = v),
            ),
          ]),
          if (_befreiungskarte) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Jahr', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade400),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _befreiungJahr,
                      isExpanded: true,
                      style: const TextStyle(fontSize: 13, color: Colors.black87),
                      items: List.generate(3, (i) {
                        final y = (now.year - 1 + i).toString();
                        return DropdownMenuItem<String>(value: y, child: Text(y));
                      }),
                      onChanged: (v) => setState(() => _befreiungJahr = v ?? now.year.toString()),
                    ),
                  ),
                ),
              ])),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Gültig bis', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                const SizedBox(height: 4),
                TextField(
                  controller: _befreiungGueltigBisController,
                  readOnly: true,
                  decoration: InputDecoration(
                    hintText: 'Datum wählen...',
                    prefixIcon: const Icon(Icons.calendar_today, size: 18),
                    isDense: true,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  style: const TextStyle(fontSize: 13),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: DateTime(befreiungJahrInt, 12, 31),
                      firstDate: DateTime(now.year - 1),
                      lastDate: DateTime(now.year + 2, 12, 31),
                      locale: const Locale('de', 'DE'),
                    );
                    if (picked != null) {
                      setState(() {
                        _befreiungGueltigBisController.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                      });
                    }
                  },
                ),
              ])),
            ]),
            const SizedBox(height: 8),
            Text(
              'Befreiung von Zuzahlungen bei Arznei-, Heil- und Hilfsmitteln, Krankenhausaufenthalten und Fahrkosten.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
            ),
            if (isExpiringSoon || isExpired) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: isExpired ? Colors.red.shade100 : Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: isExpired ? Colors.red.shade300 : Colors.orange.shade300),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Icon(isExpired ? Icons.error : Icons.warning_amber, size: 18, color: isExpired ? Colors.red.shade700 : Colors.orange.shade800),
                      const SizedBox(width: 6),
                      Expanded(child: Text(
                        isExpired
                            ? 'Befreiungsausweis $_befreiungJahr ist abgelaufen!'
                            : 'Befreiungsausweis $_befreiungJahr läuft bald ab! Neuen Antrag für ${now.year + 1} stellen.',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: isExpired ? Colors.red.shade800 : Colors.orange.shade900),
                      )),
                    ]),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: () async {
                          final nextYear = befreiungJahrInt < now.year ? now.year : now.year + 1;
                          final novFirst = DateTime(befreiungJahrInt, 11, 1);
                          final firstMonday = novFirst.weekday == DateTime.monday
                              ? novFirst
                              : novFirst.add(Duration(days: (DateTime.monday - novFirst.weekday + 7) % 7));
                          final scheduledStr = '${firstMonday.year}-${firstMonday.month.toString().padLeft(2, '0')}-${firstMonday.day.toString().padLeft(2, '0')}';

                          final result = await widget.ticketService.createTicketForMember(
                            adminMitgliedernummer: widget.adminMitgliedernummer,
                            memberMitgliedernummer: widget.user.mitgliedernummer,
                            subject: 'Befreiungsausweis $nextYear beantragen',
                            message: 'Der Befreiungsausweis für $_befreiungJahr läuft zum Jahresende ab.\n\n'
                                'Bitte neuen Antrag bei der Krankenkasse (${_krankenkasseNameController.text}) stellen für das Jahr $nextYear.\n\n'
                                'Versichertennummer: ${_versichertennummerController.text}\n'
                                'Krankenkasse: ${_krankenkasseNameController.text}',
                            priority: 'high',
                            scheduledDate: scheduledStr,
                          );

                          if (context.mounted) {
                            if (result.containsKey('ticket')) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Erinnerungsticket für Befreiungsausweis $nextYear erstellt (geplant: ${firstMonday.day.toString().padLeft(2, '0')}.${firstMonday.month.toString().padLeft(2, '0')}.${firstMonday.year})'),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(result['error'] ?? 'Fehler beim Erstellen des Tickets'),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                        icon: const Icon(Icons.assignment_add, size: 16),
                        label: Text(
                          isExpired
                              ? 'Erinnerungsticket für ${now.year} erstellen'
                              : 'Erinnerungsticket für ${now.year + 1} erstellen',
                          style: const TextStyle(fontSize: 12),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: isExpired ? Colors.red : Colors.orange.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  // ============ Save footer ============
  Widget _buildSaveFooter() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: ElevatedButton.icon(
          onPressed: widget.isSaving(type) == true ? null : () {
            widget.saveData(type, {
              'dienststelle': _dienststelleController.text.trim(),
              'name': _krankenkasseNameController.text.trim(),
              'versicherungsart': _versicherungsart,
              'versichertennummer': _versichertennummerController.text.trim(),
              'kvnr': _kvnrController.text.trim(),
              'versichertenstatus': _versichertenstatus,
              'kartennummer': _kartennummerController.text.trim(),
              'kartenfolgenummer': _kartenfolgenummerController.text.trim(),
              'egk_gueltig_ab': _egkGueltigAbController.text.trim(),
              'egk_gueltig_bis': _egkGueltigBisController.text.trim(),
              'ehic_kennnummer': _ehicKennummerController.text.trim(),
              'ehic_institutionskennzeichen': _ehicInstitutionskennzeichenController.text.trim(),
              'befreiungskarte': _befreiungskarte.toString(),
              'befreiung_jahr': _befreiungJahr,
              'befreiung_gueltig_bis': _befreiungGueltigBisController.text.trim(),
              'pflegekasse_name': _pflegekasseNameController.text.trim(),
              'pflegegrad': _pflegegrad,
              'pflegegrad_seit': _pflegegradSeitController.text.trim(),
              'pflegebox_firma': _pflegeboxFirmaName.isNotEmpty ? _pflegeboxFirmaName : _pflegeboxFirmaController.text.trim(),
              'pflegebox_firma_id': _pflegeboxFirmaId,
              'pflegebox_datum': _pflegeboxDatumController.text.trim(),
              'pflegebox_versandart': _pflegeboxVersandart,
              'pflegebox_status': _pflegeboxStatus,
              'pflegebox_notizen': _pflegeboxNotizenController.text.trim(),
              'termine': _termine,
            });
          },
          icon: widget.isSaving(type) == true
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.save, size: 18),
          label: const Text('Speichern'),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white),
        ),
      ),
    );
  }


  // ── KORRESPONDENZ SECTION ──
  Widget _buildKorrespondenzSection(String behoerdeType, Map<String, dynamic> data, StateSetter setLocalState) {
    if (!_kkKorrLoaded) _loadKKKorrespondenz();
    final korrespondenz = _kkKorrespondenz;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(Icons.mail, 'Korrespondenz', Colors.indigo),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: Text('${korrespondenz.length} Eintr\u00E4ge', style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        FilledButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Eingang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.green.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _showKorrespondenzDialog(behoerdeType, data, korrespondenz, 'eingang', setLocalState),
        ),
        const SizedBox(width: 6),
        FilledButton.icon(
          icon: const Icon(Icons.send, size: 16),
          label: const Text('Ausgang', style: TextStyle(fontSize: 11)),
          style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
          onPressed: () => _showKorrespondenzDialog(behoerdeType, data, korrespondenz, 'ausgang', setLocalState),
        ),
      ]),
      const SizedBox(height: 8),
      if (korrespondenz.isEmpty)
        Container(
          width: double.infinity, padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.grey.shade200)),
          child: Column(children: [
            Icon(Icons.mail_outline, size: 32, color: Colors.grey.shade400),
            const SizedBox(height: 6),
            Text('Keine Korrespondenz vorhanden', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
          ]),
        )
      else
        ...korrespondenz.asMap().entries.map((entry) {
          final i = entry.key;
          final k = entry.value;
          final isEingang = k['richtung'] == 'eingang';
          return InkWell(
            onTap: () => _showKorrespondenzDetailDialog(k, i, korrespondenz, data, behoerdeType, setLocalState),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(8),
                border: Border.all(color: isEingang ? Colors.green.shade200 : Colors.blue.shade200),
              ),
              child: Row(children: [
                Icon(isEingang ? Icons.call_received : Icons.call_made, size: 18,
                    color: isEingang ? Colors.green.shade600 : Colors.blue.shade600),
                const SizedBox(width: 8),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(k['betreff']?.toString() ?? 'Ohne Betreff', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold,
                      color: isEingang ? Colors.green.shade800 : Colors.blue.shade800)),
                  Row(children: [
                    Text(k['erstellt_am']?.toString() ?? k['datum']?.toString() ?? '', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                    if ((k['zugestellt_am']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Text('\u2192 ${k['zugestellt_am']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ],
                    if (k['dokumente'] is List && (k['dokumente'] as List).isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.attach_file, size: 12, color: Colors.grey.shade500),
                      Text('${(k['dokumente'] as List).length}', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                    ] else if ((k['dokument_name']?.toString() ?? '').isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.attach_file, size: 12, color: Colors.grey.shade500),
                    ],
                  ]),
                  if ((k['notiz']?.toString() ?? '').isNotEmpty)
                    Text(k['notiz'], style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                ])),
                IconButton(
                  icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade400),
                  onPressed: () {
                    korrespondenz.removeAt(i);
                    _kkKorrespondenz = korrespondenz;
                    setLocalState(() {});
                  },
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                ),
              ]),
            ),
          );
        }),
    ]);
  }

  void _showKorrespondenzDetailDialog(Map<String, dynamic> k, int index, List<Map<String, dynamic>> korrespondenz, Map<String, dynamic> data, String behoerdeType, StateSetter setLocalState) {
    final isEingang = k['richtung'] == 'eingang';
    final hasDokument = (k['dokument_name']?.toString() ?? '').isNotEmpty;
    List<Map<String, dynamic>> verlauf = [];
    if (k['verlauf'] is List) verlauf = List<Map<String, dynamic>>.from((k['verlauf'] as List).whereType<Map>());

    showDialog(
      context: context,
      builder: (ctx) => DefaultTabController(
        length: isEingang ? 2 : 3,
        child: StatefulBuilder(builder: (ctx2, setDetailState) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: SizedBox(
            width: 520, height: 500,
            child: Column(children: [
              // Header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isEingang ? Colors.green.shade50 : Colors.blue.shade50,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(children: [
                  Icon(isEingang ? Icons.call_received : Icons.call_made, size: 20,
                      color: isEingang ? Colors.green.shade700 : Colors.blue.shade700),
                  const SizedBox(width: 8),
                  Expanded(child: Text(k['betreff']?.toString() ?? 'Korrespondenz',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold,
                          color: isEingang ? Colors.green.shade800 : Colors.blue.shade800))),
                  IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(ctx)),
                ]),
              ),
              // Tabs
              TabBar(
                labelColor: isEingang ? Colors.green.shade700 : Colors.blue.shade700,
                indicatorColor: isEingang ? Colors.green.shade700 : Colors.blue.shade700,
                tabs: [
                  const Tab(text: 'Details'),
                  const Tab(text: 'Dokumente'),
                  if (!isEingang) const Tab(text: 'Verlauf'),
                ],
              ),
              // Content
              Expanded(
                child: TabBarView(children: [
                  // === Details tab ===
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _detailRow(Icons.swap_vert, 'Richtung', isEingang ? 'Eingang (empfangen)' : 'Ausgang (gesendet)'),
                      _detailRow(Icons.edit_calendar, 'Datum', k['erstellt_am']?.toString() ?? k['datum']?.toString() ?? ''),
                      if (isEingang) ...[
                        _detailRow(Icons.local_shipping, 'Zugestellt (Kunde)', k['zugestellt_am']?.toString() ?? ''),
                        _detailRow(Icons.inbox, 'Eingegangen (bei uns)', k['eingegangen_am']?.toString() ?? ''),
                      ],
                      _detailRow(Icons.subject, 'Betreff', k['betreff']?.toString() ?? ''),
                      if ((k['notiz']?.toString() ?? '').isNotEmpty)
                        _detailRow(Icons.note, 'Notiz', k['notiz'].toString()),
                      if (!isEingang && verlauf.isNotEmpty)
                        _detailRow(Icons.send, 'Zuletzt gesendet', '${verlauf.first['datum'] ?? ''} per ${verlauf.first['methode'] ?? ''}'),
                      const Spacer(),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        OutlinedButton.icon(
                          icon: Icon(Icons.delete_outline, size: 16, color: Colors.red.shade600),
                          label: Text('L\u00F6schen', style: TextStyle(color: Colors.red.shade600)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.red.shade300)),
                          onPressed: () {
                            korrespondenz.removeAt(index);
                            _kkKorrespondenz = korrespondenz;
                            setLocalState(() {});
                            Navigator.pop(ctx);
                          },
                        ),
                      ]),
                    ]),
                  ),
                  // === Dokumente tab ===
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.folder, size: 18, color: Colors.indigo.shade600),
                        const SizedBox(width: 6),
                        Text('Dokumente', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
                        const Spacer(),
                        OutlinedButton.icon(
                          icon: Icon(Icons.upload_file, size: 14, color: Colors.indigo.shade600),
                          label: Text('Hochladen', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
                          style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.indigo.shade300), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                          onPressed: () async {
                            final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
                            if (result != null && result.files.isNotEmpty) {
                              List<Map<String, dynamic>> docs = k['dokumente'] is List ? List<Map<String, dynamic>>.from((k['dokumente'] as List).whereType<Map>()) : [];
                              for (final file in result.files) {
                                if (file.path == null) continue;
                                try {
                                  final uploadResult = await widget.apiService.uploadKKKorrespondenz(
                                    userId: widget.user.id, richtung: k['richtung'] ?? 'ausgang',
                                    titel: k['betreff']?.toString() ?? '', datum: k['erstellt_am']?.toString() ?? k['datum']?.toString() ?? '',
                                    betreff: k['betreff']?.toString() ?? '', filePath: file.path, fileName: file.name,
                                  );
                                  if (uploadResult['success'] == true) {
                                    final newDocId = uploadResult['data']?['id']?.toString() ?? '';
                                    docs.add({'name': file.name, 'id': newDocId});
                                  }
                                } catch (e) {
                                  debugPrint('[KK Dok] Upload error: $e');
                                }
                              }
                              k['dokumente'] = docs;
                              if (docs.isNotEmpty && (k['dokument_name']?.toString() ?? '').isEmpty) {
                                k['dokument_name'] = docs.first['name'];
                                k['id'] = docs.first['id'];
                              }
                              _kkKorrespondenz = korrespondenz;
                              setDetailState(() {});
                              setLocalState(() {});
                            }
                          },
                        ),
                      ]),
                      const SizedBox(height: 10),
                      Expanded(child: Builder(builder: (_) {
                        List<Map<String, dynamic>> docs = k['dokumente'] is List ? List<Map<String, dynamic>>.from((k['dokumente'] as List).whereType<Map>()) : [];
                        if (docs.isEmpty && hasDokument) docs = [{'name': k['dokument_name'], 'id': k['id']?.toString() ?? ''}];
                        if (docs.isEmpty) {
                          return Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.folder_open, size: 40, color: Colors.grey.shade300),
                            const SizedBox(height: 6),
                            Text('Keine Dokumente', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                          ]));
                        }
                        return ListView.builder(
                          itemCount: docs.length,
                          itemBuilder: (_, di) {
                            final doc = docs[di];
                            final dId = int.tryParse(doc['id']?.toString() ?? '');
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(8)),
                              child: Row(children: [
                                Icon(Icons.description, size: 18, color: Colors.indigo.shade600),
                                const SizedBox(width: 8),
                                Expanded(child: Text(doc['name']?.toString() ?? '', style: TextStyle(fontSize: 12, color: Colors.indigo.shade700))),
                                // View
                                IconButton(
                                  icon: Icon(Icons.visibility, size: 18, color: Colors.indigo.shade600),
                                  tooltip: 'Anzeigen',
                                  onPressed: dId != null ? () async {
                                    try {
                                      final response = await widget.apiService.downloadKKKorrespondenzDoc(dId);
                                      if (response.statusCode == 200) {
                                        final dir = await getTemporaryDirectory();
                                        final file = File('${dir.path}/${doc['name']}');
                                        await file.writeAsBytes(response.bodyBytes);
                                        if (ctx2.mounted) await FileViewerDialog.show(ctx2, file.path, doc['name']?.toString() ?? '');
                                      }
                                    } catch (e) {
                                      if (ctx2.mounted) ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                                    }
                                  } : null,
                                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                ),
                                // Download
                                IconButton(
                                  icon: Icon(Icons.download, size: 18, color: Colors.blue.shade600),
                                  tooltip: 'Herunterladen',
                                  onPressed: dId != null ? () async {
                                    try {
                                      final response = await widget.apiService.downloadKKKorrespondenzDoc(dId);
                                      if (response.statusCode == 200) {
                                        final savePath = await FilePickerHelper.saveFile(dialogTitle: 'Speichern', fileName: doc['name']?.toString() ?? '');
                                        if (savePath != null) {
                                          await File(savePath).writeAsBytes(response.bodyBytes);
                                          if (ctx2.mounted) ScaffoldMessenger.of(ctx2).showSnackBar(const SnackBar(content: Text('Gespeichert'), backgroundColor: Colors.green));
                                        }
                                      }
                                    } catch (e) {
                                      if (ctx2.mounted) ScaffoldMessenger.of(ctx2).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
                                    }
                                  } : null,
                                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                                ),
                              ]),
                            );
                          },
                        );
                      })),
                    ]),
                  ),
                  // === Verlauf tab (nur Ausgang) ===
                  if (!isEingang)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Row(children: [
                          Icon(Icons.timeline, size: 18, color: Colors.orange.shade700),
                          const SizedBox(width: 6),
                          Text('Versandverlauf', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                          const Spacer(),
                          FilledButton.icon(
                            icon: const Icon(Icons.add, size: 14),
                            label: const Text('Eintrag', style: TextStyle(fontSize: 11)),
                            style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), minimumSize: Size.zero),
                            onPressed: () {
                              final vDatumC = TextEditingController();
                              String vMethode = 'post';
                              bool vGedruckt = false;
                              bool vUnterschrieben = false;
                              String vUnterschriftArt = 'persoenlich'; // persoenlich, digital
                              final vNotizC = TextEditingController();
                              final methoden = {'post': 'Post', 'persoenlich': 'Pers\u00F6nlich', 'online': 'Online', 'fax': 'Fax', 'email': 'E-Mail'};
                              final unterschriftArten = {'persoenlich': 'Pers\u00F6nlich', 'digital': 'Digital'};
                              showDialog(context: ctx2, builder: (vCtx) => StatefulBuilder(builder: (vCtx2, setV) => AlertDialog(
                                title: const Text('Versand eintragen', style: TextStyle(fontSize: 15)),
                                content: SizedBox(width: 380, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                  // 1. Unterschrift
                                  CheckboxListTile(
                                    value: vUnterschrieben,
                                    onChanged: (v) => setV(() => vUnterschrieben = v ?? false),
                                    title: const Text('Kunde hat unterschrieben', style: TextStyle(fontSize: 12)),
                                    secondary: Icon(Icons.draw, size: 18, color: vUnterschrieben ? Colors.green.shade600 : Colors.grey.shade400),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                  ),
                                  if (vUnterschrieben) ...[
                                    const SizedBox(height: 4),
                                    Text('Unterschrift-Art:', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                                    const SizedBox(height: 4),
                                    Wrap(spacing: 6, children: unterschriftArten.entries.map((u) => ChoiceChip(
                                      label: Text(u.value, style: TextStyle(fontSize: 11, color: vUnterschriftArt == u.key ? Colors.white : Colors.teal.shade700)),
                                      selected: vUnterschriftArt == u.key,
                                      selectedColor: Colors.teal.shade600,
                                      backgroundColor: Colors.teal.shade50,
                                      onSelected: (_) => setV(() => vUnterschriftArt = u.key),
                                    )).toList()),
                                  ],
                                  const SizedBox(height: 8),
                                  // 2. Gedruckt
                                  CheckboxListTile(
                                    value: vGedruckt,
                                    onChanged: (v) => setV(() => vGedruckt = v ?? false),
                                    title: const Text('Dokumente gedruckt', style: TextStyle(fontSize: 12)),
                                    secondary: Icon(Icons.print, size: 18, color: vGedruckt ? Colors.green.shade600 : Colors.grey.shade400),
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    controlAffinity: ListTileControlAffinity.leading,
                                  ),
                                  const SizedBox(height: 12),
                                  // 3. Datum
                                  TextField(controller: vDatumC, readOnly: true,
                                    decoration: InputDecoration(labelText: 'Versanddatum', prefixIcon: const Icon(Icons.calendar_today, size: 16), isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
                                    onTap: () async {
                                      final picked = await showDatePicker(context: vCtx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030), locale: const Locale('de'));
                                      if (picked != null) vDatumC.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                                    }),
                                  const SizedBox(height: 12),
                                  // 4. Versandart
                                  Text('Versandart:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                                  const SizedBox(height: 4),
                                  Wrap(spacing: 6, runSpacing: 4, children: methoden.entries.map((m) => ChoiceChip(
                                    label: Text(m.value, style: TextStyle(fontSize: 11, color: vMethode == m.key ? Colors.white : Colors.orange.shade700)),
                                    selected: vMethode == m.key,
                                    selectedColor: Colors.orange.shade600,
                                    backgroundColor: Colors.orange.shade50,
                                    onSelected: (_) => setV(() => vMethode = m.key),
                                  )).toList()),
                                  const SizedBox(height: 10),
                                  TextField(controller: vNotizC, decoration: InputDecoration(labelText: 'Notiz (optional)', isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)))),
                                ]))),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(vCtx), child: const Text('Abbrechen')),
                                  FilledButton(onPressed: () {
                                    if (vDatumC.text.isEmpty) return;
                                    verlauf.insert(0, {
                                      'datum': vDatumC.text.trim(),
                                      'methode': methoden[vMethode] ?? vMethode,
                                      'gedruckt': vGedruckt,
                                      'unterschrieben': vUnterschrieben,
                                      'unterschrift_art': vUnterschrieben ? (unterschriftArten[vUnterschriftArt] ?? vUnterschriftArt) : '',
                                      'notiz': vNotizC.text.trim(),
                                    });
                                    k['verlauf'] = verlauf;
                                    _kkKorrespondenz = korrespondenz;
                                    setDetailState(() {});
                                    setLocalState(() {});
                                    Navigator.pop(vCtx);
                                  }, style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade600), child: const Text('Speichern')),
                                ],
                              )));
                            },
                          ),
                        ]),
                        const SizedBox(height: 10),
                        Expanded(
                          child: verlauf.isEmpty
                            ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                                Icon(Icons.timeline, size: 40, color: Colors.grey.shade300),
                                const SizedBox(height: 6),
                                Text('Noch nicht versendet', style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                              ]))
                            : ListView.builder(
                                itemCount: verlauf.length,
                                itemBuilder: (_, vi) {
                                  final v = verlauf[vi];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 6),
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
                                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Row(children: [
                                        Icon(Icons.send, size: 16, color: Colors.orange.shade600),
                                        const SizedBox(width: 8),
                                        Text(v['datum']?.toString() ?? '', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.orange.shade700)),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          decoration: BoxDecoration(color: Colors.orange.shade200, borderRadius: BorderRadius.circular(8)),
                                          child: Text(v['methode']?.toString() ?? '', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
                                        ),
                                        const Spacer(),
                                        IconButton(
                                          icon: Icon(Icons.delete_outline, size: 14, color: Colors.red.shade400),
                                          onPressed: () {
                                            verlauf.removeAt(vi);
                                            k['verlauf'] = verlauf;
                                            _kkKorrespondenz = korrespondenz;
                                            setDetailState(() {});
                                          },
                                          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                        ),
                                      ]),
                                      // Status badges
                                      Padding(
                                        padding: const EdgeInsets.only(left: 24, top: 4),
                                        child: Wrap(spacing: 6, runSpacing: 2, children: [
                                          if (v['gedruckt'] == true)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(8)),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                Icon(Icons.print, size: 10, color: Colors.green.shade700),
                                                const SizedBox(width: 3),
                                                Text('Gedruckt', style: TextStyle(fontSize: 9, color: Colors.green.shade700, fontWeight: FontWeight.bold)),
                                              ]),
                                            ),
                                          if (v['unterschrieben'] == true)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(color: Colors.teal.shade100, borderRadius: BorderRadius.circular(8)),
                                              child: Row(mainAxisSize: MainAxisSize.min, children: [
                                                Icon(Icons.draw, size: 10, color: Colors.teal.shade700),
                                                const SizedBox(width: 3),
                                                Text('Unterschrieben (${v['unterschrift_art'] ?? ''})', style: TextStyle(fontSize: 9, color: Colors.teal.shade700, fontWeight: FontWeight.bold)),
                                              ]),
                                            ),
                                          if ((v['notiz']?.toString() ?? '').isNotEmpty)
                                            Text(v['notiz'], style: TextStyle(fontSize: 9, color: Colors.grey.shade600, fontStyle: FontStyle.italic)),
                                        ]),
                                      ),
                                    ]),
                                  );
                                },
                              ),
                        ),
                      ]),
                    ),
                ]),
              ),
            ]),
          ),
        )),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    if (value.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 10),
        SizedBox(width: 80, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  void _showKorrespondenzDialog(String behoerdeType, Map<String, dynamic> data, List<Map<String, dynamic>> korrespondenz, String richtung, StateSetter setLocalState) {
    final betreffC = TextEditingController();
    final erstelltAmC = TextEditingController();
    final zugestelltAmC = TextEditingController();
    final eingangAmC = TextEditingController(); // eingang: bei uns / ausgang: versendet am
    final notizC = TextEditingController();
    List<PlatformFile> selectedFiles = [];

    Widget datePicker(TextEditingController c, String label, BuildContext ctx2) {
      return TextField(
        controller: c,
        readOnly: true,
        decoration: InputDecoration(labelText: label, prefixIcon: const Icon(Icons.calendar_today, size: 16),
            isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
        style: const TextStyle(fontSize: 12),
        onTap: () async {
          final picked = await showDatePicker(context: ctx2, initialDate: DateTime.now(), firstDate: DateTime(2020), lastDate: DateTime(2030), locale: const Locale('de'));
          if (picked != null) c.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
        },
      );
    }

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) => AlertDialog(
        title: Row(children: [
          Icon(richtung == 'eingang' ? Icons.call_received : Icons.call_made, size: 18,
              color: richtung == 'eingang' ? Colors.green.shade700 : Colors.blue.shade700),
          const SizedBox(width: 8),
          Text(richtung == 'eingang' ? 'Eingang (empfangen)' : 'Ausgang (gesendet)', style: const TextStyle(fontSize: 15)),
        ]),
        content: SizedBox(width: 420, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Dates
          if (richtung == 'eingang') ...[
            datePicker(erstelltAmC, 'Erstellt am (Datum auf dem Schreiben)', ctx2),
            const SizedBox(height: 8),
            datePicker(zugestelltAmC, 'Zugestellt am (beim Kunden)', ctx2),
            const SizedBox(height: 8),
            datePicker(eingangAmC, 'Eingegangen am (bei uns)', ctx2),
          ] else ...[
            datePicker(erstelltAmC, 'Datum', ctx2),
          ],
          const SizedBox(height: 10),
          TextField(
            controller: betreffC,
            decoration: InputDecoration(labelText: 'Betreff', prefixIcon: const Icon(Icons.subject, size: 18),
                isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
          ),
          if (richtung == 'eingang') ...[
            const SizedBox(height: 10),
            TextField(
              controller: notizC,
              maxLines: 2,
              decoration: InputDecoration(labelText: 'Notiz (optional)', prefixIcon: const Icon(Icons.note, size: 18),
                  isDense: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(8))),
            ),
          ],
          const SizedBox(height: 10),
          // Document upload (multi-file, max 20)
          OutlinedButton.icon(
            icon: Icon(Icons.upload_file, size: 16, color: Colors.indigo.shade600),
            label: Text('Dokumente hochladen (max. 20)', style: TextStyle(fontSize: 11, color: Colors.indigo.shade600)),
            style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.indigo.shade300), minimumSize: const Size(double.infinity, 36)),
            onPressed: () async {
              final result = await FilePickerHelper.pickFiles(type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
              if (result != null && result.files.isNotEmpty) {
                setDlg(() {
                  for (final f in result.files) {
                    if (selectedFiles.length >= 20) break;
                    selectedFiles.add(f);
                  }
                });
              }
            },
          ),
          if (selectedFiles.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('${selectedFiles.length} Datei(en) ausgew\u00E4hlt:', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ...selectedFiles.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(children: [
                Icon(Icons.attach_file, size: 12, color: Colors.indigo.shade400),
                const SizedBox(width: 4),
                Expanded(child: Text(e.value.name, style: TextStyle(fontSize: 10, color: Colors.indigo.shade600), overflow: TextOverflow.ellipsis)),
                InkWell(onTap: () => setDlg(() => selectedFiles.removeAt(e.key)),
                    child: Icon(Icons.close, size: 12, color: Colors.red.shade400)),
              ]),
            )),
          ],
        ]))),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          FilledButton.icon(
            icon: const Icon(Icons.save, size: 16),
            label: const Text('Speichern'),
            style: FilledButton.styleFrom(backgroundColor: richtung == 'eingang' ? Colors.green.shade600 : Colors.blue.shade600),
            onPressed: () async {
              if (erstelltAmC.text.isEmpty) return;
              final entry = <String, dynamic>{
                'richtung': richtung,
                'datum': erstelltAmC.text.trim(),
                'erstellt_am': erstelltAmC.text.trim(),
                'zugestellt_am': zugestelltAmC.text.trim(),
                'eingegangen_am': eingangAmC.text.trim(),
                'betreff': betreffC.text.trim(),
                'notiz': notizC.text.trim(),
                'dokumente': <Map<String, dynamic>>[],
              };

              // Upload all selected files
              final List<Map<String, dynamic>> uploadedDocs = [];
              for (final file in selectedFiles) {
                if (file.path == null) continue;
                try {
                  final uploadResult = await widget.apiService.uploadKKKorrespondenz(
                    userId: widget.user.id,
                    richtung: richtung,
                    titel: betreffC.text.trim(),
                    datum: erstelltAmC.text.trim(),
                    betreff: betreffC.text.trim(),
                    notiz: notizC.text.trim(),
                    filePath: file.path,
                    fileName: file.name,
                  );
                  if (uploadResult['success'] == true) {
                    uploadedDocs.add({'name': file.name, 'id': uploadResult['data']?['id']?.toString() ?? ''});
                  }
                } catch (e) {
                  debugPrint('[KK Korrespondenz] Upload error: $e');
                }
              }
              entry['dokumente'] = uploadedDocs;
              if (uploadedDocs.isNotEmpty) {
                entry['dokument_name'] = uploadedDocs.first['name'];
                entry['id'] = uploadedDocs.first['id'];
              }

              korrespondenz.insert(0, entry);
              _kkKorrespondenz = korrespondenz;
              setLocalState(() {});
              if (ctx.mounted) Navigator.pop(ctx);
            },
          ),
        ],
      )),
    );
  }
}
