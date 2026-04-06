import 'dart:io';
import 'package:flutter/material.dart';
import '../utils/clipboard_helper.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../models/user.dart';

/// Steuererklärung helper — Anlage N 2025 (offizielles Formular)
/// Pulls data from Arbeitgeber/Lohnsteuerbescheinigung via OCR
class FinanzamtSteuerklarungWidget extends StatefulWidget {
  final ApiService apiService;
  final User user;
  final Map<String, dynamic> finanzamtData;
  final VoidCallback onBack;

  const FinanzamtSteuerklarungWidget({
    super.key,
    required this.apiService,
    required this.user,
    required this.finanzamtData,
    required this.onBack,
  });

  @override
  State<FinanzamtSteuerklarungWidget> createState() => _FinanzamtSteuerklarungWidgetState();
}

class _FinanzamtSteuerklarungWidgetState extends State<FinanzamtSteuerklarungWidget> {
  bool _isLoading = true;
  Map<String, dynamic> _arbeitgeberData = {};
  List<Map<String, dynamic>> _arbeitgeberListe = [];

  // Steuerjahr
  int _steuerJahr = DateTime.now().year - 1;

  // ══════════════════════════════════════════════════════
  // ANLAGE N 2025 — Offizielle Zeilen gemäß Vordruck
  // ══════════════════════════════════════════════════════

  // ── Zeilen 1–3: Kopfzeile ──
  final _z1NameC = TextEditingController();           // Z1: Name
  final _z2VornameC = TextEditingController();        // Z2: Vorname
  final _z3SteuernummerC = TextEditingController();   // Z3: Steuernummer

  // ── Zeilen 4–10: Angaben zum Arbeitslohn ──
  String _z4Steuerklasse = '';                        // Z4: Steuerklasse (KZ 168)
  final _z5BruttoC = TextEditingController();         // Z5: Bruttoarbeitslohn (KZ 110)
  final _z6LohnsteuerC = TextEditingController();     // Z6: Lohnsteuer (KZ 140)
  final _z7SoliC = TextEditingController();           // Z7: Solidaritätszuschlag (KZ 150)
  final _z8KirchensteuerC = TextEditingController();  // Z8: Kirchensteuer AN (KZ 142)
  final _z9KirchensteuerEheC = TextEditingController(); // Z9: Kirchensteuer Ehegatte (KZ 144)

  // ── Zeilen 11–16: Versorgungsbezüge ──
  final _z11VersorgungC = TextEditingController();    // Z11: Versorgungsbezüge (KZ 200)
  final _z12BemessungC = TextEditingController();     // Z12: Bemessungsgrundlage (KZ 201)
  final _z13KalenderjahrC = TextEditingController();  // Z13: Kalenderjahr Versorgungsbeginn (KZ 206)

  // ── Zeilen 17–20: Sonderfälle Arbeitslohn ──
  final _z17EntschaedigungC = TextEditingController(); // Z17: Arbeitslohn mehrere Jahre / Entschädigungen (KZ 165)
  final _z18OhneSteuerabzugC = TextEditingController(); // Z18: Steuerpfl. Arbeitslohn ohne Steuerabzug (KZ 115)
  final _z19AufwandsentschaedigungC = TextEditingController(); // Z19: Steuerfreie Aufwandsentschädigungen (KZ 118)
  final _z20KurzarbeitergeldC = TextEditingController(); // Z20: Kurzarbeitergeld, Elterngeld etc. (KZ 119)

  // ── Zeilen 27–34: Entfernungspauschale (1. Angabe) ──
  final _z27OrtC = TextEditingController();           // Z27: PLZ, Ort, Straße der Tätigkeitsstätte
  String _z27Typ = '1';                               // 1=erste Tätigkeitsstätte, 2=Sammelpunkt
  final _z27VomC = TextEditingController();           // vom
  final _z27BisC = TextEditingController();           // bis
  final _z28ArbeitstageWocheC = TextEditingController(); // Z28: Arbeitstage je Woche
  final _z28UrlaubstageC = TextEditingController();   // Z28: Urlaubs-/Krankheitstage
  final _z29TageC = TextEditingController();          // Z29: aufgesucht an Tagen (KZ 110)
  final _z30EntfernungC = TextEditingController();    // Z30: einfache Entfernung km (KZ 111)
  final _z31PkwKmC = TextEditingController();         // Z31: davon mit PKW (KZ 112)
  final _z34OepnvC = TextEditingController();         // Z34: Aufwendungen öffentl. Verkehrsmittel (KZ 114)

  // ── Zeile 53: Beiträge zu Berufsverbänden ──
  final _z53BerufsverbandC = TextEditingController(); // Z53: Berufsverbände (KZ 310)

  // ── Zeilen 54–56: Arbeitsmittel ──
  final _z54Arbeitsmittel1C = TextEditingController(); // Z54: Arbeitsmittel 1
  final _z55Arbeitsmittel2C = TextEditingController(); // Z55: Arbeitsmittel 2
  // Z56: Summe (berechnet)

  // ── Zeile 57: Häusliches Arbeitszimmer ──
  final _z57ArbeitszimmerC = TextEditingController(); // Z57: Arbeitszimmer (KZ 325)

  // ── Zeilen 58–59: Tagespauschale Homeoffice ──
  final _z58HomeOfficeTage1C = TextEditingController(); // Z58: Tage mit anderem Arbeitsplatz (KZ 335)
  final _z59HomeOfficeTage2C = TextEditingController(); // Z59: Tage ohne anderen Arbeitsplatz (KZ 336)

  // ── Zeile 60: Fortbildungskosten ──
  final _z60FortbildungC = TextEditingController();   // Z60: Fortbildung (KZ 330)

