import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:io';
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';
import '../services/ticket_service.dart';
import '../models/user.dart';
import '../utils/file_picker_helper.dart';
import 'pflegebox_widget.dart';
import 'mitgliederverwaltung_behorde_krankenkasse_pflegegrad.dart';

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
  final _egkFotoDatumController = TextEditingController();
  final _pflegekasseNameController = TextEditingController();
  final _pflegedienstNameController = TextEditingController();
  Map<String, dynamic> _selectedPflegedienst = {};
  final _pflegegradSeitController = TextEditingController();
  final _befreiungGueltigBisController = TextEditingController();
  final _pflegeboxFirmaController = TextEditingController();
  final _pflegeboxDatumController = TextEditingController();
  final _pflegeboxNotizenController = TextEditingController();
  bool _controllersInitialized = false;

  // Class-level state (persists across tabs)
  String _versicherungsart = '';
  String _versichertenstatus = '';
  String _egkFotoSchreibenErhalten = ''; // '', 'ja', 'nein' — Krankenkasse-Schreiben zur Foto-Aktualisierung erhalten?
  String _egkFotoUploadWeg = '';         // '', 'post', 'online' — wie wurde das Foto eingereicht
  bool _fotoSchreibenUploading = false;  // Upload des Aufforderungs-Schreibens läuft
  bool _befreiungskarte = false;
  String _befreiungJahr = '';
  // Krankengeld dossier count — surfaced by the new tab via callback,
  // shown in the tab title so the operator sees at a glance whether
  // the member has open KG cases.
  int _krankengeldCount = 0;
  String _pflegegrad = '';
  String _pflegeboxVersandart = '';
  String _pflegeboxStatus = '';
  int? _pflegeboxFirmaId;
  String _pflegeboxFirmaName = '';
  List<Map<String, dynamic>> _termine = [];

  bool _stammdatenLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadKrankenkassenStammdaten();
  }

  /// Krankenkassen-Datenbank vom Server laden (Name, Zusatzbeitrag, Rating).
  /// Fuellt _dbKrankenkassen* — _getKrankenkassenListe bevorzugt DB vor der statischen Liste,
  /// d.h. die Lupe/Auswahl arbeitet danach direkt auf der DB (Tabelle `krankenkassen`).
  Future<void> _loadKrankenkassenStammdaten() async {
    if (_stammdatenLoaded) return;
    _stammdatenLoaded = true;
    try {
      final res = await widget.apiService.getKrankenkassenStammdaten();
      if (res['success'] == true && res['data'] is List) {
        final z25 = <String, double>{};
        final z26 = <String, double>{};
        final ratings = <String, double>{};
        for (final row in (res['data'] as List)) {
          if (row is! Map) continue;
          final name = row['name']?.toString() ?? '';
          if (name.isEmpty) continue;
          final v25 = double.tryParse('${row['zusatzbeitrag_2025'] ?? ''}');
          final v26 = double.tryParse('${row['zusatzbeitrag_2026'] ?? ''}');
          final rv = double.tryParse('${row['rating'] ?? ''}');
          if (v25 != null) z25[name] = v25;
          if (v26 != null) z26[name] = v26;
          if (rv != null) ratings[name] = rv;
        }
        if (mounted && (z25.isNotEmpty || z26.isNotEmpty)) {
          setState(() {
            if (z25.isNotEmpty) _dbKrankenkassenZusatzbeitrag[2025] = z25;
            if (z26.isNotEmpty) _dbKrankenkassenZusatzbeitrag[2026] = z26;
            _dbKrankenkassenRating
              ..clear()
              ..addAll(ratings);
          });
        }
      }
    } catch (_) {
      // Fallback: statische Liste im Code — kein Blocker fuer die UI.
    }
  }

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
      _egkFotoDatumController.text = data['egk_foto_datum'] ?? '';
      _pflegekasseNameController.text = (data['pflegekasse_name'] ?? '').toString().isNotEmpty ? data['pflegekasse_name'] : (data['name'] ?? '');
      _pflegedienstNameController.text = data['pflegedienst_name'] ?? '';
      if (data['selected_pflegedienst'] is Map) _selectedPflegedienst = Map<String, dynamic>.from(data['selected_pflegedienst'] as Map);
      _pflegegradSeitController.text = data['pflegegrad_seit'] ?? '';
      _befreiungGueltigBisController.text = data['befreiung_gueltig_bis'] ?? '';
      _pflegeboxFirmaController.text = data['pflegebox_firma'] ?? '';
      _pflegeboxDatumController.text = data['pflegebox_datum'] ?? '';
      _pflegeboxNotizenController.text = data['pflegebox_notizen'] ?? '';
      _versicherungsart = data['versicherungsart'] ?? '';
      _versichertenstatus = data['versichertenstatus'] ?? '';
      _egkFotoSchreibenErhalten = data['egk_foto_schreiben_erhalten'] ?? '';
      _egkFotoUploadWeg = data['egk_foto_upload_weg'] ?? '';
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
    _egkFotoDatumController.dispose();
    _pflegekasseNameController.dispose();
    _pflegedienstNameController.dispose();
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
      length: 8,
      child: Column(
        children: [
          TabBar(
            labelColor: Colors.blue.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.blue.shade700,
            isScrollable: true,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['name']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.local_hospital, size: 16), const SizedBox(width: 4), const Text('Zuständige Krankenkasse')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _getTermineListe(data).isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.calendar_month, size: 16), const SizedBox(width: 4), const Text('Termine')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _kkKorrespondenz.isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.mail, size: 16), const SizedBox(width: 4), const Text('Korrespondenz')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['pflegegrad']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.elderly, size: 16), const SizedBox(width: 4), const Text('Pflegegrad')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['versicherungsart']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.shield, size: 16), const SizedBox(width: 4), const Text('Versicherung')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['kvnr']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.credit_card, size: 16), const SizedBox(width: 4), const Text('Versicherungskarte')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: (data['befreiungskarte'] == true || data['befreiungskarte'] == 'true' || data['befreiungskarte'] == '1') ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.card_membership, size: 16), const SizedBox(width: 4), const Text('Befreiungskarte')])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.circle, size: 8, color: _krankengeldCount > 0 ? Colors.green : Colors.red), const SizedBox(width: 4), const Icon(Icons.medical_information, size: 16), const SizedBox(width: 4), Text('Krankengeld${_krankengeldCount > 0 ? " ($_krankengeldCount)" : ""}')])),
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
                _buildVersicherungskarteTab(data),
                _buildBefreiungskarteTab(data),
                _KrankengeldTab(apiService: widget.apiService, userId: widget.user.id, onCountChanged: (n) => setState(() => _krankengeldCount = n)),
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
          _sectionHeader(Icons.local_hospital, 'Zuständige Krankenkasse', Colors.blue),
          const SizedBox(height: 8),
          widget.dienststelleBuilder(type, _dienststelleController),
          Text('Zuständige Krankenkasse', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          _buildKrankenkassePickerField(),
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
        ],
      ),
    );
  }

  // ── Lupe-Auswahlfeld für die zuständige Krankenkasse ──
  // Tippbares Feld (Lupe) -> öffnet einen Such-Dialog auf Basis der
  // Krankenkassen-Datenbank (Tabelle `krankenkassen`, mit statischem Fallback).
  Widget _buildKrankenkassePickerField() {
    final selected = _krankenkasseNameController.text.trim();
    final rating = selected.isNotEmpty ? _getKrankenkassenRatingValue(selected) : null;
    return InkWell(
      onTap: _showKrankenkassePicker,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: selected.isEmpty
              ? const Icon(Icons.arrow_drop_down, size: 24)
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  tooltip: 'Auswahl entfernen',
                  onPressed: () {
                    _krankenkasseNameController.clear();
                    setState(() {});
                  },
                ),
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        child: selected.isEmpty
            ? Text('Zuständige Krankenkasse suchen…', style: TextStyle(fontSize: 14, color: Colors.grey.shade500))
            : Row(children: [
                Expanded(child: Text(selected, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                if (rating != null) _starRating(rating, size: 13),
              ]),
      ),
    );
  }

  Future<void> _showKrankenkassePicker() async {
    final currentYear = DateTime.now().year;
    final all = _getKrankenkassenListe(currentYear);
    final controller = TextEditingController();
    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return StatefulBuilder(builder: (sheetCtx, setSheet) {
          final q = controller.text.trim().toLowerCase();
          final filtered = q.isEmpty ? all : all.where((k) => k.toLowerCase().contains(q)).toList();
          final mq = MediaQuery.of(sheetCtx);
          return Padding(
            padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
            child: Container(
              height: mq.size.height * 0.82,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(children: [
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 40, height: 4,
                  decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 6),
                  child: Row(children: [
                    Icon(Icons.local_hospital, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    const Expanded(child: Text('Zuständige Krankenkasse wählen', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
                    IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TextField(
                    controller: controller,
                    autofocus: true,
                    onChanged: (_) => setSheet(() {}),
                    decoration: InputDecoration(
                      hintText: 'Suchen (Name, z.B. AOK, TK, Barmer)…',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: controller.text.isEmpty
                          ? null
                          : IconButton(icon: const Icon(Icons.clear), onPressed: () => setSheet(() => controller.clear())),
                      isDense: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: Row(children: [
                    Text('${filtered.length} Kassen', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    const Spacer(),
                    Text('Quelle: Krankenkassen-Datenbank', style: TextStyle(fontSize: 10, color: Colors.grey.shade400)),
                  ]),
                ),
                const Divider(height: 1),
                Expanded(
                  child: filtered.isEmpty
                      ? _pickerEmptyState(controller.text.trim(), sheetCtx)
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                          itemBuilder: (itemCtx, i) {
                            final kasse = filtered[i];
                            final zusatz = _getZusatzbeitrag(kasse, currentYear);
                            final gesamt = _getGesamtbeitrag(kasse, currentYear);
                            final rating = _getKrankenkassenRatingValue(kasse);
                            final isSel = kasse == _krankenkasseNameController.text.trim();
                            return ListTile(
                              dense: true,
                              selected: isSel,
                              selectedTileColor: Colors.blue.shade50,
                              leading: CircleAvatar(
                                radius: 16,
                                backgroundColor: Colors.blue.shade50,
                                child: Icon(Icons.local_hospital, size: 16, color: Colors.blue.shade700),
                              ),
                              title: Text(kasse, style: TextStyle(fontSize: 13, fontWeight: isSel ? FontWeight.bold : FontWeight.w500)),
                              subtitle: _starRating(rating, size: 12),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text('${gesamt.toStringAsFixed(2)}%', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
                                  if (zusatz != null) Text('+${zusatz.toStringAsFixed(2)}% Zusatz', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                                ],
                              ),
                              onTap: () => Navigator.pop(sheetCtx, kasse),
                            );
                          },
                        ),
                ),
              ]),
            ),
          );
        });
      },
    );
    controller.dispose();
    if (selected != null && selected.isNotEmpty) {
      _krankenkasseNameController.text = selected;
      setState(() {});
    }
  }

  Widget _pickerEmptyState(String query, BuildContext sheetCtx) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off, size: 42, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('Keine Kasse gefunden', style: TextStyle(fontSize: 14, color: Colors.grey.shade600)),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.add, size: 18),
              label: Text('„$query" übernehmen'),
              onPressed: () => Navigator.pop(sheetCtx, query),
            ),
          ],
        ]),
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
    return DefaultTabController(
      length: 2,
      child: Column(children: [
        Container(
          color: Colors.purple.shade50,
          child: TabBar(
            labelColor: Colors.purple.shade700,
            unselectedLabelColor: Colors.grey.shade600,
            indicatorColor: Colors.purple.shade700,
            tabs: [
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.circle, size: 8, color: (data['pflegegrad']?.toString() ?? '').isNotEmpty ? Colors.green : Colors.red),
                const SizedBox(width: 4), const Icon(Icons.elderly, size: 16),
                const SizedBox(width: 4), const Text('Zuständige Pflegekasse'),
              ])),
              Tab(child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.assignment, size: 16),
                SizedBox(width: 4),
                Text('Pflegestufe / Anträge'),
              ])),
            ],
          ),
        ),
        Expanded(child: TabBarView(children: [
          _buildPflegegradZustaendigTab(data),
          MitgliederverwaltungBehordeKrankenkassePflegegrad(
            apiService: widget.apiService,
            userId: widget.user.id,
            member: widget.user,
          ),
        ])),
      ]),
    );
  }

  Widget _buildPflegegradZustaendigTab(Map<String, dynamic> data) {
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
          Text('Pflegedienst', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          const SizedBox(height: 4),
          TextField(
            controller: _pflegedienstNameController,
            readOnly: true,
            decoration: InputDecoration(
              hintText: 'Pflegedienst auswählen...',
              prefixIcon: const Icon(Icons.medical_services, size: 20),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                  icon: const Icon(Icons.search, size: 20),
                  tooltip: 'Pflegedienst suchen',
                  onPressed: () => _showPflegedienstSuche(),
                ),
                if (_pflegedienstNameController.text.isNotEmpty)
                  IconButton(
                    icon: Icon(Icons.clear, size: 18, color: Colors.red.shade300),
                    tooltip: 'Entfernen',
                    onPressed: () => setState(() {
                      _pflegedienstNameController.clear();
                      _selectedPflegedienst = {};
                    }),
                  ),
              ]),
            ),
            style: const TextStyle(fontSize: 14),
            onTap: () => _showPflegedienstSuche(),
          ),
          if (_selectedPflegedienst.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: Colors.purple.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.purple.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_selectedPflegedienst['name']?.toString() ?? '', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.purple.shade800)),
                if ((_selectedPflegedienst['strasse']?.toString() ?? '').isNotEmpty || (_selectedPflegedienst['plz_ort']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                    Icon(Icons.location_on, size: 14, color: Colors.purple.shade600),
                    const SizedBox(width: 4),
                    Text('${_selectedPflegedienst['strasse'] ?? ''}, ${_selectedPflegedienst['plz_ort'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.purple.shade700)),
                  ])),
                if ((_selectedPflegedienst['telefon']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                    Icon(Icons.phone, size: 14, color: Colors.purple.shade600),
                    const SizedBox(width: 4),
                    Text(_selectedPflegedienst['telefon'].toString(), style: TextStyle(fontSize: 12, color: Colors.purple.shade700)),
                  ])),
                if ((_selectedPflegedienst['email']?.toString() ?? '').isNotEmpty)
                  Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                    Icon(Icons.email, size: 14, color: Colors.purple.shade600),
                    const SizedBox(width: 4),
                    Text(_selectedPflegedienst['email'].toString(), style: TextStyle(fontSize: 12, color: Colors.purple.shade700)),
                  ])),
              ]),
            ),
          ],
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
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.teal.shade200),
            ),
            child: Row(children: [
              Icon(Icons.credit_card, size: 18, color: Colors.teal.shade700),
              const SizedBox(width: 8),
              Expanded(child: Text('Gesundheitskarte (eGK) und EHIC-Rückseite befinden sich jetzt im Tab „Versicherungskarte".', style: TextStyle(fontSize: 12, color: Colors.teal.shade800))),
            ]),
          ),
        ],
      ),
    );
  }

  // ============ TAB (neu): VERSICHERUNGSKARTE ============
  // Visuelle Vorschau der elektronischen Gesundheitskarte (eGK) im Design der
  // jeweiligen Krankenkasse + EHIC-Rueckseite. Die eGK-Datenfelder wurden aus
  // dem Versicherung-Tab hierher verschoben (gleiche Controller / DB-Felder).

  /// Markenfarben je Krankenkasse — als "ideale Nachbildung" ohne geschuetzte
  /// Original-Logos (Wortmarke + Markenfarbe statt Bild-Logo).
  _EgkTheme _egkThemeFor(String raw) {
    final n = raw.toLowerCase().trim();
    _EgkTheme mk(int a, int b, {String? mark, Color on = Colors.white}) =>
        _EgkTheme(Color(a), Color(b), on, mark);
    if (n.contains('aok')) return mk(0xFF00A94F, 0xFF007A38, mark: 'AOK');
    if (n.contains('techniker') || n == 'tk' || n.startsWith('tk ') || n.startsWith('tk-')) return mk(0xFF1A3C7A, 0xFF0E2551, mark: 'TK');
    if (n.contains('barmer')) return mk(0xFF3AAA35, 0xFF247A1D, mark: 'BARMER');
    if (n.contains('dak')) return mk(0xFFE2001A, 0xFF9C0012, mark: 'DAK');
    if (n.contains('ikk')) return mk(0xFF004F9F, 0xFF00356B, mark: 'IKK');
    if (n.contains('kkh')) return mk(0xFF009AA6, 0xFF006A73, mark: 'KKH');
    if (n.contains('hkk')) return mk(0xFFE2001A, 0xFF9C0012, mark: 'hkk');
    if (n.contains('knappschaft')) return mk(0xFF0F4C81, 0xFF083254, mark: 'KBS');
    if (n.contains('viactiv')) return mk(0xFFEC6608, 0xFFB44B04, mark: 'VIACTIV');
    if (n.contains('big direkt') || n.startsWith('big ') || n == 'big') return mk(0xFFF39200, 0xFFB56A00, mark: 'BIG');
    if (n.contains('mobil')) return mk(0xFF6FAF2A, 0xFF4A7A14, mark: 'Mobil');
    if (n.contains('sbk') || n.contains('siemens')) return mk(0xFF4C9C2E, 0xFF2F6B18, mark: 'SBK');
    if (n.contains('mhplus')) return mk(0xFF0075BF, 0xFF004E80, mark: 'mhplus');
    if (n.contains('pronova')) return mk(0xFF0090D4, 0xFF005E8C, mark: 'pronova');
    if (n.contains('audi')) return mk(0xFF262626, 0xFF000000, mark: 'Audi BKK');
    if (n.contains('bmw')) return mk(0xFF0066B1, 0xFF00437A, mark: 'BMW BKK');
    if (n.contains('bosch')) return mk(0xFF00539C, 0xFF00365F, mark: 'Bosch BKK');
    if (n.contains('bertelsmann')) return mk(0xFF3B3B3B, 0xFF1A1A1A, mark: 'Bertelsmann BKK');
    if (n.contains('heimat')) return mk(0xFF00713B, 0xFF004D28, mark: 'Heimat');
    if (n.contains('vivida')) return mk(0xFF6A1F7A, 0xFF441150, mark: 'vivida bkk');
    if (n.contains('salus')) return mk(0xFFE30613, 0xFF9C0410, mark: 'Salus BKK');
    if (n.contains('bkk')) return mk(0xFF0069B4, 0xFF00477A, mark: 'BKK');
    // Standard: neutrales Blaugrau, volle Kassenbezeichnung als Wortmarke
    return mk(0xFF37556B, 0xFF223546, mark: null);
  }

  String _holderVornameFull() {
    final v1 = (widget.user.vorname ?? '').trim();
    final v2 = (widget.user.vorname2 ?? '').trim();
    final j = [v1, v2].where((s) => s.isNotEmpty).join(' ');
    return j;
  }

  String _holderNameZeile() {
    final n = (widget.user.nachname ?? '').trim();
    final v = _holderVornameFull();
    if (n.isEmpty && v.isEmpty) return widget.user.name;
    return [n, v].where((s) => s.isNotEmpty).join(', ');
  }

  String _fmtDate(String? s) {
    final v = (s ?? '').trim();
    if (v.isEmpty) return '';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(v);
    if (m != null) return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
    return v;
  }

  String _mmYY(String d) {
    final m = RegExp(r'(\d{2})\.(\d{2})\.(\d{4})').firstMatch(d);
    if (m != null) return '${m.group(2)}/${m.group(3)!.substring(2)}';
    return d;
  }

  String _fmtD(DateTime d) => '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

  DateTime? _parseDeDate(String s) {
    final m = RegExp(r'^(\d{2})\.(\d{2})\.(\d{4})$').firstMatch(s.trim());
    if (m == null) return null;
    final d = int.tryParse(m.group(1)!);
    final mo = int.tryParse(m.group(2)!);
    final y = int.tryParse(m.group(3)!);
    if (d == null || mo == null || y == null) return null;
    return DateTime(y, mo, d);
  }

  Widget _stepHeader(String num, String title, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 6),
      child: Row(children: [
        Container(
          width: 20, height: 20, alignment: Alignment.center,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          child: Text(num, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Text(title, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color))),
      ]),
    );
  }

  /// Schritt 1: Aufforderungs-Schreiben der Krankenkasse anhängen (max. 20 Dateien),
  /// gespeichert als eingehende KK-Korrespondenz.
  Future<void> _uploadFotoSchreiben() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePickerHelper.pickFiles(
        type: FileType.custom, allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png'], allowMultiple: true);
    if (picked == null || picked.files.isEmpty) return;
    final files = picked.files.take(20).toList();
    if (mounted) setState(() => _fotoSchreibenUploading = true);
    final heute = _fmtD(DateTime.now());
    int ok = 0;
    for (final f in files) {
      if (f.path == null) continue;
      try {
        final r = await widget.apiService.uploadKKKorrespondenz(
          userId: widget.user.id,
          richtung: 'eingang',
          titel: 'Lichtbild-Aufforderung (eGK)',
          datum: heute,
          betreff: 'Lichtbild-Aufforderung (eGK)',
          notiz: 'Aufforderung zur Aktualisierung des eGK-Lichtbilds',
          filePath: f.path,
          fileName: f.name,
        );
        if (r['success'] == true) ok++;
      } catch (_) {}
    }
    // Neu laden, damit die angehängten Schreiben direkt in der Sektion erscheinen.
    _kkKorrLoaded = false;
    await _loadKKKorrespondenz();
    if (!mounted) return;
    setState(() => _fotoSchreibenUploading = false);
    messenger.showSnackBar(SnackBar(
      content: Text(ok > 0 ? '$ok/${files.length} Schreiben angehängt' : 'Upload fehlgeschlagen (0/${files.length})'),
      backgroundColor: ok > 0 ? Colors.green : Colors.red,
    ));
  }

  /// Die angehängten „Lichtbild-Aufforderung"-Dokumente aus der KK-Korrespondenz.
  List<Map<String, dynamic>> _lichtbildAufforderungDocs() {
    final out = <Map<String, dynamic>>[];
    for (final k in _kkKorrespondenz) {
      if ((k['titel']?.toString() ?? '').contains('Lichtbild-Aufforderung') && k['dokumente'] is List) {
        for (final d in (k['dokumente'] as List)) {
          if (d is Map) out.add(Map<String, dynamic>.from(d));
        }
      }
    }
    return out;
  }

  Future<void> _openKKKorrDoc(int id, String name) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final response = await widget.apiService.downloadKKKorrespondenzDoc(id);
      if (response.statusCode == 200) {
        final dir = await getTemporaryDirectory();
        final file = File('${dir.path}/$name');
        await file.writeAsBytes(response.bodyBytes);
        if (!mounted) return;
        await FileViewerDialog.show(context, file.path, name);
      } else {
        if (!mounted) return;
        messenger.showSnackBar(const SnackBar(content: Text('Dokument konnte nicht geladen werden'), backgroundColor: Colors.red));
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  // Ziel-Maße Passbild (35:45 @ 300 dpi ≈ 413×531 px)
  static const int _fotoTargetW = 413;
  static const int _fotoTargetH = 531;

  Future<ui.Image?> _decodeImg(Uint8List bytes) {
    final c = Completer<ui.Image?>();
    try {
      ui.decodeImageFromList(bytes, (img) => c.complete(img));
    } catch (_) {
      c.complete(null);
    }
    return c.future;
  }

  /// Prüft ein Lichtbild gegen die eGK-Anforderungen (Format, Größe, Auflösung, Seitenverhältnis).
  _FotoCheck _checkImage(PlatformFile f, ui.Image? img) {
    final issues = <String>[];
    final warns = <String>[];
    final ext = (f.extension ?? '').toLowerCase();
    if (!['jpg', 'jpeg', 'png'].contains(ext)) {
      issues.add('Format ${ext.isEmpty ? '?' : '.$ext'} — nur JPG/PNG erlaubt');
    }
    final sizeMB = f.size / (1024 * 1024);
    if (sizeMB > 10) {
      issues.add('Datei zu groß: ${sizeMB.toStringAsFixed(1)} MB (max. 10 MB)');
    } else if (sizeMB > 5) {
      warns.add('Datei ${sizeMB.toStringAsFixed(1)} MB — manche Kassen erlauben nur 5 MB');
    }
    if (img == null) {
      warns.add('Bildmaße konnten nicht automatisch geprüft werden');
    } else {
      final w = img.width, h = img.height;
      if (w < 320 || h < 411) {
        issues.add('Auflösung zu gering: ${w}×$h px (mind. 320×411 px)');
      } else if (w < _fotoTargetW || h < _fotoTargetH) {
        warns.add('Auflösung ${w}×$h px — empfohlen mind. ${_fotoTargetW}×$_fotoTargetH px');
      }
      if (h < w) {
        issues.add('Querformat (${w}×$h px) — ein Passbild muss Hochformat sein');
      } else {
        final ratio = w / h;
        const ideal = 35 / 45; // 0,778
        if ((ratio - ideal).abs() > 0.06) {
          warns.add('Seitenverhältnis ${ratio.toStringAsFixed(2)} ≠ 35:45 (0,78) — Zuschnitt nötig');
        }
      }
    }
    return _FotoCheck(issues, warns, imgW: img?.width, imgH: img?.height);
  }

  /// Passt ein Bild automatisch an: mittiger Zuschnitt auf 35:45 und Skalierung auf 413×531 px (PNG).
  Future<Uint8List?> _adaptLichtbild(ui.Image src) async {
    try {
      final sw = src.width.toDouble(), sh = src.height.toDouble();
      const targetRatio = _fotoTargetW / _fotoTargetH;
      double cropW, cropH;
      if (sw / sh > targetRatio) {
        cropH = sh;
        cropW = sh * targetRatio;
      } else {
        cropW = sw;
        cropH = sw / targetRatio;
      }
      final srcRect = Rect.fromLTWH((sw - cropW) / 2, (sh - cropH) / 2, cropW, cropH);
      final dstRect = Rect.fromLTWH(0, 0, _fotoTargetW.toDouble(), _fotoTargetH.toDouble());
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(dstRect, Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawImageRect(src, srcRect, dstRect, Paint()..filterQuality = FilterQuality.high..isAntiAlias = true);
      final outImg = await recorder.endRecording().toImage(_fotoTargetW, _fotoTargetH);
      final bd = await outImg.toByteData(format: ui.ImageByteFormat.png);
      return bd?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  Future<String> _writeTemp(Uint8List bytes, String name) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$name');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Schritt 2: Lichtbild hochladen — mit Anforderungs-Prüfung und optionaler
  /// automatischer Anpassung (Zuschnitt/Skalierung) inkl. Vorher/Nachher-Vorschau.
  Future<void> _uploadLichtbildFoto() async {
    final messenger = ScaffoldMessenger.of(context);
    final picked = await FilePickerHelper.pickFiles(
        type: FileType.custom, allowedExtensions: ['jpg', 'jpeg', 'png'], allowMultiple: false);
    if (picked == null || picked.files.isEmpty) return;
    final f = picked.files.first;
    if (f.path == null) return;
    Uint8List origBytes;
    try {
      origBytes = await File(f.path!).readAsBytes();
    } catch (_) {
      return;
    }
    final img = await _decodeImg(origBytes);
    final check = _checkImage(f, img);
    if (!mounted) return;

    // Bereits konform → direkt hochladen.
    if (check.perfect) {
      await _doUploadLichtbild(f.name, f.path!, messenger, 'Anforderungen erfüllt');
      return;
    }

    // Nicht konform → angepasste Version erzeugen und Vorher/Nachher zeigen.
    final adapted = img == null ? null : await _adaptLichtbild(img);
    if (!mounted) return;
    final choice = await _showFotoAdaptDialog(origBytes, adapted, check, f.name);
    if (choice == null || !mounted) return;
    if (choice == 'adapted' && adapted != null) {
      final path = await _writeTemp(adapted, 'egk_lichtbild_${DateTime.now().millisecondsSinceEpoch}.png');
      await _doUploadLichtbild('eGK-Lichtbild_${_fotoTargetW}x$_fotoTargetH.png', path, messenger, 'automatisch angepasst auf ${_fotoTargetW}×$_fotoTargetH px');
    } else {
      await _doUploadLichtbild(f.name, f.path!, messenger, 'Original (nicht angepasst)');
    }
  }

  Future<void> _doUploadLichtbild(String fileName, String path, ScaffoldMessengerState messenger, String? note) async {
    try {
      final r = await widget.apiService.uploadKKKorrespondenz(
        userId: widget.user.id,
        richtung: 'ausgang',
        titel: 'eGK-Lichtbild (Foto)',
        datum: _fmtD(DateTime.now()),
        betreff: 'eGK-Lichtbild (Foto)',
        notiz: 'Lichtbild für die eGK${note != null ? ' — $note' : ''}',
        filePath: path,
        fileName: fileName,
      );
      _kkKorrLoaded = false;
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(
        content: Text(r['success'] == true
            ? 'Lichtbild „$fileName" gespeichert${note != null ? ' ($note)' : ''}'
            : 'Fehler beim Hochladen des Lichtbilds'),
        backgroundColor: r['success'] == true ? Colors.green : Colors.red,
      ));
    } catch (_) {
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Fehler beim Hochladen des Lichtbilds'), backgroundColor: Colors.red));
    }
  }

  /// Vorher/Nachher-Dialog. Rückgabe: 'adapted', 'original' oder null (Abbruch).
  Future<String?> _showFotoAdaptDialog(Uint8List origBytes, Uint8List? adaptedBytes, _FotoCheck check, String fileName) {
    Widget frame(String caption, Widget child, Color c) => Expanded(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(caption, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: c)),
            const SizedBox(height: 4),
            AspectRatio(
              aspectRatio: 35 / 45,
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: c, width: 1.5), borderRadius: BorderRadius.circular(4)),
                clipBehavior: Clip.antiAlias,
                child: child,
              ),
            ),
          ]),
        );
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          Icon(check.hasHardFail ? Icons.error_outline : Icons.warning_amber, color: check.hasHardFail ? Colors.red : Colors.orange, size: 22),
          const SizedBox(width: 8),
          const Expanded(child: Text('Foto-Prüfung & Anpassung', style: TextStyle(fontSize: 16))),
        ]),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(fileName, style: TextStyle(fontSize: 11, color: Colors.grey.shade600), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              frame('Original${check.imgW != null ? ' (${check.imgW}×${check.imgH})' : ''}', Image.memory(origBytes, fit: BoxFit.cover), Colors.grey.shade500),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward, size: 18, color: Colors.teal.shade600),
              const SizedBox(width: 8),
              adaptedBytes != null
                  ? frame('Angepasst (${_fotoTargetW}×$_fotoTargetH)', Image.memory(adaptedBytes, fit: BoxFit.cover), Colors.teal.shade600)
                  : frame('Angepasst', Container(color: Colors.grey.shade100, child: Icon(Icons.block, color: Colors.grey.shade400)), Colors.grey.shade400),
            ]),
            const SizedBox(height: 10),
            Text('Prüfung des Originals:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
            const SizedBox(height: 3),
            ...check.issues.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.cancel, size: 14, color: Colors.red.shade600),
                    const SizedBox(width: 5),
                    Expanded(child: Text(s, style: TextStyle(fontSize: 11, color: Colors.red.shade800))),
                  ]),
                )),
            ...check.warns.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 3),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade700),
                    const SizedBox(width: 5),
                    Expanded(child: Text(s, style: TextStyle(fontSize: 11, color: Colors.orange.shade900))),
                  ]),
                )),
            const SizedBox(height: 6),
            Text('„Angepasst" schneidet mittig auf 35:45 zu und skaliert auf ${_fotoTargetW}×$_fotoTargetH px (PNG).', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'original'), child: const Text('Original')),
          if (adaptedBytes != null)
            FilledButton.icon(
              onPressed: () => Navigator.pop(ctx, 'adapted'),
              icon: const Icon(Icons.auto_fix_high, size: 16),
              label: const Text('Angepasst hochladen'),
              style: FilledButton.styleFrom(backgroundColor: Colors.teal.shade700),
            ),
        ],
      ),
    );
  }

  /// Schritt 1: Ticket zur Bearbeitung erstellen (neues Foto beim Mitglied einholen),
  /// mit Duplikat-Prüfung.
  Future<void> _createFotoBearbeitenTicket() async {
    final messenger = ScaffoldMessenger.of(context);
    const subject = 'eGK: Lichtbild-Aufforderung bearbeiten';
    final kasse = _krankenkasseNameController.text.trim();
    final now = DateTime.now();
    // Server prüft atomar auf ein bereits vorhandenes offenes Ticket (dedupeSubject).
    final result = await widget.ticketService.createTicketForMember(
      adminMitgliedernummer: widget.adminMitgliedernummer,
      memberMitgliedernummer: widget.user.mitgliedernummer,
      subject: subject,
      message: 'Die Krankenkasse${kasse.isNotEmpty ? ' ($kasse)' : ''} hat ein Schreiben zur Aktualisierung '
          'des eGK-Lichtbilds geschickt (in der KK-Korrespondenz hinterlegt).\n\n'
          'Bitte ein neues Foto vom Mitglied einholen und bei der Krankenkasse einreichen.',
      priority: 'high',
      scheduledDate: '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}',
      dedupeSubject: true,
    );
    if (!mounted) return;
    if (result['duplicate'] == true) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Es existiert bereits ein offenes Bearbeitungs-Ticket für dieses Mitglied.'), backgroundColor: Colors.orange));
    } else if (result.containsKey('ticket')) {
      messenger.showSnackBar(const SnackBar(content: Text('Bearbeitungs-Ticket erstellt'), backgroundColor: Colors.green));
    } else {
      messenger.showSnackBar(SnackBar(content: Text(result['error']?.toString() ?? 'Fehler beim Erstellen des Tickets'), backgroundColor: Colors.red));
    }
  }

  /// Erinnerungs-Ticket für die naechste eGK-Foto-Aktualisierung (gesetzlich alle 10 Jahre).
  /// Faellig = letztes Einreichungsdatum + 10 Jahre, sonst heute + 10 Jahre.
  /// Prüft vorher auf ein bereits existierendes Erinnerungs-Ticket (keine Duplikate).
  Future<void> _createFotoErinnerung(DateTime? faellig) async {
    final messenger = ScaffoldMessenger.of(context);
    const subject = 'eGK: Neues Lichtbild einreichen';
    final now = DateTime.now();
    final due = faellig ?? DateTime(now.year + 10, now.month, now.day);
    final scheduledStr = '${due.year}-${due.month.toString().padLeft(2, '0')}-${due.day.toString().padLeft(2, '0')}';
    final kasse = _krankenkasseNameController.text.trim();
    // Server prüft atomar, ob für dieses Mitglied bereits ein solches Erinnerungs-
    // Ticket existiert (dedupeSubject) — kein Duplikat für die 10-Jahres-Erinnerung.
    final result = await widget.ticketService.createTicketForMember(
      adminMitgliedernummer: widget.adminMitgliedernummer,
      memberMitgliedernummer: widget.user.mitgliedernummer,
      subject: subject,
      message: 'Das Lichtbild für die elektronische Gesundheitskarte muss gesetzlich alle 10 Jahre '
          'bei der Krankenkasse aktualisiert werden (Pflicht ab dem 15. Lebensjahr).\n\n'
          'Bitte ein neues Foto bei der Krankenkasse${kasse.isNotEmpty ? ' ($kasse)' : ''} einreichen '
          '(Online-Upload-Tool, Kassen-App oder per Post).\n\n'
          'Fällig: ${_fmtD(due)}\n'
          'Versicherten-Nr. (KVNR): ${_kvnrController.text.trim()}',
      priority: 'medium',
      scheduledDate: scheduledStr,
      dedupeSubject: true,
    );
    if (!mounted) return;
    if (result['duplicate'] == true) {
      final sd = result['scheduled_date']?.toString() ?? '';
      final jahr = sd.length >= 4 ? sd.substring(0, 4) : '';
      messenger.showSnackBar(SnackBar(
        content: Text('Für dieses Mitglied existiert bereits ein Erinnerungs-Ticket${jahr.isNotEmpty ? ' (geplant $jahr)' : ''}.'),
        backgroundColor: Colors.orange,
      ));
    } else if (result.containsKey('ticket')) {
      messenger.showSnackBar(SnackBar(
        content: Text('Foto-Erinnerung erstellt (geplant: ${_fmtD(due)})'),
        backgroundColor: Colors.green,
      ));
    } else {
      messenger.showSnackBar(SnackBar(
        content: Text(result['error']?.toString() ?? 'Fehler beim Erstellen des Tickets'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _copyValue(String value, String label) {
    final v = value.trim();
    if (v.isEmpty) return;
    Clipboard.setData(ClipboardData(text: v));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label kopiert'), duration: const Duration(seconds: 1)),
    );
  }

  Widget _cardCaption(IconData icon, String text) {
    return Row(children: [
      Icon(icon, size: 15, color: Colors.grey.shade600),
      const SizedBox(width: 6),
      Expanded(child: Text(text, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700))),
    ]);
  }

  Widget _cardScaler(Widget card) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: AspectRatio(
          aspectRatio: 430 / 271, // ISO/IEC 7810 ID-1 (Scheckkartenformat)
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: 430, height: 271, child: card),
          ),
        ),
      ),
    );
  }

  Widget _egkChip() {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        gradient: const LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [Color(0xFFF2D98A), Color(0xFFC9A94A), Color(0xFFAE8A2E)],
        ),
        border: Border.all(color: const Color(0xFF9A7A26), width: 0.5),
      ),
      child: CustomPaint(painter: _EgkChipPainter()),
    );
  }

  Widget _frontField(Color on, String label, String value, {double valueSize = 13, bool bold = false, bool mono = false, String ph = '—'}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Text(label.toUpperCase(), style: TextStyle(color: on.withValues(alpha: 0.68), fontSize: 8, fontWeight: FontWeight.w600, letterSpacing: 0.6)),
      const SizedBox(height: 1),
      Text(
        value.isEmpty ? ph : value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: on,
          fontSize: valueSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          letterSpacing: mono ? 1.1 : 0,
          fontFamily: mono ? 'monospace' : null,
        ),
      ),
    ]);
  }

  Widget _ehicField(String label, String value, {String ph = '—'}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5, right: 6),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(label, style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 7.5, fontWeight: FontWeight.w700, letterSpacing: 0.2)),
        Text(value.isEmpty ? ph : value, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildEgkFrontCard(_EgkTheme t) {
    final kasse = _krankenkasseNameController.text.trim();
    final wordmark = t.mark ?? (kasse.isEmpty ? 'Krankenkasse' : kasse);
    final showSub = t.mark != null && kasse.isNotEmpty && kasse.toLowerCase() != t.mark!.toLowerCase();
    final on = t.onPrimary;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [t.primary, t.primaryDark]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          Positioned(right: -60, top: -60, child: Container(width: 180, height: 180, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.06)))),
          Positioned(right: 30, bottom: -80, child: Container(width: 160, height: 160, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withValues(alpha: 0.05)))),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(wordmark, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on, fontSize: 26, fontWeight: FontWeight.w800, letterSpacing: 0.3, height: 1.0)),
                  if (showSub) Padding(padding: const EdgeInsets.only(top: 2), child: Text(kasse, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: on.withValues(alpha: 0.85), fontSize: 11, fontWeight: FontWeight.w500))),
                ])),
                const SizedBox(width: 10),
                Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                  Text('Gesundheitskarte', style: TextStyle(color: on, fontSize: 13, fontWeight: FontWeight.w700)),
                  Text('Versicherungskarte', style: TextStyle(color: on.withValues(alpha: 0.7), fontSize: 9)),
                ]),
              ]),
              const SizedBox(height: 18),
              Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                    width: 78, height: 96,
                    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(6)),
                    child: Icon(Icons.person, size: 54, color: t.primary.withValues(alpha: 0.55)),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(width: 46, height: 34, child: _egkChip()),
                ]),
                const SizedBox(width: 18),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _frontField(on, 'Name, Vorname', _holderNameZeile(), valueSize: 15, bold: true),
                  const SizedBox(height: 9),
                  _frontField(on, 'Versicherten-Nr.', _kvnrController.text.trim(), mono: true),
                  const SizedBox(height: 7),
                  _frontField(on, 'Kennnummer', _ehicInstitutionskennzeichenController.text.trim(), mono: true),
                  const SizedBox(height: 7),
                  _frontField(on, 'Kartennummer', _kartennummerController.text.trim(), valueSize: 11, mono: true),
                  const Spacer(),
                  Align(alignment: Alignment.centerRight, child: Column(crossAxisAlignment: CrossAxisAlignment.end, mainAxisSize: MainAxisSize.min, children: [
                    Text('gültig bis', style: TextStyle(color: on.withValues(alpha: 0.7), fontSize: 9, fontWeight: FontWeight.w600)),
                    Text(_mmYY(_egkGueltigBisController.text.trim()).isEmpty ? 'MM/JJ' : _mmYY(_egkGueltigBisController.text.trim()), style: TextStyle(color: on, fontSize: 17, fontWeight: FontWeight.w700, letterSpacing: 1)),
                  ])),
                ])),
              ])),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildEhicBackCard(_EgkTheme t) {
    final nach = (widget.user.nachname ?? '').trim().isNotEmpty ? (widget.user.nachname ?? '').trim() : widget.user.name;
    final vor = _holderVornameFull();
    final geb = _fmtDate(widget.user.geburtsdatum);
    final persKenn = _ehicKennummerController.text.trim().isNotEmpty ? _ehicKennummerController.text.trim() : _kvnrController.text.trim();
    final ik = _ehicInstitutionskennzeichenController.text.trim();
    final kasse = _krankenkasseNameController.text.trim();
    final ikLine = [ik, kasse].where((s) => s.isNotEmpty).join('  ');
    final kartennr = _kartennummerController.text.trim();
    final ablauf = _fmtDate(_egkGueltigBisController.text.trim());
    const eu = Color(0xFFFFCC00);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF0A3DA6), Color(0xFF00206B)]),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.22), blurRadius: 10, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(children: [
          Positioned(left: 0, right: 0, top: 16, child: Container(height: 30, color: Colors.black.withValues(alpha: 0.55))),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 56, 18, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.public, size: 16, color: eu),
                const SizedBox(width: 6),
                const Expanded(child: Text('Europäische Krankenversicherungskarte', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700))),
              ]),
              Padding(padding: const EdgeInsets.only(left: 22, top: 1), child: Text('European Health Insurance Card', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 8.5, fontStyle: FontStyle.italic))),
              const SizedBox(height: 8),
              Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(width: 100, child: Center(child: SizedBox(width: 94, height: 94, child: CustomPaint(painter: const _EuStarsPainter())))),
                const SizedBox(width: 12),
                Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: _ehicField('3  Name', nach)),
                    Expanded(child: _ehicField('4  Vornamen', vor)),
                  ]),
                  Row(children: [
                    Expanded(child: _ehicField('5  Geburtsdatum', geb)),
                    Expanded(child: _ehicField('9  Ablaufdatum', ablauf)),
                  ]),
                  _ehicField('6  Persönliche Kennnummer', persKenn),
                  _ehicField('7  Kennnummer der Institution', ikLine),
                  _ehicField('8  Kennnummer der Karte', kartennr),
                ])),
              ])),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _buildVersicherungskarteTab(Map<String, dynamic> data) {
    return StatefulBuilder(builder: (context, setCard) {
      final t = _egkThemeFor(_krankenkasseNameController.text);
      final kasseLeer = _krankenkasseNameController.text.trim().isEmpty;

      InputDecoration deco(String hint, IconData icon, {Widget? suffix}) => InputDecoration(
            hintText: hint,
            prefixIcon: Icon(icon, size: 18),
            suffixIcon: suffix,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          );

      Widget label(String s) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(s, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
          );

      Widget dateField(TextEditingController c, String hint, IconData icon, DateTime initial) => TextField(
            controller: c,
            readOnly: true,
            style: const TextStyle(fontSize: 13),
            decoration: deco(hint, icon),
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: DateTime(2000),
                lastDate: DateTime(2040),
                locale: const Locale('de', 'DE'),
              );
              if (picked != null) {
                setCard(() {
                  c.text = '${picked.day.toString().padLeft(2, '0')}.${picked.month.toString().padLeft(2, '0')}.${picked.year}';
                });
              }
            },
          );

      return SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(Icons.credit_card, 'Versicherungskarte', t.primary),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: kasseLeer ? Colors.orange.shade50 : Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kasseLeer ? Colors.orange.shade200 : Colors.blue.shade200),
              ),
              child: Row(children: [
                Icon(kasseLeer ? Icons.info_outline : Icons.palette_outlined, size: 16, color: kasseLeer ? Colors.orange.shade700 : Colors.blue.shade700),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  kasseLeer
                      ? 'Bitte zuerst im Tab „Krankenkasse" die Kasse auswählen — die Karte wird dann im passenden Kassendesign angezeigt.'
                      : 'Vorschau im Design der Krankenkasse. Nachbildung ohne Original-Logo, dient der Anschauung / Datenerfassung.',
                  style: TextStyle(fontSize: 11.5, color: kasseLeer ? Colors.orange.shade900 : Colors.blue.shade900),
                )),
              ]),
            ),
            const SizedBox(height: 16),
            _cardCaption(Icons.badge_outlined, 'Vorderseite — Elektronische Gesundheitskarte (eGK)'),
            const SizedBox(height: 8),
            _cardScaler(_buildEgkFrontCard(t)),
            const SizedBox(height: 20),
            _cardCaption(Icons.public, 'Rückseite — Europäische Krankenversicherungskarte (EHIC)'),
            const SizedBox(height: 8),
            _cardScaler(_buildEhicBackCard(t)),
            const SizedBox(height: 22),
            const Divider(),
            const SizedBox(height: 4),
            _sectionHeader(Icons.edit_note, 'Kartendaten bearbeiten', Colors.blueGrey),
            const SizedBox(height: 8),
            label('Krankenversichertennummer (KVNR)'),
            TextField(
              controller: _kvnrController,
              onChanged: (_) => setCard(() {}),
              style: const TextStyle(fontSize: 14),
              decoration: deco('z.B. A123456789 (1 Buchstabe + 9 Ziffern)', Icons.badge, suffix: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'KVNR kopieren',
                onPressed: () => _copyValue(_kvnrController.text, 'KVNR'),
              )),
            ),
            const SizedBox(height: 4),
            Text('Lebenslang gültig — bleibt auch bei Kassenwechsel gleich.', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Kartennummer'),
                TextField(controller: _kartennummerController, onChanged: (_) => setCard(() {}), style: const TextStyle(fontSize: 14), decoration: deco('Auf der Vorderseite', Icons.numbers)),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Kartenfolge-Nr.'),
                TextField(controller: _kartenfolgenummerController, onChanged: (_) => setCard(() {}), keyboardType: TextInputType.number, style: const TextStyle(fontSize: 14), decoration: deco('z.B. 01', Icons.tag)),
              ])),
            ]),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Gültig ab'),
                dateField(_egkGueltigAbController, 'Datum...', Icons.calendar_today, DateTime.now()),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                label('Gültig bis'),
                dateField(_egkGueltigBisController, 'Datum...', Icons.event_busy, DateTime.now().add(const Duration(days: 365 * 5))),
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Icon(Icons.language, size: 18, color: Colors.indigo.shade700),
                  const SizedBox(width: 6),
                  Expanded(child: Text('EHIC — Europäische Krankenversicherungskarte (Rückseite)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700))),
                ]),
                const SizedBox(height: 4),
                Text('Gültig in allen EU-/EWR-Ländern + Schweiz', style: TextStyle(fontSize: 10, color: Colors.indigo.shade400, fontStyle: FontStyle.italic)),
                const SizedBox(height: 10),
                label('Persönliche Kennnummer (Feld 6)'),
                TextField(controller: _ehicKennummerController, onChanged: (_) => setCard(() {}), style: const TextStyle(fontSize: 13), decoration: deco('Kennnummer auf der EHIC-Rückseite', Icons.person_pin)),
                const SizedBox(height: 10),
                label('Kennnummer der Institution / IK (Feld 7)'),
                TextField(controller: _ehicInstitutionskennzeichenController, onChanged: (_) => setCard(() {}), style: const TextStyle(fontSize: 13), decoration: deco('Institutionskennzeichen der Krankenkasse', Icons.business)),
              ]),
            ),
            const SizedBox(height: 16),
            Builder(builder: (context) {
              final fotoDatum = _parseDeDate(_egkFotoDatumController.text);
              final faellig = fotoDatum == null ? null : DateTime(fotoDatum.year + 10, fotoDatum.month, fotoDatum.day);
              final now = DateTime.now();
              Color statusColor;
              IconData statusIcon;
              String statusText;
              if (faellig == null) {
                statusColor = Colors.grey.shade600;
                statusIcon = Icons.help_outline;
                statusText = 'Kein Einreichungsdatum erfasst';
              } else if (now.isAfter(faellig)) {
                statusColor = Colors.red.shade700;
                statusIcon = Icons.error_outline;
                statusText = 'Überfällig — seit ${_fmtD(faellig)} fällig';
              } else if (faellig.difference(now).inDays <= 365) {
                statusColor = Colors.orange.shade800;
                statusIcon = Icons.hourglass_bottom;
                statusText = 'Bald fällig am ${_fmtD(faellig)}';
              } else {
                statusColor = Colors.green.shade700;
                statusIcon = Icons.check_circle_outline;
                statusText = 'Aktuell — nächste Aktualisierung am ${_fmtD(faellig)}';
              }
              final teal = Colors.teal.shade700;
              final schreiben = _egkFotoSchreibenErhalten;
              Widget divider() => Divider(height: 18, color: Colors.teal.shade100);
              return Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.photo_camera, size: 18, color: teal),
                    const SizedBox(width: 6),
                    Expanded(child: Text('Lichtbild (Foto) — Aktualisierung', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: teal))),
                  ]),
                  const SizedBox(height: 4),
                  Text('Gesetzlich muss das Lichtbild alle 10 Jahre bei der Krankenkasse aktualisiert werden (Pflicht ab dem 15. Lebensjahr). Die Kasse löscht das alte Foto nach spätestens 10 Jahren.', style: TextStyle(fontSize: 10.5, color: Colors.teal.shade900)),
                  divider(),

                  // ── Schritt 1: Schreiben der Krankenkasse ──
                  _stepHeader('1', 'Schreiben der Krankenkasse erhalten?', teal),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      label: const Text('Ja', style: TextStyle(fontSize: 12)),
                      selected: schreiben == 'ja',
                      selectedColor: Colors.teal.shade200,
                      onSelected: (_) => setCard(() => _egkFotoSchreibenErhalten = schreiben == 'ja' ? '' : 'ja'),
                    ),
                    ChoiceChip(
                      label: const Text('Nein', style: TextStyle(fontSize: 12)),
                      selected: schreiben == 'nein',
                      selectedColor: Colors.teal.shade200,
                      onSelected: (_) => setCard(() => _egkFotoSchreibenErhalten = schreiben == 'nein' ? '' : 'nein'),
                    ),
                  ]),
                  if (schreiben == 'ja') ...[
                    const SizedBox(height: 8),
                    Text('Aufforderung anhängen und zur Bearbeitung einreichen:', style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                    const SizedBox(height: 6),
                    OutlinedButton.icon(
                      icon: _fotoSchreibenUploading
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : Icon(Icons.attach_file, size: 16, color: teal),
                      label: Text(_fotoSchreibenUploading ? 'Wird hochgeladen…' : 'Schreiben anhängen (max. 20)', style: const TextStyle(fontSize: 12)),
                      style: OutlinedButton.styleFrom(foregroundColor: teal, side: BorderSide(color: Colors.teal.shade300), minimumSize: const Size(double.infinity, 38)),
                      onPressed: _fotoSchreibenUploading ? null : _uploadFotoSchreiben,
                    ),
                    Builder(builder: (_) {
                      if (!_kkKorrLoaded) _loadKKKorrespondenz();
                      final docs = _lichtbildAufforderungDocs();
                      if (docs.isEmpty) return const SizedBox(height: 6);
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Angehängte Schreiben (${docs.length}):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                          const SizedBox(height: 2),
                          ...docs.map((d) {
                            final id = d['id'];
                            final did = id is int ? id : int.tryParse('$id');
                            final name = d['name']?.toString() ?? 'Dokument';
                            return Padding(
                              padding: const EdgeInsets.only(top: 3),
                              child: Row(children: [
                                Icon(Icons.description, size: 14, color: teal),
                                const SizedBox(width: 5),
                                Expanded(child: Text(name, style: TextStyle(fontSize: 11, color: Colors.grey.shade800), overflow: TextOverflow.ellipsis)),
                                if (did != null)
                                  InkWell(
                                    onTap: () => _openKKKorrDoc(did, name),
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.visibility, size: 16, color: teal)),
                                  ),
                              ]),
                            );
                          }),
                        ]),
                      );
                    }),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.assignment_turned_in, size: 16),
                      label: const Text('Zur Bearbeitung einreichen', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade600, foregroundColor: Colors.white, minimumSize: const Size(double.infinity, 38)),
                      onPressed: _createFotoBearbeitenTicket,
                    ),
                  ],
                  divider(),

                  // ── Schritt 2: Foto eingereicht ──
                  _stepHeader('2', 'Foto eingereicht', teal),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.blue.shade100)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                        const SizedBox(width: 4),
                        Text('Foto-Anforderungen (Passbild)', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade800)),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                        '• 35 × 45 mm, biometrisch, frontal, neutraler Hintergrund\n'
                        '• Digital: JPG/PNG, mind. ~413 × 531 px (300 dpi)\n'
                        '• Dateigröße je nach Kasse max. 5–10 MB\n'
                        '• Genaue Vorgaben im Upload-Tool der Krankenkasse prüfen',
                        style: TextStyle(fontSize: 10, color: Colors.blue.shade900, height: 1.35),
                      ),
                    ]),
                  ),
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    icon: Icon(Icons.add_a_photo, size: 16, color: teal),
                    label: const Text('Lichtbild hochladen (JPG/PNG)', style: TextStyle(fontSize: 12)),
                    style: OutlinedButton.styleFrom(foregroundColor: teal, side: BorderSide(color: Colors.teal.shade300), minimumSize: const Size(double.infinity, 38)),
                    onPressed: _uploadLichtbildFoto,
                  ),
                  const SizedBox(height: 10),
                  label('Foto eingereicht am'),
                  dateField(_egkFotoDatumController, 'Datum der Einreichung…', Icons.event_available, DateTime.now()),
                  const SizedBox(height: 8),
                  Text('Einreichungsweg', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade700)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 8, children: [
                    ChoiceChip(
                      avatar: Icon(Icons.local_post_office, size: 15, color: _egkFotoUploadWeg == 'post' ? Colors.white : Colors.grey.shade600),
                      label: const Text('Per Post', style: TextStyle(fontSize: 12)),
                      selected: _egkFotoUploadWeg == 'post',
                      selectedColor: teal,
                      labelStyle: TextStyle(color: _egkFotoUploadWeg == 'post' ? Colors.white : Colors.black87),
                      onSelected: (_) => setCard(() => _egkFotoUploadWeg = _egkFotoUploadWeg == 'post' ? '' : 'post'),
                    ),
                    ChoiceChip(
                      avatar: Icon(Icons.cloud_upload, size: 15, color: _egkFotoUploadWeg == 'online' ? Colors.white : Colors.grey.shade600),
                      label: const Text('Online (Tool/App)', style: TextStyle(fontSize: 12)),
                      selected: _egkFotoUploadWeg == 'online',
                      selectedColor: teal,
                      labelStyle: TextStyle(color: _egkFotoUploadWeg == 'online' ? Colors.white : Colors.black87),
                      onSelected: (_) => setCard(() => _egkFotoUploadWeg = _egkFotoUploadWeg == 'online' ? '' : 'online'),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: statusColor.withValues(alpha: 0.40)),
                    ),
                    child: Row(children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 6),
                      Expanded(child: Text(statusText, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: statusColor))),
                    ]),
                  ),
                  divider(),

                  // ── Schritt 3: Erinnerung in 10 Jahren ──
                  _stepHeader('3', 'Erinnerung (alle 10 Jahre)', teal),
                  Text('Legt ein Ticket an, das das Mitglied in 10 Jahren an ein neues Foto erinnert. Prüft auf bereits vorhandene Tickets (keine Duplikate).', style: TextStyle(fontSize: 10.5, color: Colors.grey.shade700)),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _createFotoErinnerung(faellig),
                      icon: const Icon(Icons.assignment_add, size: 16),
                      label: Text('Erinnerung erstellen (Ticket ${(faellig ?? DateTime(now.year + 10, now.month, now.day)).year})', style: const TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                      ),
                    ),
                  ),
                ]),
              );
            }),
          ],
        ),
      );
    });
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
                          final messenger = ScaffoldMessenger.of(context);
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

                          if (result.containsKey('ticket')) {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Erinnerungsticket für Befreiungsausweis $nextYear erstellt (geplant: ${firstMonday.day.toString().padLeft(2, '0')}.${firstMonday.month.toString().padLeft(2, '0')}.${firstMonday.year})'),
                                backgroundColor: Colors.green,
                              ),
                            );
                          } else {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(result['error'] ?? 'Fehler beim Erstellen des Tickets'),
                                backgroundColor: Colors.red,
                              ),
                            );
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
  void _showPflegedienstSuche() {
    final searchC = TextEditingController();
    List<Map<String, dynamic>> results = [];
    bool loading = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx2, setDlg) {
      Future<void> doSearch() async {
        setDlg(() => loading = true);
        try {
          final res = await widget.apiService.searchPflegedienst(search: searchC.text.trim());
          if (res['success'] == true && res['pflegedienste'] is List) {
            results = List<Map<String, dynamic>>.from((res['pflegedienste'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
          }
        } catch (_) {}
        setDlg(() => loading = false);
      }
      return AlertDialog(
        title: Row(children: [
          Icon(Icons.medical_services, size: 20, color: Colors.purple.shade700),
          const SizedBox(width: 8),
          const Text('Pflegedienst suchen', style: TextStyle(fontSize: 16)),
        ]),
        content: SizedBox(width: 500, height: 400, child: Column(children: [
          TextField(
            controller: searchC,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Name oder Ort eingeben...',
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: doSearch),
            ),
            onSubmitted: (_) => doSearch(),
          ),
          const SizedBox(height: 12),
          Expanded(child: loading
            ? const Center(child: CircularProgressIndicator())
            : results.isEmpty
              ? Center(child: Text(searchC.text.isEmpty ? 'Suchbegriff eingeben' : 'Keine Ergebnisse', style: TextStyle(color: Colors.grey.shade400)))
              : ListView.builder(itemCount: results.length, itemBuilder: (_, i) {
                  final p = results[i];
                  return Card(child: ListTile(
                    onTap: () {
                      setState(() {
                        _selectedPflegedienst = p;
                        _pflegedienstNameController.text = p['name']?.toString() ?? '';
                      });
                      Navigator.pop(ctx);
                    },
                    leading: CircleAvatar(backgroundColor: Colors.purple.shade50, child: Icon(Icons.medical_services, color: Colors.purple.shade700, size: 20)),
                    title: Text(p['name']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      if ((p['strasse']?.toString() ?? '').isNotEmpty || (p['plz_ort']?.toString() ?? '').isNotEmpty)
                        Text('${p['strasse'] ?? ''}, ${p['plz_ort'] ?? ''}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                      if ((p['telefon']?.toString() ?? '').isNotEmpty)
                        Text('Tel: ${p['telefon']}', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                    ]),
                  ));
                })),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen'))],
      );
    }));
  }

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
              'egk_foto_datum': _egkFotoDatumController.text.trim(),
              'egk_foto_schreiben_erhalten': _egkFotoSchreibenErhalten,
              'egk_foto_upload_weg': _egkFotoUploadWeg,
              'befreiungskarte': _befreiungskarte.toString(),
              'befreiung_jahr': _befreiungJahr,
              'befreiung_gueltig_bis': _befreiungGueltigBisController.text.trim(),
              'pflegekasse_name': _pflegekasseNameController.text.trim(),
              'pflegedienst_name': _pflegedienstNameController.text.trim(),
              'selected_pflegedienst': _selectedPflegedienst,
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

// ════════════════ KRANKENGELD ════════════════════════════════════
// Sub-system mirroring the Inkasso layout: list of dossiers per user,
// tap a dossier to open a 4-tab modal (Details / Korrespondenz /
// Auszahlungen / Termine). All fields go through column-level AES-CBC
// encryption server-side.

const _kgStatusLabel = {
  'beantragt': 'Beantragt',
  'laeuft': 'Läuft',
  'ausgesetzt': 'Ausgesetzt',
  'abgelehnt': 'Abgelehnt',
  'beendet': 'Beendet',
  'widerspruch': 'Widerspruch',
};
const _kgStatusColor = {
  'beantragt': Colors.amber,
  'laeuft': Colors.green,
  'ausgesetzt': Colors.orange,
  'abgelehnt': Colors.red,
  'beendet': Colors.grey,
  'widerspruch': Colors.purple,
};

class _KrankengeldTab extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final ValueChanged<int> onCountChanged;
  const _KrankengeldTab({required this.apiService, required this.userId, required this.onCountChanged});
  @override
  State<_KrankengeldTab> createState() => _KrankengeldTabState();
}

class _KrankengeldTabState extends State<_KrankengeldTab> {
  List<Map<String, dynamic>> _dossiers = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listKrankengeldDossier(widget.userId);
    if (!mounted) return;
    setState(() {
      _dossiers = List<Map<String, dynamic>>.from(res['dossiers'] as List? ?? []);
      _loaded = true;
    });
    widget.onCountChanged(_dossiers.length);
  }

  Future<void> _addOrEdit({Map<String, dynamic>? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _KrankengeldDossierEditDialog(
        apiService: widget.apiService, userId: widget.userId, existing: existing,
      ),
    );
    if (saved == true) _load();
  }

  Future<void> _openDossier(Map<String, dynamic> d) async {
    final changed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        child: SizedBox(width: 720, height: 720,
          child: _KrankengeldDossierModal(apiService: widget.apiService, dossier: d)),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Dossier löschen?'),
      content: const Text('Alle Korrespondenz-, Auszahlungs- und Termin-Einträge werden mitgelöscht.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    await widget.apiService.deleteKrankengeldDossier(id);
    _load();
  }

  String _fmtDate(String? s) {
    if (s == null || s.isEmpty) return '–';
    final d = DateTime.tryParse(s);
    return d == null ? s : DateFormat('dd.MM.yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: Colors.teal.shade50,
        child: Row(children: [
          Icon(Icons.medical_information, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
          Expanded(child: Text('Krankengeld-Dossiers (${_dossiers.length})',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
          ElevatedButton.icon(
            onPressed: () => _addOrEdit(),
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Neues Dossier', style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
          ),
        ]),
      ),
      Expanded(child: _dossiers.isEmpty
        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.folder_off, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Noch kein Krankengeld-Dossier', style: TextStyle(color: Colors.grey.shade600)),
            const SizedBox(height: 4),
            Text('Ein Dossier umfasst Zeitraum, Status, Diagnose, Korrespondenz, Auszahlungen und MDK-Termine.',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade500), textAlign: TextAlign.center),
          ]))
        : ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: _dossiers.length,
            itemBuilder: (_, i) {
              final d = _dossiers[i];
              final status = (d['status'] ?? 'beantragt').toString();
              final col = _kgStatusColor[status] ?? Colors.grey;
              final period = '${_fmtDate(d['perioda_von']?.toString())} – ${_fmtDate(d['perioda_bis']?.toString())}';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () => _openDossier(d),
                  child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Icon(Icons.folder, color: col.shade700, size: 18),
                      const SizedBox(width: 8),
                      Expanded(child: Text(period, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold))),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: col.shade600, borderRadius: BorderRadius.circular(8)),
                        child: Text(_kgStatusLabel[status] ?? status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                      IconButton(icon: Icon(Icons.edit_outlined, size: 16, color: Colors.blue.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _addOrEdit(existing: d)),
                      IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _delete(d['id'] as int)),
                    ]),
                    if ((d['diagnose'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Row(children: [
                      Icon(Icons.medical_services, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                      Expanded(child: Text(d['diagnose'].toString(), style: const TextStyle(fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ])),
                    if ((d['arzt_name'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                      Icon(Icons.person, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                      Text(d['arzt_name'].toString(), style: const TextStyle(fontSize: 11)),
                    ])),
                    if ((d['aktenzeichen'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2), child: Row(children: [
                      Icon(Icons.tag, size: 13, color: Colors.grey.shade600), const SizedBox(width: 4),
                      Text('Az: ${d['aktenzeichen']}', style: const TextStyle(fontSize: 11, fontFamily: 'monospace')),
                    ])),
                    Padding(padding: const EdgeInsets.only(top: 4), child: Text('Tippen zum Öffnen →', style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400, fontStyle: FontStyle.italic))),
                  ])),
                ),
              );
            },
          )),
    ]);
  }
}