  // ── Zeilen 61–64: Weitere Werbungskosten ──
  final _z61FaehrFlugC = TextEditingController();     // Z61: Fähr-/Flugkosten
  final _z62SonstigesC = TextEditingController();     // Z62: Sonstiges (Bewerbung, Kontoführung)
  final _z63Sonstiges2C = TextEditingController();    // Z63: Sonstiges 2
  // Z64: Summe weitere WK (KZ 380, berechnet)

  // ── Zeilen 65–71: Reisekosten ──
  final _z66FahrtkostenC = TextEditingController();   // Z66: Fahrtkosten
  final _z67UebernachtungC = TextEditingController(); // Z67: Übernachtungskosten
  final _z68ReisenebenC = TextEditingController();    // Z68: Reisenebenkosten
  // Z69: Gesamtsumme Reisekosten (KZ 410, berechnet)
  final _z71ErsattReiseC = TextEditingController();   // Z71: Vom AG steuerfrei ersetzt (KZ 420)

  // ── Zeilen 72–77: Verpflegungsmehraufwand ──
  final _z72Tage8hC = TextEditingController();        // Z72: Tage >8h (KZ 470)
  final _z73AnAbreisetageC = TextEditingController(); // Z73: An-/Abreisetage (KZ 471)
  final _z74Tage24hC = TextEditingController();       // Z74: Tage 24h (KZ 472)
  final _z75KuerzungC = TextEditingController();      // Z75: Kürzung Mahlzeiten (KZ 473)
  final _z77ErsattVerpflegungC = TextEditingController(); // Z77: Vom AG steuerfrei ersetzt (KZ 490)

  // ── Vorsorgeaufwand (nicht in Anlage N, aber aus LSB) ──
  final _rentenversicherungC = TextEditingController();
  final _arbeitslosenversicherungC = TextEditingController();
  final _krankenversicherungC = TextEditingController();
  final _pflegeversicherungC = TextEditingController();

  // Lohnsteuerbescheinigung docs
  List<Map<String, dynamic>> _lsbDokumente = [];
  bool _isOcrRunning = false;
  String _ocrError = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    for (final c in [
      _z1NameC, _z2VornameC, _z3SteuernummerC,
      _z5BruttoC, _z6LohnsteuerC, _z7SoliC, _z8KirchensteuerC, _z9KirchensteuerEheC,
      _z11VersorgungC, _z12BemessungC, _z13KalenderjahrC,
      _z17EntschaedigungC, _z18OhneSteuerabzugC, _z19AufwandsentschaedigungC, _z20KurzarbeitergeldC,
      _z27OrtC, _z27VomC, _z27BisC, _z28ArbeitstageWocheC, _z28UrlaubstageC,
      _z29TageC, _z30EntfernungC, _z31PkwKmC, _z34OepnvC,
      _z53BerufsverbandC, _z54Arbeitsmittel1C, _z55Arbeitsmittel2C,
      _z57ArbeitszimmerC, _z58HomeOfficeTage1C, _z59HomeOfficeTage2C, _z60FortbildungC,
      _z61FaehrFlugC, _z62SonstigesC, _z63Sonstiges2C,
      _z66FahrtkostenC, _z67UebernachtungC, _z68ReisenebenC, _z71ErsattReiseC,
      _z72Tage8hC, _z73AnAbreisetageC, _z74Tage24hC, _z75KuerzungC, _z77ErsattVerpflegungC,
      _rentenversicherungC, _arbeitslosenversicherungC, _krankenversicherungC, _pflegeversicherungC,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final agResult = await widget.apiService.getBehoerdeData(widget.user.id, 'arbeitgeber');
      if (agResult['success'] == true && agResult['data'] is Map) {
        _arbeitgeberData = Map<String, dynamic>.from(agResult['data'] as Map);
        final liste = _arbeitgeberData['liste'];
        if (liste is List) {
          _arbeitgeberListe = liste.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        }
      }

      // Load Lohnsteuerbescheinigung documents
      if (_arbeitgeberListe.isNotEmpty) {
        final docsResult = await widget.apiService.getArbeitgeberDokumente(widget.user.id, 0);
        final docsList = docsResult['dokumente'] ?? docsResult['data'];
        if (docsList is List) {
          _lsbDokumente = docsList
              .where((d) => d['dok_typ'] == 'lohnsteuerbescheinigung')
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();
        }
      }

      // Pre-fill Z1-3 from User + Finanzamt data
      _z1NameC.text = widget.user.nachname ?? '';
      _z2VornameC.text = widget.user.vorname ?? '';
      _z3SteuernummerC.text = widget.finanzamtData['steuernummer']?.toString() ??
          widget.finanzamtData['steuer_id']?.toString() ?? '';
      _z4Steuerklasse = widget.finanzamtData['steuerklasse']?.toString() ?? '';

      // Pre-fill from Arbeitgeber if available
      if (_arbeitgeberListe.isNotEmpty) {
        final ag = _arbeitgeberListe.first;
        final lsb = ag['lohnsteuerbescheinigungen'];
        if (lsb is List && lsb.isNotEmpty) {
          final latest = lsb.firstWhere(
            (b) => b['jahr']?.toString() == _steuerJahr.toString(),
            orElse: () => lsb.first,
          );
          if (latest['bruttoarbeitslohn'] != null) {
            _z5BruttoC.text = latest['bruttoarbeitslohn'].toString();
          }
        }
        // Estimate from Grundgehalt
        if (_z5BruttoC.text.isEmpty && ag['grundgehalt'] != null) {
          final monthly = double.tryParse(ag['grundgehalt'].toString()) ?? 0;
          if (monthly > 0) _z5BruttoC.text = (monthly * 12).toStringAsFixed(2);
        }
        // Pre-fill Tätigkeitsstätte
        if (ag['ort'] != null) _z27OrtC.text = ag['ort'].toString();
      }
    } catch (e) {
      debugPrint('[Steuerklarung] _loadData error: $e');
    }
    if (mounted) setState(() => _isLoading = false);

    // Auto-run OCR if documents exist
    if (_lsbDokumente.isNotEmpty) {
      _runOcr();
    }
  }