// ─── Dossier edit dialog (only Stammdaten — sub-content via modal) ───

class _KrankengeldDossierEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final Map<String, dynamic>? existing;
  const _KrankengeldDossierEditDialog({required this.apiService, required this.userId, this.existing});
  @override
  State<_KrankengeldDossierEditDialog> createState() => _KrankengeldDossierEditDialogState();
}

class _KrankengeldDossierEditDialogState extends State<_KrankengeldDossierEditDialog> {
  late TextEditingController _vonC, _bisC, _diagnoseC, _arztC, _aktenC, _bruttoC, _nettoC, _sbC, _sbTelC, _sbEmailC, _notizC;
  String _status = 'beantragt';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? <String, dynamic>{};
    _vonC      = TextEditingController(text: e['perioda_von']?.toString() ?? '');
    _bisC      = TextEditingController(text: e['perioda_bis']?.toString() ?? '');
    _diagnoseC = TextEditingController(text: e['diagnose']?.toString() ?? '');
    _arztC     = TextEditingController(text: e['arzt_name']?.toString() ?? '');
    _aktenC    = TextEditingController(text: e['aktenzeichen']?.toString() ?? '');
    _bruttoC   = TextEditingController(text: e['taegliches_brutto']?.toString() ?? '');
    _nettoC    = TextEditingController(text: e['taegliches_netto']?.toString() ?? '');
    _sbC       = TextEditingController(text: e['sachbearbeiter']?.toString() ?? '');
    _sbTelC    = TextEditingController(text: e['sachbearbeiter_tel']?.toString() ?? '');
    _sbEmailC  = TextEditingController(text: e['sachbearbeiter_email']?.toString() ?? '');
    _notizC    = TextEditingController(text: e['notiz']?.toString() ?? '');
    _status    = e['status']?.toString() ?? 'beantragt';
  }

  @override
  void dispose() {
    for (final c in [_vonC, _bisC, _diagnoseC, _arztC, _aktenC, _bruttoC, _nettoC, _sbC, _sbTelC, _sbEmailC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pick(TextEditingController c) async {
    final init = DateTime.tryParse(c.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2010), lastDate: DateTime(2050), locale: const Locale('de'));
    if (p != null) setState(() => c.text = DateFormat('yyyy-MM-dd').format(p));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final dossier = {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'perioda_von': _vonC.text.trim().isEmpty ? null : _vonC.text.trim(),
      'perioda_bis': _bisC.text.trim().isEmpty ? null : _bisC.text.trim(),
      'status': _status,
      'diagnose': _diagnoseC.text.trim(),
      'arzt_name': _arztC.text.trim(),
      'aktenzeichen': _aktenC.text.trim(),
      'taegliches_brutto': _bruttoC.text.trim(),
      'taegliches_netto': _nettoC.text.trim(),
      'sachbearbeiter': _sbC.text.trim(),
      'sachbearbeiter_tel': _sbTelC.text.trim(),
      'sachbearbeiter_email': _sbEmailC.text.trim(),
      'notiz': _notizC.text.trim(),
    };
    final res = await widget.apiService.saveKrankengeldDossier(widget.userId, dossier);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Neues Krankengeld-Dossier' : 'Dossier bearbeiten'),
    content: SizedBox(width: 520, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _vonC, readOnly: true, onTap: () => _pick(_vonC),
          decoration: const InputDecoration(labelText: 'Zeitraum von', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _bisC, readOnly: true, onTap: () => _pick(_bisC),
          decoration: const InputDecoration(labelText: 'Zeitraum bis', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(
        initialValue: _status,
        decoration: const InputDecoration(labelText: 'Status', isDense: true, border: OutlineInputBorder()),
        items: _kgStatusLabel.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
        onChanged: (v) => setState(() => _status = v ?? 'beantragt'),
      ),
      const SizedBox(height: 10),
      TextField(controller: _diagnoseC, decoration: const InputDecoration(labelText: 'Diagnose', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _arztC, decoration: const InputDecoration(labelText: 'Arzt', isDense: true, border: OutlineInputBorder()))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _aktenC, decoration: const InputDecoration(labelText: 'Aktenzeichen', isDense: true, border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _bruttoC, decoration: const InputDecoration(labelText: 'Tgl. brutto €', isDense: true, border: OutlineInputBorder()))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _nettoC, decoration: const InputDecoration(labelText: 'Tgl. netto €', isDense: true, border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _sbC, decoration: const InputDecoration(labelText: 'Sachbearbeiter', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _sbTelC, decoration: const InputDecoration(labelText: 'Telefon', isDense: true, border: OutlineInputBorder()))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _sbEmailC, decoration: const InputDecoration(labelText: 'E-Mail', isDense: true, border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      TextField(controller: _notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
      ElevatedButton.icon(
        onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
      ),
    ],
  );
}

// ─── 4-tab modal: Details / Korrespondenz / Auszahlungen / Termine ──

class _KrankengeldDossierModal extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> dossier;
  const _KrankengeldDossierModal({required this.apiService, required this.dossier});
  @override
  State<_KrankengeldDossierModal> createState() => _KrankengeldDossierModalState();
}

class _KrankengeldDossierModalState extends State<_KrankengeldDossierModal> with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _dataChanged = false;

  @override
  void initState() { super.initState(); _tab = TabController(length: 4, vsync: this); }
  @override
  void dispose() { _tab.dispose(); super.dispose(); }

  void _mark() { if (!_dataChanged) _dataChanged = true; }

  String _fmt(String? s) {
    if (s == null || s.isEmpty) return '–';
    final d = DateTime.tryParse(s);
    return d == null ? s : DateFormat('dd.MM.yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dossier;
    final status = (d['status'] ?? 'beantragt').toString();
    final col = _kgStatusColor[status] ?? Colors.grey;
    final period = '${_fmt(d['perioda_von']?.toString())} – ${_fmt(d['perioda_bis']?.toString())}';
    return Column(children: [
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
        child: Row(children: [
          const Icon(Icons.medical_information, color: Colors.white), const SizedBox(width: 8),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Krankengeld-Dossier · $period', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            if ((d['diagnose'] ?? '').toString().isNotEmpty) Text(d['diagnose'].toString(), style: TextStyle(color: Colors.teal.shade100, fontSize: 11)),
          ])),
          Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(color: col.shade600, borderRadius: BorderRadius.circular(8)),
            child: Text(_kgStatusLabel[status] ?? status, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
          IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context, _dataChanged)),
        ]),
      ),
      Container(color: Colors.teal.shade50, child: TabBar(
        controller: _tab,
        labelColor: Colors.teal.shade800, unselectedLabelColor: Colors.grey.shade600,
        indicatorColor: Colors.teal.shade700,
        tabs: const [
          Tab(icon: Icon(Icons.info_outline, size: 18), text: 'Details'),
          Tab(icon: Icon(Icons.mail, size: 18), text: 'Korrespondenz'),
          Tab(icon: Icon(Icons.payments, size: 18), text: 'Auszahlungen'),
          Tab(icon: Icon(Icons.event, size: 18), text: 'Termine'),
        ],
      )),
      Expanded(child: TabBarView(controller: _tab, children: [
        _KgDetailsTab(dossier: d),
        _KgKorrTab(apiService: widget.apiService, dossierId: d['id'] as int, onChanged: _mark),
        _KgAuszahlungenTab(apiService: widget.apiService, dossierId: d['id'] as int, onChanged: _mark),
        _KgTermineTab(apiService: widget.apiService, dossierId: d['id'] as int, onChanged: _mark),
      ])),
    ]);
  }
}

class _KgDetailsTab extends StatelessWidget {
  final Map<String, dynamic> dossier;
  const _KgDetailsTab({required this.dossier});

  Widget _kv(IconData icon, String label, String? value, {bool multiline = false}) {
    if (value == null || value.isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 5), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 140, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        maxLines: multiline ? null : 3,
        overflow: multiline ? null : TextOverflow.ellipsis,
      )),
    ]));
  }

  String _fmt(String? s) {
    if (s == null || s.isEmpty) return '';
    final d = DateTime.tryParse(s);
    return d == null ? s : DateFormat('dd.MM.yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    final d = dossier;
    return SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _kv(Icons.event, 'Von',  _fmt(d['perioda_von']?.toString())),
      _kv(Icons.event, 'Bis',  _fmt(d['perioda_bis']?.toString())),
      _kv(Icons.flag, 'Status', _kgStatusLabel[(d['status'] ?? '').toString()]),
      _kv(Icons.medical_services, 'Diagnose', d['diagnose']?.toString(), multiline: true),
      _kv(Icons.person, 'Arzt', d['arzt_name']?.toString()),
      _kv(Icons.tag, 'Aktenzeichen', d['aktenzeichen']?.toString()),
      _kv(Icons.euro, 'Tgl. brutto', d['taegliches_brutto']?.toString()),
      _kv(Icons.euro, 'Tgl. netto',  d['taegliches_netto']?.toString()),
      const SizedBox(height: 10),
      Divider(color: Colors.teal.shade100),
      const SizedBox(height: 10),
      _kv(Icons.support_agent, 'Sachbearbeiter', d['sachbearbeiter']?.toString()),
      _kv(Icons.phone, 'Telefon', d['sachbearbeiter_tel']?.toString()),
      _kv(Icons.email, 'E-Mail',  d['sachbearbeiter_email']?.toString()),
      _kv(Icons.sticky_note_2, 'Notiz', d['notiz']?.toString(), multiline: true),
    ]));
  }
}

class _KgKorrTab extends StatefulWidget {
  final ApiService apiService;
  final int dossierId;
  final VoidCallback onChanged;
  const _KgKorrTab({required this.apiService, required this.dossierId, required this.onChanged});
  @override
  State<_KgKorrTab> createState() => _KgKorrTabState();
}

class _KgKorrTabState extends State<_KgKorrTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listKrankengeldKorr(widget.dossierId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _openEdit({Map<String, dynamic>? existing}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _KgKorrEditDialog(
      apiService: widget.apiService, dossierId: widget.dossierId, existing: existing));
    if (ok == true) { widget.onChanged(); _load(); }
  }

  // Read-only view: shows content + attached files. Tap-anywhere replaces
  // the pencil-icon foot-gun (consistent with Inkasso-Korr).
  Future<void> _openView(Map<String, dynamic> k) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _KgKorrViewDialog(apiService: widget.apiService, korr: k),
    );
    if (result == 'edit') {
      await _openEdit(existing: k);
    } else if (result == 'delete') {
      await _delete(k['id'] as int);
    } else if (result == 'docs_changed') {
      widget.onChanged();
      _load();
    }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Eintrag löschen?'),
      content: const Text('Der Eintrag und alle Anhänge werden unwiderruflich entfernt.'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red)))],
    ));
    if (ok != true) return;
    await widget.apiService.deleteKrankengeldKorr(id);
    widget.onChanged(); _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(children: [
        Icon(Icons.mail_outline, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
        Expanded(child: Text('${_items.length} Eintrag/Einträge', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neu'), onPressed: () => _openEdit(),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
      ])),
      const Divider(height: 1),
      Expanded(child: _items.isEmpty
        ? Center(child: Text('Keine Korrespondenz', style: TextStyle(color: Colors.grey.shade600)))
        : ListView.builder(padding: const EdgeInsets.all(8), itemCount: _items.length, itemBuilder: (_, i) {
            final k = _items[i];
            final eingang = k['richtung'] == 'eingang';
            return Card(child: ListTile(
              onTap: () => _openView(k),
              leading: CircleAvatar(backgroundColor: (eingang ? Colors.blue : Colors.green).shade50,
                child: Icon(eingang ? Icons.south_west : Icons.north_east, size: 18, color: eingang ? Colors.blue : Colors.green)),
              title: Text(k['betreff']?.toString().isNotEmpty == true ? k['betreff'].toString() : '(ohne Betreff)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(k['datum']?.toString() ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(width: 8),
                  Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(color: (eingang ? Colors.blue : Colors.green).shade50, borderRadius: BorderRadius.circular(4)),
                    child: Text(eingang ? 'eingang' : 'ausgang', style: TextStyle(fontSize: 10, color: eingang ? Colors.blue : Colors.green))),
                  if (k['medium'] != null) ...[const SizedBox(width: 4), Text(k['medium'].toString(), style: const TextStyle(fontSize: 10, color: Colors.grey))],
                  if (k['erledigt'] == 1 || k['erledigt'] == true) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1), decoration: BoxDecoration(color: Colors.green.shade100, borderRadius: BorderRadius.circular(4)), child: Text('Erledigt', style: TextStyle(fontSize: 9, color: Colors.green.shade900)))],
                ]),
                if ((k['text'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                  child: Text(k['text'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))),
              ]),
              trailing: const Icon(Icons.chevron_right, color: Colors.grey),
            ));
          })),
    ]);
  }
}