  Future<void> _runOcr() async {
    if (_lsbDokumente.isEmpty) return;
    setState(() { _isOcrRunning = true; _ocrError = ''; });
    try {
      final docId = int.tryParse(_lsbDokumente.first['id']?.toString() ?? '');
      if (docId == null) {
        setState(() { _isOcrRunning = false; _ocrError = 'Keine gültige Dokument-ID'; });
        return;
      }
      final result = await widget.apiService.ocrLohnsteuerbescheinigung(docId);

      final isSuccess = result['success'] == true || result['success'] == 'true';

      Map<String, dynamic>? felder;
      if (result['felder'] is Map) {
        felder = Map<String, dynamic>.from(result['felder'] as Map);
      } else if (result['data'] is Map && (result['data'] as Map)['felder'] is Map) {
        felder = Map<String, dynamic>.from((result['data'] as Map)['felder'] as Map);
      }

      if (isSuccess && felder != null && felder.isNotEmpty) {
        setState(() {
          _z5BruttoC.text = felder!['bruttoarbeitslohn']?.toString() ?? _z5BruttoC.text;
          _z6LohnsteuerC.text = felder['lohnsteuer']?.toString() ?? _z6LohnsteuerC.text;
          _z7SoliC.text = felder['solidaritaetszuschlag']?.toString() ?? _z7SoliC.text;
          _z8KirchensteuerC.text = felder['kirchensteuer']?.toString() ?? _z8KirchensteuerC.text;
          _rentenversicherungC.text = felder['rentenversicherung']?.toString() ?? _rentenversicherungC.text;
          _arbeitslosenversicherungC.text = felder['arbeitslosenversicherung']?.toString() ?? _arbeitslosenversicherungC.text;
          _krankenversicherungC.text = felder['krankenversicherung']?.toString() ?? _krankenversicherungC.text;
          _pflegeversicherungC.text = felder['pflegeversicherung']?.toString() ?? _pflegeversicherungC.text;
          if (felder['steuerklasse'] != null) _z4Steuerklasse = felder['steuerklasse'].toString();
          if (felder['steuer_id'] != null && _z3SteuernummerC.text.isEmpty) {
            _z3SteuernummerC.text = felder['steuer_id'].toString();
          }
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('OCR: Brutto ${_z5BruttoC.text} €, LSt ${_z6LohnsteuerC.text} €'),
              backgroundColor: Colors.green.shade600,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      } else {
        final msg = result['message']?.toString() ?? 'Keine Felder erkannt';
        setState(() => _ocrError = 'OCR: $msg (success=$isSuccess, felder=${felder?.length ?? 0})');
      }
    } catch (e) {
      setState(() => _ocrError = 'OCR Fehler: $e');
    }
    if (mounted) setState(() => _isOcrRunning = false);
  }

  double _parseEuro(String val) => double.tryParse(val.replaceAll(',', '.').replaceAll('€', '').trim()) ?? 0;

  String _fmtEuro(double val) => NumberFormat.currency(locale: 'de_DE', symbol: '€').format(val);

  /// Entfernungspauschale: erste 20 km × 0,30 €, ab 21 km × 0,38 €
  double _calcEntfernungspauschale() {
    final km = double.tryParse(_z30EntfernungC.text) ?? 0;
    final tage = int.tryParse(_z29TageC.text) ?? 0;
    if (km <= 0 || tage <= 0) return 0;
    if (km <= 20) return km * 0.30 * tage;
    return (20 * 0.30 + (km - 20) * 0.38) * tage;
  }

  /// Home-Office Pauschale: 6 € pro Tag, max 1.260 € (210 Tage)
  double _calcHomeOfficePauschale() {
    final t1 = int.tryParse(_z58HomeOfficeTage1C.text) ?? 0;
    final t2 = int.tryParse(_z59HomeOfficeTage2C.text) ?? 0;
    final tage = t1 + t2;
    if (tage <= 0) return 0;
    return (tage > 210 ? 210 : tage) * 6.0;
  }

  /// Verpflegungsmehraufwand
  double _calcVerpflegung() {
    final t8h = int.tryParse(_z72Tage8hC.text) ?? 0;
    final anAbreise = int.tryParse(_z73AnAbreisetageC.text) ?? 0;
    final t24h = int.tryParse(_z74Tage24hC.text) ?? 0;
    final kuerzung = _parseEuro(_z75KuerzungC.text);
    final ersetzt = _parseEuro(_z77ErsattVerpflegungC.text);
    // 2025: >8h = 14€, An-/Abreisetag = 14€, 24h = 28€
    return (t8h * 14.0) + (anAbreise * 14.0) + (t24h * 28.0) - kuerzung - ersetzt;
  }

  /// Summe Arbeitsmittel (Z56)
  double _calcArbeitsmittel() {
    return _parseEuro(_z54Arbeitsmittel1C.text) + _parseEuro(_z55Arbeitsmittel2C.text);
  }

  /// Summe weitere Werbungskosten (Z64)
  double _calcWeitereWK() {
    return _parseEuro(_z61FaehrFlugC.text) + _parseEuro(_z62SonstigesC.text) + _parseEuro(_z63Sonstiges2C.text);
  }

  /// Reisekosten gesamt (Z69)
  double _calcReisekosten() {
    return _parseEuro(_z66FahrtkostenC.text) +
        _parseEuro(_z67UebernachtungC.text) +
        _parseEuro(_z68ReisenebenC.text);
  }

  /// Reisekosten netto (nach Erstattung)
  double _calcReisekostenNetto() {
    return _calcReisekosten() - _parseEuro(_z71ErsattReiseC.text);
  }

  /// Gesamte Werbungskosten
  double _calcGesamtWerbungskosten() {
    return _calcEntfernungspauschale() +
        _parseEuro(_z34OepnvC.text) +
        _parseEuro(_z53BerufsverbandC.text) +
        _calcArbeitsmittel() +
        _parseEuro(_z57ArbeitszimmerC.text) +
        _calcHomeOfficePauschale() +
        _parseEuro(_z60FortbildungC.text) +
        _calcWeitereWK() +
        _calcReisekostenNetto() +
        (_calcVerpflegung() > 0 ? _calcVerpflegung() : 0);
  }

  Future<void> _generateElsterXml() async {
    final xml = '''<?xml version="1.0" encoding="UTF-8"?>
<!-- ELSTER Steuererklärung $_steuerJahr - Generiert von ICD360S e.V. -->
<!-- HINWEIS: Diese XML-Datei dient als Vorlage für ELSTER. -->
<Steuererklarung>
  <Allgemein>
    <Steuerjahr>$_steuerJahr</Steuerjahr>
    <Steuernummer>${_z3SteuernummerC.text}</Steuernummer>
    <Name>${_z1NameC.text}</Name>
    <Vorname>${_z2VornameC.text}</Vorname>
    <Steuerklasse>$_z4Steuerklasse</Steuerklasse>
  </Allgemein>
  <AnlageN>
    <Zeile4_Steuerklasse KZ="168">$_z4Steuerklasse</Zeile4_Steuerklasse>
    <Zeile5_Bruttoarbeitslohn KZ="110">${_z5BruttoC.text}</Zeile5_Bruttoarbeitslohn>
    <Zeile6_Lohnsteuer KZ="140">${_z6LohnsteuerC.text}</Zeile6_Lohnsteuer>
    <Zeile7_Solidaritaetszuschlag KZ="150">${_z7SoliC.text}</Zeile7_Solidaritaetszuschlag>
    <Zeile8_Kirchensteuer KZ="142">${_z8KirchensteuerC.text}</Zeile8_Kirchensteuer>
    <Zeile17_Entschaedigung KZ="165">${_z17EntschaedigungC.text}</Zeile17_Entschaedigung>
    <Zeile29_Arbeitstage KZ="110">${_z29TageC.text}</Zeile29_Arbeitstage>
    <Zeile30_Entfernung KZ="111">${_z30EntfernungC.text}</Zeile30_Entfernung>
    <Zeile53_Berufsverband KZ="310">${_z53BerufsverbandC.text}</Zeile53_Berufsverband>
    <Zeile56_Arbeitsmittel KZ="320">${_calcArbeitsmittel().toStringAsFixed(2)}</Zeile56_Arbeitsmittel>
    <Zeile57_Arbeitszimmer KZ="325">${_z57ArbeitszimmerC.text}</Zeile57_Arbeitszimmer>
    <Zeile58_HomeOffice KZ="335">${_z58HomeOfficeTage1C.text}</Zeile58_HomeOffice>
    <Zeile59_HomeOffice KZ="336">${_z59HomeOfficeTage2C.text}</Zeile59_HomeOffice>
    <Zeile60_Fortbildung KZ="330">${_z60FortbildungC.text}</Zeile60_Fortbildung>
    <Zeile64_WeitereWK KZ="380">${_calcWeitereWK().toStringAsFixed(2)}</Zeile64_WeitereWK>
    <Zeile69_Reisekosten KZ="410">${_calcReisekosten().toStringAsFixed(2)}</Zeile69_Reisekosten>
    <Werbungskosten_Gesamt>${_calcGesamtWerbungskosten().toStringAsFixed(2)}</Werbungskosten_Gesamt>
  </AnlageN>
</Steuererklarung>
''';

    try {
      final dir = await getDownloadsDirectory() ?? await getTemporaryDirectory();
      final file = File('${dir.path}/anlage_n_${_steuerJahr}_${widget.user.mitgliedernummer}.xml');
      await file.writeAsString(xml);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('XML gespeichert: ${file.path}'),
            backgroundColor: Colors.green.shade600,
            duration: const Duration(seconds: 3),
            action: SnackBarAction(label: 'Öffnen', textColor: Colors.white, onPressed: () => OpenFilex.open(file.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final entfernung = _calcEntfernungspauschale();
    final oepnv = _parseEuro(_z34OepnvC.text);
    final berufsverband = _parseEuro(_z53BerufsverbandC.text);
    final arbeitsmittel = _calcArbeitsmittel();
    final arbeitszimmer = _parseEuro(_z57ArbeitszimmerC.text);
    final homeOffice = _calcHomeOfficePauschale();
    final fortbildung = _parseEuro(_z60FortbildungC.text);
    final weitereWK = _calcWeitereWK();
    final reisekostenNetto = _calcReisekostenNetto();
    final verpflegung = _calcVerpflegung();
    final werbungskosten = _calcGesamtWerbungskosten();
    final brutto = _parseEuro(_z5BruttoC.text);
    final pauschbetrag = 1230.0; // Arbeitnehmer-Pauschbetrag 2025
    final abzug = werbungskosten > pauschbetrag ? werbungskosten : pauschbetrag;
    final zvE = brutto - abzug;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Row(children: [
            IconButton(icon: const Icon(Icons.arrow_back, size: 20), onPressed: widget.onBack, tooltip: 'Zurück'),
            const SizedBox(width: 8),
            Icon(Icons.receipt_long, size: 28, color: Colors.indigo.shade700),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Anlage N $_steuerJahr', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.indigo.shade800)),
              Text('Einkünfte aus nichtselbständiger Arbeit', style: TextStyle(fontSize: 11, color: Colors.indigo.shade500)),
            ])),
            DropdownButton<int>(
              value: _steuerJahr,
              underline: const SizedBox(),
              items: List.generate(5, (i) {
                final y = DateTime.now().year - 1 - i;
                return DropdownMenuItem(value: y, child: Text('$y', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)));
              }),
              onChanged: (y) { if (y != null) setState(() => _steuerJahr = y); },
            ),
          ]),
          const SizedBox(height: 16),

          // ── Arbeitgeber Info + OCR ──
          if (_arbeitgeberListe.isNotEmpty) ...[
            _sectionHeader(Icons.business, 'Arbeitgeber', Colors.teal),
            Container(
              width: double.infinity, padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(_arbeitgeberListe.first['firma']?.toString() ?? '–', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.teal.shade800)),
                if (_arbeitgeberListe.first['ort'] != null) Text(_arbeitgeberListe.first['ort'].toString(), style: TextStyle(fontSize: 12, color: Colors.teal.shade600)),
              ]),
            ),
            const SizedBox(height: 6),
            _buildOcrStatus(),
            const SizedBox(height: 16),
          ],

          // ══════════════════════════════════════════════
          // ANLAGE N — Zeilen gemäß offiziellem Vordruck
          // ══════════════════════════════════════════════

          // ── Zeilen 1–3: Kopfzeile ──
          _sectionHeader(Icons.person, 'Zeilen 1–3: Grundangaben', Colors.grey),
          Row(children: [
            Expanded(child: _zeileField(_z1NameC, 1, 'Name', isEuro: false)),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z2VornameC, 2, 'Vorname', isEuro: false)),
          ]),
          const SizedBox(height: 6),
          _zeileField(_z3SteuernummerC, 3, 'Steuernummer', isEuro: false),
          const SizedBox(height: 16),

          // ── Zeilen 4–10: Angaben zum Arbeitslohn ──
          _sectionHeader(Icons.euro, 'Zeilen 4–10: Angaben zum Arbeitslohn', Colors.red),
          _infoBox('Werte aus der Lohnsteuerbescheinigung Nr. 3–8 übernehmen', Colors.red),
          const SizedBox(height: 8),
          Row(children: [
            SizedBox(width: 160, child: DropdownButtonFormField<String>(
              initialValue: _z4Steuerklasse.isNotEmpty ? _z4Steuerklasse : null,
              decoration: InputDecoration(
                labelText: 'Z4: Steuerklasse',
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                prefixIcon: _zeileBadge(4),
                prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 0),
              ),
              items: ['I', 'II', 'III', 'IV', 'V', 'VI'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
              onChanged: (v) => setState(() => _z4Steuerklasse = v ?? ''),
            )),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z5BruttoC, 5, 'Bruttoarbeitslohn einschl. Sachbezüge (KZ 110)')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _zeileField(_z6LohnsteuerC, 6, 'Lohnsteuer (KZ 140)')),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z7SoliC, 7, 'Solidaritätszuschlag (KZ 150)')),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _zeileField(_z8KirchensteuerC, 8, 'Kirchensteuer AN (KZ 142)')),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z9KirchensteuerEheC, 9, 'Kirchensteuer Ehegatte (KZ 144)')),
          ]),
          const SizedBox(height: 16),

          // ── Zeilen 11–16: Versorgungsbezüge ──
          _expandableSection(Icons.account_balance, 'Zeilen 11–16: Versorgungsbezüge', Colors.brown, [
            _zeileField(_z11VersorgungC, 11, 'Steuerbegünstigte Versorgungsbezüge (KZ 200)'),
            const SizedBox(height: 6),
            _zeileField(_z12BemessungC, 12, 'Bemessungsgrundlage Versorgungsfreibetrag (KZ 201)'),
            const SizedBox(height: 6),
            _zeileField(_z13KalenderjahrC, 13, 'Kalenderjahr Versorgungsbeginn (KZ 206)', isEuro: false),
          ]),
          const SizedBox(height: 8),

          // ── Zeilen 17–20: Sonderfälle ──
          _expandableSection(Icons.more_horiz, 'Zeilen 17–20: Sonderfälle Arbeitslohn', Colors.teal, [
            _zeileField(_z17EntschaedigungC, 17, 'Arbeitslohn mehrere Jahre / Entschädigungen (KZ 165)'),
            const SizedBox(height: 6),
            _zeileField(_z18OhneSteuerabzugC, 18, 'Steuerpfl. Arbeitslohn ohne Steuerabzug (KZ 115)'),
            const SizedBox(height: 6),
            _zeileField(_z19AufwandsentschaedigungC, 19, 'Steuerfreie Aufwandsentschädigungen (KZ 118)'),
            const SizedBox(height: 6),
            _zeileField(_z20KurzarbeitergeldC, 20, 'Kurzarbeitergeld, Elterngeld, Krankengeld (KZ 119)'),
          ]),
          const SizedBox(height: 8),

          // ── Vorsorgeaufwand (Ergänzung aus LSB) ──
          _expandableSection(Icons.shield, 'Vorsorgeaufwand (aus LSB Nr. 22–25, für Anlage Vorsorgeaufwand)', Colors.purple, [
            _infoBox('Diese Werte gehören in die Anlage Vorsorgeaufwand, nicht in Anlage N', Colors.purple),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _zeileField(_rentenversicherungC, 22, 'Rentenversicherung AN', isEuro: true)),
              const SizedBox(width: 8),
              Expanded(child: _zeileField(_arbeitslosenversicherungC, 23, 'Arbeitslosenversicherung AN')),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Expanded(child: _zeileField(_krankenversicherungC, 24, 'Krankenversicherung AN')),
              const SizedBox(width: 8),
              Expanded(child: _zeileField(_pflegeversicherungC, 25, 'Pflegeversicherung AN')),
            ]),
          ]),
          const SizedBox(height: 16),

          // ═══════════════════════════════════════
          // WERBUNGSKOSTEN (Zeilen 27–83)
          // ═══════════════════════════════════════
          Container(
            width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(8)),
            child: Text('Werbungskosten (Zeilen 27–83)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
          ),
          const SizedBox(height: 12),

          // ── Zeilen 27–34: Entfernungspauschale (1. Angabe) ──
          _sectionHeader(Icons.directions_car, 'Zeilen 27–34: Wege Wohnung – Arbeit (1. Angabe)', Colors.orange),
          Row(children: [
            SizedBox(width: 130, child: DropdownButtonFormField<String>(
              initialValue: _z27Typ,
              decoration: InputDecoration(
                labelText: 'Z27: Typ', isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
              items: const [
                DropdownMenuItem(value: '1', child: Text('1. Tätigkeitsstätte', style: TextStyle(fontSize: 11))),
                DropdownMenuItem(value: '2', child: Text('Sammelpunkt', style: TextStyle(fontSize: 11))),
              ],
              onChanged: (v) => setState(() => _z27Typ = v ?? '1'),
            )),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z27OrtC, 27, 'PLZ, Ort und Straße', isEuro: false)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _zeileField(_z27VomC, 27, 'vom (Datum)', isEuro: false)),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z27BisC, 27, 'bis (Datum)', isEuro: false)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _zeileField(_z28ArbeitstageWocheC, 28, 'Arbeitstage/Woche', isEuro: false)),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z28UrlaubstageC, 28, 'Urlaubs-/Krankheitstage', isEuro: false)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _zeileField(_z29TageC, 29, 'aufgesucht an Tagen (KZ 110)', isEuro: false)),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z30EntfernungC, 30, 'Entfernung einfach km (KZ 111)', isEuro: false)),
          ]),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(child: _zeileField(_z31PkwKmC, 31, 'davon mit PKW km (KZ 112)', isEuro: false)),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z34OepnvC, 34, 'ÖPNV Aufwendungen (KZ 114)')),
          ]),
          if (entfernung > 0) ...[
            const SizedBox(height: 4),
            Text('  Entfernungspauschale: ${_fmtEuro(entfernung)} (erste 20 km × 0,30 €, ab 21 km × 0,38 €)',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade700, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),

          // ── Zeile 53: Berufsverbände ──
          _sectionHeader(Icons.group, 'Zeile 53: Beiträge zu Berufsverbänden', Colors.indigo),
          _zeileField(_z53BerufsverbandC, 53, 'Bezeichnung und Beitrag (KZ 310)'),
          const SizedBox(height: 16),

          // ── Zeilen 54–56: Arbeitsmittel ──
          _sectionHeader(Icons.computer, 'Zeilen 54–56: Aufwendungen für Arbeitsmittel', Colors.indigo),
          _zeileField(_z54Arbeitsmittel1C, 54, 'Arbeitsmittel 1 (Art + Betrag)'),
          const SizedBox(height: 6),
          _zeileField(_z55Arbeitsmittel2C, 55, 'Arbeitsmittel 2 (Art + Betrag)'),
          if (arbeitsmittel > 0) ...[
            const SizedBox(height: 4),
            _summeZeile(56, 'Summe Arbeitsmittel (KZ 320)', arbeitsmittel),
          ],
          const SizedBox(height: 16),

          // ── Zeile 57: Häusliches Arbeitszimmer ──
          _sectionHeader(Icons.home, 'Zeile 57: Häusliches Arbeitszimmer', Colors.indigo),
          _infoBox('Nur wenn Mittelpunkt der gesamten Tätigkeit. Jahrespauschale max 1.260 €', Colors.indigo),
          const SizedBox(height: 4),
          _zeileField(_z57ArbeitszimmerC, 57, 'Aufwendungen / Jahrespauschale (KZ 325)'),
          const SizedBox(height: 16),

          // ── Zeilen 58–59: Tagespauschale Homeoffice ──
          _sectionHeader(Icons.home_work, 'Zeilen 58–59: Tagespauschale Homeoffice', Colors.indigo),
          _infoBox('6 € pro Tag, max 210 Tage = 1.260 €. Nicht gleichzeitig mit Z57!', Colors.indigo),
          const SizedBox(height: 4),
          Row(children: [
            Expanded(child: _zeileField(_z58HomeOfficeTage1C, 58, 'Tage (anderer Arbeitsplatz vorhanden, KZ 335)', isEuro: false)),
            const SizedBox(width: 8),
            Expanded(child: _zeileField(_z59HomeOfficeTage2C, 59, 'Tage (kein anderer Arbeitsplatz, KZ 336)', isEuro: false)),
          ]),
          if (homeOffice > 0) ...[
            const SizedBox(height: 4),
            Text('  Tagespauschale: ${_fmtEuro(homeOffice)}',
                style: TextStyle(fontSize: 10, color: Colors.indigo.shade700, fontStyle: FontStyle.italic)),
          ],
          const SizedBox(height: 16),

          // ── Zeile 60: Fortbildungskosten ──
          _sectionHeader(Icons.school, 'Zeile 60: Fortbildungskosten', Colors.indigo),
          _zeileField(_z60FortbildungC, 60, 'Fortbildungskosten (KZ 330)'),
          const SizedBox(height: 16),

          // ── Zeilen 61–64: Weitere Werbungskosten ──
          _sectionHeader(Icons.more, 'Zeilen 61–64: Weitere Werbungskosten', Colors.indigo),
          _zeileField(_z61FaehrFlugC, 61, 'Fähr- und Flugkosten (Wohnung–Arbeit)'),
          const SizedBox(height: 6),
          _zeileField(_z62SonstigesC, 62, 'Sonstiges (z.B. Bewerbungskosten, Kontoführung 16 €)'),
          const SizedBox(height: 6),
          _zeileField(_z63Sonstiges2C, 63, 'Sonstiges 2'),
          if (weitereWK > 0) ...[
            const SizedBox(height: 4),
            _summeZeile(64, 'Summe weitere WK (KZ 380)', weitereWK),
          ],
          const SizedBox(height: 16),

          // ── Zeilen 65–71: Reisekosten ──
          _expandableSection(Icons.flight, 'Zeilen 65–71: Reisekosten Auswärtstätigkeit', Colors.cyan, [
            _zeileField(_z66FahrtkostenC, 66, 'Fahrtkosten'),
            const SizedBox(height: 6),
            _zeileField(_z67UebernachtungC, 67, 'Übernachtungskosten'),
            const SizedBox(height: 6),
            _zeileField(_z68ReisenebenC, 68, 'Reisenebenkosten'),
            if (_calcReisekosten() > 0) ...[
              const SizedBox(height: 4),
              _summeZeile(69, 'Gesamtsumme Reisekosten (KZ 410)', _calcReisekosten()),
            ],
            const SizedBox(height: 6),
            _zeileField(_z71ErsattReiseC, 71, 'Vom Arbeitgeber steuerfrei ersetzt (KZ 420)'),
          ]),
          const SizedBox(height: 8),

          // ── Zeilen 72–77: Verpflegungsmehraufwand ──
          _expandableSection(Icons.restaurant, 'Zeilen 72–77: Verpflegungsmehraufwand', Colors.cyan, [
            _infoBox('Inland: >8h = 14 €, An-/Abreisetag = 14 €, 24h = 28 €', Colors.cyan),
            const SizedBox(height: 8),
            _zeileField(_z72Tage8hC, 72, 'Tage >8h ohne Übernachtung (KZ 470)', isEuro: false),
            const SizedBox(height: 6),
            _zeileField(_z73AnAbreisetageC, 73, 'An- und Abreisetage (KZ 471)', isEuro: false),
            const SizedBox(height: 6),
            _zeileField(_z74Tage24hC, 74, 'Tage 24h Abwesenheit (KZ 472)', isEuro: false),
            const SizedBox(height: 6),
            _zeileField(_z75KuerzungC, 75, 'Kürzung wegen Mahlzeitengestellung (KZ 473)'),
            const SizedBox(height: 6),
            _zeileField(_z77ErsattVerpflegungC, 77, 'Vom Arbeitgeber steuerfrei ersetzt (KZ 490)'),
            if (verpflegung != 0) ...[
              const SizedBox(height: 4),
              Text('  Verpflegungsmehraufwand netto: ${_fmtEuro(verpflegung)}',
                  style: TextStyle(fontSize: 10, color: Colors.cyan.shade700, fontStyle: FontStyle.italic)),
            ],
          ]),
          const SizedBox(height: 20),

          // ═══════════════════════════════════════
          // BERECHNUNG WERBUNGSKOSTEN
          // ═══════════════════════════════════════
          Container(
            width: double.infinity, padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.orange.shade200)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Berechnung Werbungskosten', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800)),
              const SizedBox(height: 8),
              if (entfernung > 0) _calcRow('Entfernungspauschale (Z27–34)', entfernung),
              if (oepnv > 0) _calcRow('ÖPNV-Kosten (Z34)', oepnv),
              if (berufsverband > 0) _calcRow('Berufsverbände (Z53)', berufsverband),
              if (arbeitsmittel > 0) _calcRow('Arbeitsmittel (Z54–56)', arbeitsmittel),
              if (arbeitszimmer > 0) _calcRow('Arbeitszimmer (Z57)', arbeitszimmer),
              if (homeOffice > 0) _calcRow('Home-Office (Z58–59)', homeOffice),
              if (fortbildung > 0) _calcRow('Fortbildung (Z60)', fortbildung),
              if (weitereWK > 0) _calcRow('Weitere WK (Z61–64)', weitereWK),
              if (reisekostenNetto > 0) _calcRow('Reisekosten netto (Z65–71)', reisekostenNetto),
              if (verpflegung > 0) _calcRow('Verpflegung (Z72–77)', verpflegung),
              const Divider(height: 12),
              _calcRow('Summe Werbungskosten', werbungskosten, bold: true),
              if (werbungskosten < pauschbetrag)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('Arbeitnehmer-Pauschbetrag (${pauschbetrag.toInt()} €) wird angesetzt.', style: TextStyle(fontSize: 9, color: Colors.orange.shade600, fontStyle: FontStyle.italic)),
                ),
            ]),
          ),
          const SizedBox(height: 16),

          // ═══════════════════════════════════════
          // ZUSAMMENFASSUNG
          // ═══════════════════════════════════════
          _sectionHeader(Icons.summarize, 'Zusammenfassung', Colors.green),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [Colors.green.shade50, Colors.green.shade100]),
              borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.green.shade300),
            ),
            child: Column(children: [
              _summaryRow('Bruttoarbeitslohn (Z5)', brutto),
              _summaryRow('- Werbungskosten', -abzug),
              const Divider(height: 12),
              _summaryRow('= zu versteuerndes Einkommen (ca.)', zvE, bold: true),
              const SizedBox(height: 8),
              _summaryRow('Gezahlte Lohnsteuer (Z6)', _parseEuro(_z6LohnsteuerC.text)),
              _summaryRow('Gezahlter Soli (Z7)', _parseEuro(_z7SoliC.text)),
              _summaryRow('Gezahlte Kirchensteuer (Z8)', _parseEuro(_z8KirchensteuerC.text)),
            ]),
          ),
          const SizedBox(height: 20),

          // ═══════════════════════════════════════
          // EXPORT BUTTONS
          // ═══════════════════════════════════════
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            ElevatedButton.icon(
              onPressed: () {
                final text = 'Anlage N $_steuerJahr\n'
                    'Name: ${_z2VornameC.text} ${_z1NameC.text}\n'
                    'Steuernummer: ${_z3SteuernummerC.text}\n'
                    'Steuerklasse: $_z4Steuerklasse\n\n'
                    'Z5 Bruttoarbeitslohn: ${_z5BruttoC.text} €\n'
                    'Z6 Lohnsteuer: ${_z6LohnsteuerC.text} €\n'
                    'Z7 Soli: ${_z7SoliC.text} €\n'
                    'Z8 Kirchensteuer: ${_z8KirchensteuerC.text} €\n\n'
                    'Werbungskosten: ${werbungskosten.toStringAsFixed(2)} €\n'
                    'zvE (ca.): ${zvE.toStringAsFixed(2)} €';
                ClipboardHelper.copy(context, text, 'Steuererklärung');
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('Kopieren', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.grey.shade600, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _generateElsterXml,
              icon: const Icon(Icons.code, size: 16),
              label: const Text('XML für ELSTER exportieren', style: TextStyle(fontSize: 12)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.indigo.shade700, foregroundColor: Colors.white),
            ),
          ]),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════
  // HELPER WIDGETS
  // ═══════════════════════════════════════

  Widget _buildOcrStatus() {
    if (_lsbDokumente.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.green.shade300)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
            const SizedBox(width: 6),
            Expanded(child: Text('${_lsbDokumente.length} Lohnsteuerbescheinigung(en) vorhanden', style: TextStyle(fontSize: 11, color: Colors.green.shade700))),
            ElevatedButton.icon(
              onPressed: _isOcrRunning ? null : () => _runOcr(),
              icon: _isOcrRunning
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.document_scanner, size: 14),
              label: Text(_isOcrRunning ? 'Wird erkannt...' : 'Daten extrahieren (OCR)', style: const TextStyle(fontSize: 11)),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple.shade600, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), minimumSize: Size.zero),
            ),
          ]),
          if (_ocrError.isNotEmpty) ...[const SizedBox(height: 4), Text(_ocrError, style: TextStyle(fontSize: 10, color: Colors.red.shade600))],
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade300)),
      child: Row(children: [
        Icon(Icons.warning_amber, size: 16, color: Colors.orange.shade700),
        const SizedBox(width: 6),
        Expanded(child: Text('Keine Lohnsteuerbescheinigung. Bitte unter Arbeitgeber → Lohn hochladen.', style: TextStyle(fontSize: 11, color: Colors.orange.shade700))),
      ]),
    );
  }

  Widget _sectionHeader(IconData icon, String title, MaterialColor color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(children: [
        Icon(icon, size: 18, color: color.shade700),
        const SizedBox(width: 8),
        Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
      ]),
    );
  }

  Widget _zeileBadge(int zeile) {
    return Container(
      width: 42, alignment: Alignment.center,
      child: Text('$zeile', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
    );
  }

  Widget _zeileField(TextEditingController controller, int zeile, String label, {bool isEuro = true}) {
    return TextFormField(
      controller: controller,
      keyboardType: isEuro ? const TextInputType.numberWithOptions(decimal: true) : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: _zeileBadge(zeile),
        prefixIconConstraints: const BoxConstraints(minWidth: 42, minHeight: 0),
        suffixText: isEuro ? '€' : null,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400)),
      ),
      style: const TextStyle(fontSize: 13),
      onChanged: (_) => setState(() {}),
    );
  }

  Widget _infoBox(String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: color.shade50, borderRadius: BorderRadius.circular(6)),
      child: Text(text, style: TextStyle(fontSize: 10, color: color.shade600, fontStyle: FontStyle.italic)),
    );
  }

  Widget _summeZeile(int zeile, String label, double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
      child: Row(children: [
        Text('Z$zeile', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
        const SizedBox(width: 8),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 11))),
        Text(_fmtEuro(value), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade700)),
      ]),
    );
  }

  Widget _expandableSection(IconData icon, String title, MaterialColor color, List<Widget> children) {
    return ExpansionTile(
      leading: Icon(icon, size: 18, color: color.shade700),
      title: Text(title, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color.shade800)),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: children,
    );
  }

  Widget _calcRow(String label, double value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 11, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: Colors.orange.shade800))),
        Text(_fmtEuro(value), style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: Colors.orange.shade900)),
      ]),
    );
  }

  Widget _summaryRow(String label, double value, {bool bold = false}) {
    final isNeg = value < 0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(children: [
        Expanded(child: Text(label, style: TextStyle(fontSize: 12, fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: Colors.green.shade800))),
        Text('${isNeg ? '- ' : ''}${_fmtEuro(value.abs())}', style: TextStyle(fontSize: 13, fontWeight: bold ? FontWeight.bold : FontWeight.w500, color: Colors.green.shade900)),
      ]),
    );
  }
}