class _KgKorrEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int dossierId;
  final Map<String, dynamic>? existing;
  const _KgKorrEditDialog({required this.apiService, required this.dossierId, this.existing});
  @override
  State<_KgKorrEditDialog> createState() => _KgKorrEditDialogState();
}

class _KgKorrEditDialogState extends State<_KgKorrEditDialog> {
  late TextEditingController _datumC, _betreffC, _textC, _notizC;
  String _richtung = 'eingang', _medium = 'post';
  bool _erledigt = false, _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? <String, dynamic>{};
    _datumC = TextEditingController(text: e['datum']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _betreffC = TextEditingController(text: e['betreff']?.toString() ?? '');
    _textC = TextEditingController(text: e['text']?.toString() ?? '');
    _notizC = TextEditingController(text: e['notiz']?.toString() ?? '');
    _richtung = e['richtung']?.toString() ?? 'eingang';
    _medium = e['medium']?.toString() ?? 'post';
    _erledigt = e['erledigt'] == 1 || e['erledigt'] == true;
  }

  @override
  void dispose() {
    for (final c in [_datumC, _betreffC, _textC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final init = DateTime.tryParse(_datumC.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2010), lastDate: DateTime(2050), locale: const Locale('de'));
    if (p != null) setState(() => _datumC.text = DateFormat('yyyy-MM-dd').format(p));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final korr = {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'datum': _datumC.text.trim(),
      'richtung': _richtung, 'medium': _medium,
      'betreff': _betreffC.text.trim(), 'text': _textC.text.trim(), 'notiz': _notizC.text.trim(),
      'erledigt': _erledigt,
    };
    final res = await widget.apiService.saveKrankengeldKorr(widget.dossierId, korr);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) Navigator.pop(context, true);
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Neue Korrespondenz' : 'Korrespondenz bearbeiten'),
    content: SizedBox(width: 480, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _datumC, readOnly: true, onTap: _pickDate,
          decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
        const SizedBox(width: 8),
        Expanded(child: DropdownButtonFormField<String>(initialValue: _richtung,
          decoration: const InputDecoration(labelText: 'Richtung', isDense: true, border: OutlineInputBorder()),
          items: const [DropdownMenuItem(value: 'eingang', child: Text('Eingang')), DropdownMenuItem(value: 'ausgang', child: Text('Ausgang'))],
          onChanged: (v) => setState(() => _richtung = v ?? 'eingang'))),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(initialValue: _medium,
        decoration: const InputDecoration(labelText: 'Medium', isDense: true, border: OutlineInputBorder()),
        items: const ['post', 'email', 'fax', 'telefon', 'persoenlich', 'online'].map((m) => DropdownMenuItem(value: m, child: Text(m))).toList(),
        onChanged: (v) => setState(() => _medium = v ?? 'post')),
      const SizedBox(height: 10),
      TextField(controller: _betreffC, decoration: const InputDecoration(labelText: 'Betreff', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _textC, maxLines: 5, decoration: const InputDecoration(labelText: 'Text / Inhalt', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
      CheckboxListTile(value: _erledigt, onChanged: (v) => setState(() => _erledigt = v ?? false),
        title: const Text('Erledigt'), controlAffinity: ListTileControlAffinity.leading, contentPadding: EdgeInsets.zero),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
      ElevatedButton.icon(onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
    ],
  );
}

class _KgAuszahlungenTab extends StatefulWidget {
  final ApiService apiService;
  final int dossierId;
  final VoidCallback onChanged;
  const _KgAuszahlungenTab({required this.apiService, required this.dossierId, required this.onChanged});
  @override
  State<_KgAuszahlungenTab> createState() => _KgAuszahlungenTabState();
}

class _KgAuszahlungenTabState extends State<_KgAuszahlungenTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listKrankengeldAuszahlungen(widget.dossierId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _openEdit({Map<String, dynamic>? existing}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _KgAuszahlungEditDialog(
      apiService: widget.apiService, dossierId: widget.dossierId, existing: existing));
    if (ok == true) { widget.onChanged(); _load(); }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Auszahlung löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red)))],
    ));
    if (ok != true) return;
    await widget.apiService.deleteKrankengeldAuszahlung(id);
    widget.onChanged(); _load();
  }

  String _fmt(String? s) {
    if (s == null || s.isEmpty) return '–';
    final d = DateTime.tryParse(s);
    return d == null ? s : DateFormat('dd.MM.yyyy').format(d);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    double total = 0;
    for (final a in _items) {
      total += double.tryParse((a['betrag'] ?? '').toString().replaceAll(',', '.')) ?? 0;
    }
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(children: [
        Icon(Icons.payments, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
        Expanded(child: Text('${_items.length} Zahlung(en) · Σ ${total.toStringAsFixed(2)} €',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neu'), onPressed: () => _openEdit(),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
      ])),
      const Divider(height: 1),
      Expanded(child: _items.isEmpty
        ? Center(child: Text('Noch keine Auszahlungen', style: TextStyle(color: Colors.grey.shade600)))
        : ListView.builder(padding: const EdgeInsets.all(8), itemCount: _items.length, itemBuilder: (_, i) {
            final a = _items[i];
            final betrag = (a['betrag'] ?? '').toString();
            return Card(child: ListTile(
              onTap: () => _openEdit(existing: a),
              leading: CircleAvatar(backgroundColor: Colors.green.shade50, child: Icon(Icons.euro, color: Colors.green.shade700, size: 18)),
              title: Text(betrag.isEmpty ? '–' : '$betrag €', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${_fmt(a['zeitraum_von']?.toString())} – ${_fmt(a['zeitraum_bis']?.toString())}', style: const TextStyle(fontSize: 11)),
                if ((a['zahlung_datum'] ?? '').toString().isNotEmpty) Text('Gezahlt am ${a['zahlung_datum']}', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
                if ((a['ueberweisungsart'] ?? '').toString().isNotEmpty) Text((a['ueberweisungsart']).toString(), style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ]),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(a['id'] as int)),
            ));
          })),
    ]);
  }
}

class _KgAuszahlungEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int dossierId;
  final Map<String, dynamic>? existing;
  const _KgAuszahlungEditDialog({required this.apiService, required this.dossierId, this.existing});
  @override
  State<_KgAuszahlungEditDialog> createState() => _KgAuszahlungEditDialogState();
}

class _KgAuszahlungEditDialogState extends State<_KgAuszahlungEditDialog> {
  late TextEditingController _zahlungDatumC, _vonC, _bisC, _betragC, _notizC;
  String _art = 'ueberweisung';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? <String, dynamic>{};
    _zahlungDatumC = TextEditingController(text: e['zahlung_datum']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _vonC    = TextEditingController(text: e['zeitraum_von']?.toString() ?? '');
    _bisC    = TextEditingController(text: e['zeitraum_bis']?.toString() ?? '');
    _betragC = TextEditingController(text: e['betrag']?.toString() ?? '');
    _notizC  = TextEditingController(text: e['notiz']?.toString() ?? '');
    _art     = e['ueberweisungsart']?.toString() ?? 'ueberweisung';
  }

  @override
  void dispose() {
    for (final c in [_zahlungDatumC, _vonC, _bisC, _betragC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pick(TextEditingController c) async {
    final init = DateTime.tryParse(c.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2010), lastDate: DateTime(2050), locale: const Locale('de'));
    if (p != null) setState(() => c.text = DateFormat('yyyy-MM-dd').format(p));
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'zahlung_datum': _zahlungDatumC.text.trim(),
      'zeitraum_von': _vonC.text.trim().isEmpty ? null : _vonC.text.trim(),
      'zeitraum_bis': _bisC.text.trim().isEmpty ? null : _bisC.text.trim(),
      'betrag': _betragC.text.trim(),
      'ueberweisungsart': _art,
      'notiz': _notizC.text.trim(),
    };
    final res = await widget.apiService.saveKrankengeldAuszahlung(widget.dossierId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) Navigator.pop(context, true);
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Neue Auszahlung' : 'Auszahlung bearbeiten'),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _vonC, readOnly: true, onTap: () => _pick(_vonC),
          decoration: const InputDecoration(labelText: 'Zeitraum von', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _bisC, readOnly: true, onTap: () => _pick(_bisC),
          decoration: const InputDecoration(labelText: 'Zeitraum bis', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: TextField(controller: _zahlungDatumC, readOnly: true, onTap: () => _pick(_zahlungDatumC),
          decoration: const InputDecoration(labelText: 'Gezahlt am', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _betragC, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Betrag €', isDense: true, border: OutlineInputBorder()))),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(initialValue: _art,
        decoration: const InputDecoration(labelText: 'Überweisungsart', isDense: true, border: OutlineInputBorder()),
        items: const ['ueberweisung', 'scheck', 'bar', 'sonstige'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _art = v ?? 'ueberweisung')),
      const SizedBox(height: 10),
      TextField(controller: _notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
      ElevatedButton.icon(onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
    ],
  );
}

class _KgTermineTab extends StatefulWidget {
  final ApiService apiService;
  final int dossierId;
  final VoidCallback onChanged;
  const _KgTermineTab({required this.apiService, required this.dossierId, required this.onChanged});
  @override
  State<_KgTermineTab> createState() => _KgTermineTabState();
}

class _KgTermineTabState extends State<_KgTermineTab> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;

  static const _artLabel = {
    'mdk': 'MDK',
    'reha_antrag': 'Reha-Antrag',
    'wba': 'WBA',
    'gutachten': 'Gutachten',
    'beratung': 'Beratung',
    'sonstige': 'Sonstige',
  };

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listKrankengeldTermine(widget.dossierId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _openEdit({Map<String, dynamic>? existing}) async {
    final ok = await showDialog<bool>(context: context, builder: (_) => _KgTerminEditDialog(
      apiService: widget.apiService, dossierId: widget.dossierId, existing: existing));
    if (ok == true) { widget.onChanged(); _load(); }
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Termin löschen?'),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red)))],
    ));
    if (ok != true) return;
    await widget.apiService.deleteKrankengeldTermin(id);
    widget.onChanged(); _load();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Row(children: [
        Icon(Icons.event, size: 18, color: Colors.teal.shade700), const SizedBox(width: 8),
        Expanded(child: Text('${_items.length} Termin(e)', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
        ElevatedButton.icon(icon: const Icon(Icons.add, size: 16), label: const Text('Neu'), onPressed: () => _openEdit(),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
      ])),
      const Divider(height: 1),
      Expanded(child: _items.isEmpty
        ? Center(child: Text('Keine Termine', style: TextStyle(color: Colors.grey.shade600)))
        : ListView.builder(padding: const EdgeInsets.all(8), itemCount: _items.length, itemBuilder: (_, i) {
            final t = _items[i];
            return Card(child: ListTile(
              onTap: () => _openEdit(existing: t),
              leading: CircleAvatar(backgroundColor: Colors.amber.shade50, child: Icon(Icons.event_note, color: Colors.amber.shade800, size: 18)),
              title: Text('${t['termin_datum'] ?? '?'}${(t['termin_uhrzeit'] ?? '').toString().isNotEmpty ? " · ${t['termin_uhrzeit']}" : ""}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Container(padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  margin: const EdgeInsets.only(top: 2),
                  decoration: BoxDecoration(color: Colors.indigo.shade50, borderRadius: BorderRadius.circular(3)),
                  child: Text(_artLabel[(t['art'] ?? 'sonstige').toString()] ?? (t['art'] ?? '').toString(), style: TextStyle(fontSize: 10, color: Colors.indigo.shade800))),
                if ((t['ort'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [const Icon(Icons.place, size: 12, color: Colors.grey), const SizedBox(width: 4), Expanded(child: Text(t['ort'].toString(), style: const TextStyle(fontSize: 11), overflow: TextOverflow.ellipsis))])),
                if ((t['grund'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                  child: Text(t['grund'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11))),
                if ((t['ergebnis'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 2),
                  child: Text('→ ${t['ergebnis']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: Colors.green.shade800, fontStyle: FontStyle.italic))),
              ]),
              trailing: IconButton(icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red), onPressed: () => _delete(t['id'] as int)),
            ));
          })),
    ]);
  }
}

class _KgTerminEditDialog extends StatefulWidget {
  final ApiService apiService;
  final int dossierId;
  final Map<String, dynamic>? existing;
  const _KgTerminEditDialog({required this.apiService, required this.dossierId, this.existing});
  @override
  State<_KgTerminEditDialog> createState() => _KgTerminEditDialogState();
}

class _KgTerminEditDialogState extends State<_KgTerminEditDialog> {
  late TextEditingController _datumC, _zeitC, _ortC, _grundC, _ergebnisC, _notizC;
  String _art = 'mdk';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing ?? <String, dynamic>{};
    _datumC    = TextEditingController(text: e['termin_datum']?.toString() ?? DateFormat('yyyy-MM-dd').format(DateTime.now()));
    _zeitC     = TextEditingController(text: e['termin_uhrzeit']?.toString() ?? '');
    _ortC      = TextEditingController(text: e['ort']?.toString() ?? '');
    _grundC    = TextEditingController(text: e['grund']?.toString() ?? '');
    _ergebnisC = TextEditingController(text: e['ergebnis']?.toString() ?? '');
    _notizC    = TextEditingController(text: e['notiz']?.toString() ?? '');
    _art       = e['art']?.toString() ?? 'mdk';
  }

  @override
  void dispose() {
    for (final c in [_datumC, _zeitC, _ortC, _grundC, _ergebnisC, _notizC]) { c.dispose(); }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final init = DateTime.tryParse(_datumC.text) ?? DateTime.now();
    final p = await showDatePicker(context: context, initialDate: init, firstDate: DateTime(2010), lastDate: DateTime(2050), locale: const Locale('de'));
    if (p != null) setState(() => _datumC.text = DateFormat('yyyy-MM-dd').format(p));
  }

  Future<void> _pickTime() async {
    final parts = _zeitC.text.split(':');
    final init = parts.length == 2 ? TimeOfDay(hour: int.tryParse(parts[0]) ?? 9, minute: int.tryParse(parts[1]) ?? 0) : const TimeOfDay(hour: 9, minute: 0);
    final p = await showTimePicker(context: context, initialTime: init);
    if (p != null) setState(() => _zeitC.text = '${p.hour.toString().padLeft(2,'0')}:${p.minute.toString().padLeft(2,'0')}');
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final body = {
      if (widget.existing != null) 'id': widget.existing!['id'],
      'termin_datum': _datumC.text.trim(),
      'termin_uhrzeit': _zeitC.text.trim(),
      'art': _art,
      'ort': _ortC.text.trim(),
      'grund': _grundC.text.trim(),
      'ergebnis': _ergebnisC.text.trim(),
      'notiz': _notizC.text.trim(),
    };
    final res = await widget.apiService.saveKrankengeldTermin(widget.dossierId, body);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res['success'] == true) Navigator.pop(context, true);
    else ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(res['message'] ?? 'Fehler'), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.existing == null ? 'Neuer Termin' : 'Termin bearbeiten'),
    content: SizedBox(width: 460, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Expanded(child: TextField(controller: _datumC, readOnly: true, onTap: _pickDate,
          decoration: const InputDecoration(labelText: 'Datum', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.calendar_today, size: 16)))),
        const SizedBox(width: 8),
        Expanded(child: TextField(controller: _zeitC, readOnly: true, onTap: _pickTime,
          decoration: const InputDecoration(labelText: 'Uhrzeit', isDense: true, border: OutlineInputBorder(), suffixIcon: Icon(Icons.access_time, size: 16)))),
      ]),
      const SizedBox(height: 10),
      DropdownButtonFormField<String>(initialValue: _art,
        decoration: const InputDecoration(labelText: 'Art', isDense: true, border: OutlineInputBorder()),
        items: const ['mdk', 'reha_antrag', 'wba', 'gutachten', 'beratung', 'sonstige'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => _art = v ?? 'mdk')),
      const SizedBox(height: 10),
      TextField(controller: _ortC, decoration: const InputDecoration(labelText: 'Ort', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _grundC, maxLines: 2, decoration: const InputDecoration(labelText: 'Grund / Thema', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _ergebnisC, maxLines: 2, decoration: const InputDecoration(labelText: 'Ergebnis', isDense: true, border: OutlineInputBorder())),
      const SizedBox(height: 10),
      TextField(controller: _notizC, maxLines: 2, decoration: const InputDecoration(labelText: 'Notiz', isDense: true, border: OutlineInputBorder())),
    ]))),
    actions: [
      TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Abbrechen')),
      ElevatedButton.icon(onPressed: _saving ? null : _save,
        icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16),
        label: const Text('Speichern'),
        style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white)),
    ],
  );
}

// ─── Read-only view dialog for a Krankengeld-Korr entry ───
// Shows full content + attached files. Footer offers Edit / Delete.

class _KgKorrViewDialog extends StatefulWidget {
  final ApiService apiService;
  final Map<String, dynamic> korr;
  const _KgKorrViewDialog({required this.apiService, required this.korr});
  @override
  State<_KgKorrViewDialog> createState() => _KgKorrViewDialogState();
}

class _KgKorrViewDialogState extends State<_KgKorrViewDialog> {
  bool _docsTouched = false;

  Widget _kv(IconData icon, String label, String? value, {bool multiline = false}) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(padding: const EdgeInsets.symmetric(vertical: 4), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Icon(icon, size: 16, color: Colors.grey.shade600), const SizedBox(width: 8),
      SizedBox(width: 110, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
      Expanded(child: Text(value,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        maxLines: multiline ? null : 3,
        overflow: multiline ? null : TextOverflow.ellipsis,
      )),
    ]));
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.korr;
    final eingang = k['richtung'] == 'eingang';
    final isErledigt = k['erledigt'] == 1 || k['erledigt'] == true;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(width: 620, height: 640, child: Column(children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.teal.shade700, borderRadius: const BorderRadius.vertical(top: Radius.circular(4))),
          child: Row(children: [
            Icon(eingang ? Icons.south_west : Icons.north_east, color: Colors.white), const SizedBox(width: 8),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(k['betreff']?.toString().isNotEmpty == true ? k['betreff'].toString() : '(ohne Betreff)',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
              Text('${k['datum'] ?? ''} · ${eingang ? "eingang" : "ausgang"} · ${k['medium'] ?? ''}',
                style: TextStyle(color: Colors.teal.shade100, fontSize: 11)),
            ])),
            if (isErledigt) Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              margin: const EdgeInsets.only(right: 6),
              decoration: BoxDecoration(color: Colors.green.shade600, borderRadius: BorderRadius.circular(8)),
              child: const Text('Erledigt', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.pop(context, _docsTouched ? 'docs_changed' : null)),
          ]),
        ),
        Expanded(child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if ((k['text'] ?? '').toString().trim().isNotEmpty) ...[
            Text('Inhalt', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade700, letterSpacing: 0.5)),
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.grey.shade300)),
              child: Text(k['text'].toString(), style: const TextStyle(fontSize: 13, height: 1.4)),
            ),
            const SizedBox(height: 12),
          ],
          _kv(Icons.sticky_note_2, 'Notiz', k['notiz']?.toString(), multiline: true),
          const SizedBox(height: 12),
          const Divider(),
          const SizedBox(height: 6),
          Text('Anhänge', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.teal.shade700, letterSpacing: 0.5)),
          const SizedBox(height: 6),
          _KgKorrDocsSection(
            apiService: widget.apiService,
            korrId: k['id'] as int,
            onChanged: () => _docsTouched = true,
          ),
        ]))),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.grey.shade100, border: Border(top: BorderSide(color: Colors.grey.shade300))),
          child: Row(children: [
            TextButton.icon(
              onPressed: () => Navigator.pop(context, 'delete'),
              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
              label: const Text('Löschen', style: TextStyle(color: Colors.red)),
            ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context, _docsTouched ? 'docs_changed' : null), child: const Text('Schließen')),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context, 'edit'),
              icon: const Icon(Icons.edit, size: 16),
              label: const Text('Bearbeiten'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade700, foregroundColor: Colors.white),
            ),
          ]),
        ),
      ])),
    );
  }
}

// ─── Multi-file uploader for one Krankengeld-Korr entry (up to 20) ───

class _KgKorrDocsSection extends StatefulWidget {
  final ApiService apiService;
  final int korrId;
  final VoidCallback? onChanged;
  const _KgKorrDocsSection({required this.apiService, required this.korrId, this.onChanged});
  @override
  State<_KgKorrDocsSection> createState() => _KgKorrDocsSectionState();
}

class _KgKorrDocsSectionState extends State<_KgKorrDocsSection> {
  List<Map<String, dynamic>> _items = [];
  bool _loaded = false;
  bool _uploading = false;
  int _doneCount = 0, _totalCount = 0;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final res = await widget.apiService.listKrankengeldKorrDocs(widget.korrId);
    if (!mounted) return;
    setState(() {
      _items = List<Map<String, dynamic>>.from(res['items'] as List? ?? []);
      _loaded = true;
    });
  }

  Future<void> _upload() async {
    final r = await FilePickerHelper.pickFiles(
      allowMultiple: true, type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'odt', 'txt'],
    );
    if (r == null || r.files.isEmpty) return;
    var files = r.files.where((f) => f.path != null).toList();
    final scaffold = ScaffoldMessenger.of(context);
    if (files.length > 20) {
      scaffold.showSnackBar(SnackBar(content: Text('Max. 20 Dateien — ${files.length - 20} ausgelassen'), backgroundColor: Colors.orange));
      files = files.sublist(0, 20);
    }
    setState(() { _uploading = true; _doneCount = 0; _totalCount = files.length; });
    final errors = <String>[];
    for (final f in files) {
      final res = await widget.apiService.uploadKrankengeldKorrDoc(
        korrId: widget.korrId, filePath: f.path!, fileName: f.name,
      );
      if (res['success'] == true) { _doneCount++; } else { errors.add('${f.name}: ${res['message'] ?? '?'}'); }
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    setState(() => _uploading = false);
    scaffold.showSnackBar(SnackBar(
      content: Text(errors.isEmpty
        ? '$_doneCount/$_totalCount Datei(en) hochgeladen'
        : '$_doneCount OK, ${errors.length} fehlgeschlagen:\n${errors.join("\n")}'),
      backgroundColor: errors.isEmpty ? Colors.green : Colors.orange,
      duration: const Duration(seconds: 4),
    ));
    widget.onChanged?.call();
    _load();
  }

  Future<void> _delete(int id) async {
    final ok = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Datei löschen?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
        TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Löschen', style: TextStyle(color: Colors.red))),
      ],
    ));
    if (ok != true) return;
    final res = await widget.apiService.deleteKrankengeldKorrDoc(id);
    if (res['success'] == true) { widget.onChanged?.call(); _load(); }
  }

  Future<void> _open(Map<String, dynamic> d, {bool externalApp = false}) async {
    try {
      final resp = await widget.apiService.downloadKrankengeldKorrDoc(d['id'] as int);
      if (resp.statusCode != 200 || !mounted) return;
      final dir = await getTemporaryDirectory();
      final safeName = (d['datei_name']?.toString() ?? 'kg_korr_${d['id']}.pdf').replaceAll(RegExp(r'[<>:"|?*\\/]'), '_');
      final f = File('${dir.path}/$safeName');
      await f.writeAsBytes(resp.bodyBytes);
      if (externalApp) {
        await OpenFilex.open(f.path);
      } else if (mounted) {
        await FileViewerDialog.show(context, f.path, safeName);
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Padding(padding: EdgeInsets.all(8), child: Center(child: CircularProgressIndicator()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        Icon(Icons.folder_zip, size: 16, color: Colors.teal.shade700), const SizedBox(width: 6),
        Expanded(child: Text('${_items.length} Datei(en)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.teal.shade800))),
        ElevatedButton.icon(
          onPressed: _uploading ? null : _upload,
          icon: _uploading
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.upload_file, size: 14),
          label: Text(
            _uploading
              ? (_totalCount > 0 ? '$_doneCount / $_totalCount …' : 'Lädt…')
              : 'Hochladen (bis 20)',
            style: const TextStyle(fontSize: 11),
          ),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
        ),
      ]),
      const SizedBox(height: 6),
      if (_items.isEmpty)
        Padding(padding: const EdgeInsets.all(8), child: Text('Keine Dateien', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)))
      else
        ..._items.map((d) {
          final kb = ((d['file_size'] as num?) ?? 0).toInt() ~/ 1024;
          return Padding(padding: const EdgeInsets.symmetric(vertical: 2), child: Row(children: [
            Icon(Icons.description, size: 16, color: Colors.teal.shade400), const SizedBox(width: 6),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d['datei_name']?.toString() ?? '?', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
              Text('$kb KB · ${d['erstellt_am'] ?? ''}', style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            ])),
            IconButton(icon: const Icon(Icons.visibility, size: 16), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), tooltip: 'Anzeigen', onPressed: () => _open(d)),
            IconButton(icon: Icon(Icons.download, size: 16, color: Colors.green.shade700), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), tooltip: 'Herunterladen', onPressed: () => _open(d, externalApp: true)),
            IconButton(icon: const Icon(Icons.close, size: 16, color: Colors.red), padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 28, minHeight: 28), onPressed: () => _delete(d['id'] as int)),
          ]));
        }),
    ]);
  }
}

// ============ Versicherungskarte: Design-Helfer ============

/// Kassen-Design: Markenfarbe (Verlauf), Textfarbe und Kurz-Wortmarke.
/// Bewusst ohne geschuetzte Original-Logos — Nachbildung anhand Farbe + Wortmarke.
class _EgkTheme {
  final Color primary;
  final Color primaryDark;
  final Color onPrimary;
  final String? mark;
  const _EgkTheme(this.primary, this.primaryDark, this.onPrimary, this.mark);
}

/// Ergebnis der eGK-Lichtbild-Prüfung: harte Fehler (issues) und Warnungen (warns).
class _FotoCheck {
  final List<String> issues;
  final List<String> warns;
  final int? imgW;
  final int? imgH;
  const _FotoCheck(this.issues, this.warns, {this.imgW, this.imgH});
  bool get perfect => issues.isEmpty && warns.isEmpty;
  bool get hasHardFail => issues.isNotEmpty;
}

/// Zeichnet den EU-Sternenkranz (12 goldene Sterne im Kreis) fuer die EHIC-Rueckseite.
class _EuStarsPainter extends CustomPainter {
  final Color color;
  const _EuStarsPainter({this.color = const Color(0xFFFFCC00)});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final ringR = size.width * 0.40;
    final starR = size.width * 0.075;
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    for (int i = 0; i < 12; i++) {
      final a = (i / 12) * 2 * math.pi - math.pi / 2;
      final c = Offset(center.dx + ringR * math.cos(a), center.dy + ringR * math.sin(a));
      canvas.drawPath(_star(c, starR), paint);
    }
  }

  Path _star(Offset c, double r) {
    final path = Path();
    for (int i = 0; i < 5; i++) {
      final outer = (i / 5) * 2 * math.pi - math.pi / 2;
      final inner = outer + math.pi / 5;
      final ox = c.dx + r * math.cos(outer);
      final oy = c.dy + r * math.sin(outer);
      final ix = c.dx + (r * 0.42) * math.cos(inner);
      final iy = c.dy + (r * 0.42) * math.sin(inner);
      if (i == 0) {
        path.moveTo(ox, oy);
      } else {
        path.lineTo(ox, oy);
      }
      path.lineTo(ix, iy);
    }
    path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _EuStarsPainter old) => old.color != color;
}

/// Zeichnet die Kontaktflaechen des goldenen eGK-Chips.
class _EgkChipPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0xFF8A6D1F)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
    final w = size.width, h = size.height;
    final pad = Rect.fromLTWH(w * 0.30, h * 0.28, w * 0.40, h * 0.44);
    canvas.drawRRect(RRect.fromRectAndRadius(pad, const Radius.circular(2)), p);
    canvas.drawLine(Offset(0, h * 0.34), Offset(w * 0.30, h * 0.34), p);
    canvas.drawLine(Offset(0, h * 0.66), Offset(w * 0.30, h * 0.66), p);
    canvas.drawLine(Offset(w * 0.70, h * 0.34), Offset(w, h * 0.34), p);
    canvas.drawLine(Offset(w * 0.70, h * 0.66), Offset(w, h * 0.66), p);
    canvas.drawLine(Offset(w * 0.5, 0), Offset(w * 0.5, h * 0.28), p);
    canvas.drawLine(Offset(w * 0.5, h * 0.72), Offset(w * 0.5, h), p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

