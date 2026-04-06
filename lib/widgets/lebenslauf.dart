import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:intl/intl.dart';
import '../services/api_service.dart';
import 'file_viewer_dialog.dart';

/// ATS-optimized Lebenslauf (CV) generator
/// Simple layout, standard fonts, no icons/images, standard section headings
class LebenslaufGenerator {
  static Future<void> generate(BuildContext context, ApiService apiService, int userId) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: Card(
        child: Padding(padding: EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
          CircularProgressIndicator(),
          SizedBox(height: 12),
          Text('Lebenslauf wird erstellt...', style: TextStyle(fontSize: 14)),
        ])),
      )),
    );

    try {
      // Load fonts
      final fontData = await rootBundle.load('assets/fonts/DejaVuSans.ttf');
      final fontBoldData = await rootBundle.load('assets/fonts/DejaVuSans-Bold.ttf');
      final ttf = pw.Font.ttf(fontData);
      final ttfBold = pw.Font.ttf(fontBoldData);

      // Load all data
      final results = await Future.wait([
        apiService.getUserDetails(userId),
        apiService.getBerufserfahrung(userId),
        apiService.getUserSchulbildung(userId),
        apiService.getUserQualifikationen(userId),
      ]);

      final userData = results[0]['success'] == true ? (results[0]['user'] ?? {}) : {};
      final berufserfahrung = results[1]['success'] == true ? List<Map<String, dynamic>>.from(results[1]['data'] ?? []) : <Map<String, dynamic>>[];
      final schulbildung = results[2]['success'] == true ? List<Map<String, dynamic>>.from(results[2]['data'] ?? []) : <Map<String, dynamic>>[];
      final qualifikationen = results[3];
      final fuehrerschein = qualifikationen['success'] == true ? List<Map<String, dynamic>>.from(qualifikationen['fuehrerschein'] ?? []) : <Map<String, dynamic>>[];
      final sprachen = qualifikationen['success'] == true ? List<Map<String, dynamic>>.from(qualifikationen['sprachen'] ?? []) : <Map<String, dynamic>>[];

      // Clean invisible Unicode characters
      String clean(String? s) => (s ?? '').replaceAll(RegExp(r'[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]'), '').trim();

      // Personal data
      final vorname = clean(userData['vorname']);
      final nachname = clean(userData['nachname']);
      final fullName = '$vorname $nachname'.trim();
      final geburtsdatum = clean(userData['geburtsdatum']);
      final geburtsort = clean(userData['geburtsort']);
      final strasse = clean(userData['strasse']);
      final hausnummer = clean(userData['hausnummer']);
      final plz = clean(userData['plz']);
      final ort = clean(userData['ort']);
      final telefon = clean(userData['telefon_mobil']?.toString().isNotEmpty == true ? userData['telefon_mobil'] : userData['telefon_fix']);
      final email = clean(userData['email']);
      final familienstand = clean(userData['familienstand']);
      final geschlecht = clean(userData['geschlecht']);
      final staatsangehoerigkeit = clean(userData['staatsangehoerigkeit']);

      String formatDate(String datum) {
        if (datum.isEmpty) return '';
        try {
          final d = DateTime.parse(datum);
          return DateFormat('dd.MM.yyyy').format(d);
        } catch (_) { return datum; }
      }

      String adresse() {
        final parts = <String>[];
        if (strasse.isNotEmpty) parts.add('$strasse${hausnummer.isNotEmpty ? ' $hausnummer' : ''}');
        if (plz.isNotEmpty || ort.isNotEmpty) parts.add('$plz $ort'.trim());
        return parts.join(', ');
      }

      String familienstandLabel(String fs) {
        const labels = {
          'ledig': 'Ledig',
          'verheiratet': 'Verheiratet',
          'eingetragene_lebenspartnerschaft': 'Eingetragene Lebenspartnerschaft',
          'geschieden': 'Geschieden',
          'verwitwet': 'Verwitwet',
          'getrennt_lebend': 'Getrennt lebend',
          'eheaehnliche_gemeinschaft': 'Eheähnliche Gemeinschaft',
        };
        return labels[fs] ?? fs;
      }

      String geschlechtLabel(String g) {
        if (g == 'M') return 'Männlich';
        if (g == 'W') return 'Weiblich';
        if (g == 'D') return 'Divers';
        return g;
      }

      // ATS-optimized colors
      final darkColor = PdfColor.fromHex('#333333');
      final greyColor = PdfColor.fromHex('#666666');
      final lineColor = PdfColor.fromHex('#cccccc');

      final pdf = pw.Document(
        theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
      );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.symmetric(horizontal: 50, vertical: 40),
          build: (pw.Context ctx) {
            return [
              // === NAME (large, bold, top) ===
              pw.Text(
                fullName.isNotEmpty ? fullName : 'Lebenslauf',
                style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold, color: darkColor),
              ),
              pw.SizedBox(height: 4),
              pw.Container(height: 2, color: darkColor),
              pw.SizedBox(height: 16),

              // === PERSÖNLICHE DATEN ===
              _sectionTitle('PERSÖNLICHE DATEN', darkColor),
              _dataRow('Adresse', adresse(), greyColor),
              _dataRow('Telefon', telefon, greyColor),
              _dataRow('E-Mail', email, greyColor),
              _dataRow('Geburtsdatum', formatDate(geburtsdatum), greyColor),
              _dataRow('Geburtsort', geburtsort, greyColor),
              _dataRow('Staatsangehörigkeit', staatsangehoerigkeit, greyColor),
              _dataRow('Familienstand', familienstandLabel(familienstand), greyColor),
              _dataRow('Geschlecht', geschlechtLabel(geschlecht), greyColor),
              if (fuehrerschein.isNotEmpty) ...[
                if (fuehrerschein.any((f) => (f['klasse'] ?? '').toString().toLowerCase() == 'keinen'))
                  _dataRow('Führerschein', 'Keinen', greyColor)
                else
                  _dataRow('Führerschein', fuehrerschein.map((f) => 'Klasse ${clean(f['klasse'])}').join(', '), greyColor),
              ],
              pw.SizedBox(height: 16),

              // === BERUFSERFAHRUNG ===
              if (berufserfahrung.isNotEmpty) ...[
                _sectionTitle('BERUFSERFAHRUNG', darkColor),
                ...berufserfahrung.map((be) {
                  final firma = clean(be['firma']);
                  final funktion = clean(be['funktion'] ?? be['position']);
                  final beOrt = clean(be['ort']);
                  final vonM = clean(be['von_monat']);
                  final vonJ = clean(be['von_jahr']);
                  final bisM = clean(be['bis_monat']);
                  final bisJ = clean(be['bis_jahr']);
                  final von = vonM.isNotEmpty && vonJ.isNotEmpty ? '$vonM/$vonJ' : '';
                  final bis = bisM.isNotEmpty && bisJ.isNotEmpty ? '$bisM/$bisJ' : 'heute';
                  final zeitraum = von.isNotEmpty ? '$von - $bis' : '';
                  final aufgaben = <String>[
                    if (clean(be['aufgabe1']).isNotEmpty) clean(be['aufgabe1']),
                    if (clean(be['aufgabe2']).isNotEmpty) clean(be['aufgabe2']),
                    if (clean(be['aufgabe3']).isNotEmpty) clean(be['aufgabe3']),
                  ];

                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 10),
                    child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      // Date range on the left, job title bold
                      pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.SizedBox(
                          width: 120,
                          child: pw.Text(zeitraum, style: pw.TextStyle(fontSize: 10, color: greyColor)),
                        ),
                        pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                          // Job title first (ATS priority)
                          if (funktion.isNotEmpty)
                            pw.Text(funktion, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: darkColor)),
                          // Company + Location
                          pw.Text(
                            '$firma${beOrt.isNotEmpty ? ', $beOrt' : ''}',
                            style: pw.TextStyle(fontSize: 10, color: greyColor),
                          ),
                          // Tasks as bullet points
                          if (aufgaben.isNotEmpty) ...[
                            pw.SizedBox(height: 3),
                            ...aufgaben.map((a) => pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 1),
                              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                                pw.Text('- ', style: pw.TextStyle(fontSize: 10, color: darkColor)),
                                pw.Expanded(child: pw.Text(a, style: const pw.TextStyle(fontSize: 10))),
                              ]),
                            )),
                          ],
                        ])),
                      ]),
                    ]),
                  );
                }),
                pw.SizedBox(height: 12),
              ],

              // === SCHULBILDUNG / AUSBILDUNG ===
              if (schulbildung.isNotEmpty) ...[
                _sectionTitle('SCHULBILDUNG', darkColor),
                ...schulbildung.map((sc) {
                  final name = clean(sc['schul_name']);
                  final art = clean(sc['schulart']);
                  final scOrt = clean(sc['schul_plz_ort']);
                  final klasse = clean(sc['klasse']);
                  // Convert DD.MM.YYYY to MM/YYYY for compact display
                  String toShort(String d) {
                    if (d.isEmpty) return '';
                    final parts = d.split('.');
                    if (parts.length == 3) return '${parts[1]}/${parts[2]}';
                    return d;
                  }
                  final beginn = toShort(clean(sc['schul_beginn']));
                  final ende = toShort(clean(sc['schul_ende']));
                  final zeitraum = beginn.isNotEmpty ? '$beginn - ${ende.isNotEmpty ? ende : 'heute'}' : '';

                  return pw.Container(
                    margin: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                      pw.SizedBox(
                        width: 120,
                        child: pw.Text(zeitraum, style: pw.TextStyle(fontSize: 10, color: greyColor)),
                      ),
                      pw.Expanded(child: pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                        pw.Text(name, style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold, color: darkColor)),
                        if (art.isNotEmpty) pw.Text(art, style: pw.TextStyle(fontSize: 10, color: greyColor)),
                        if (scOrt.isNotEmpty) pw.Text(scOrt, style: pw.TextStyle(fontSize: 10, color: greyColor)),
                        if (klasse.isNotEmpty) pw.Text('Klasse: $klasse', style: pw.TextStyle(fontSize: 10, color: greyColor)),
                      ])),
                    ]),
                  );
                }),
                pw.SizedBox(height: 12),
              ],

              // === SPRACHKENNTNISSE ===
              if (sprachen.isNotEmpty) ...[
                _sectionTitle('SPRACHKENNTNISSE', darkColor),
                ...sprachen.map((sp) {
                  final sprache = clean(sp['sprache']);
                  final niveau = clean(sp['niveau']);
                  return pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 3),
                    child: pw.Row(children: [
                      pw.SizedBox(width: 120, child: pw.Text(sprache, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold))),
                      pw.Text(niveau, style: pw.TextStyle(fontSize: 10, color: greyColor)),
                    ]),
                  );
                }),
                pw.SizedBox(height: 12),
              ],

              // === FÜHRERSCHEIN (if not already shown above) ===
              // Already shown in Persönliche Daten

              // === ORT UND DATUM ===
              pw.SizedBox(height: 24),
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border(top: pw.BorderSide(color: lineColor))),
                padding: const pw.EdgeInsets.only(top: 8),
                child: pw.Text(
                  '${ort.isNotEmpty ? ort : ''}, ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                  style: pw.TextStyle(fontSize: 10, color: greyColor),
                ),
              ),
            ];
          },
        ),
      );

      // Save PDF
      final dir = await getTemporaryDirectory();
      final fileName = 'Lebenslauf_${nachname}_$vorname.pdf'.replaceAll(' ', '_');
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(await pdf.save());

      if (context.mounted) {
        Navigator.pop(context); // Close loading dialog
        final handled = await FileViewerDialog.show(context, file.path, fileName);
        if (!handled && context.mounted) {
          await OpenFilex.open(file.path);
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fehler: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      // Ensure loading dialog is always closed, even on unexpected errors
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
    }
  }

  /// ATS-friendly section title with underline
  static pw.Widget _sectionTitle(String title, PdfColor color) {
    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 6),
      decoration: pw.BoxDecoration(border: pw.Border(bottom: pw.BorderSide(color: color, width: 1))),
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Text(title, style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color, letterSpacing: 1)),
    );
  }

  /// Simple data row: label + value
  static pw.Widget _dataRow(String label, String? value, PdfColor greyColor) {
    if (value == null || value.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 3),
      child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
        pw.SizedBox(width: 140, child: pw.Text(label, style: pw.TextStyle(fontSize: 10, color: greyColor))),
        pw.Expanded(child: pw.Text(value, style: const pw.TextStyle(fontSize: 10))),
      ]),
    );
  }

  /// Modal with tabs: Generate + Quality Check
  static void showLebenslaufDialog(BuildContext context, ApiService apiService, int userId) {
    showDialog(
      context: context,
      builder: (ctx) {
        return _LebenslaufDialog(apiService: apiService, userId: userId, parentContext: context);
      },
    );
  }
}

class _LebenslaufDialog extends StatefulWidget {
  final ApiService apiService;
  final int userId;
  final BuildContext parentContext;
  const _LebenslaufDialog({required this.apiService, required this.userId, required this.parentContext});
  @override
  State<_LebenslaufDialog> createState() => _LebenslaufDialogState();
}

class _LebenslaufDialogState extends State<_LebenslaufDialog> {
  Map<String, dynamic> _userData = {};
  List<Map<String, dynamic>> _berufserfahrung = [];
  List<Map<String, dynamic>> _schulbildung = [];
  List<Map<String, dynamic>> _fuehrerschein = [];
  List<Map<String, dynamic>> _sprachen = [];
  bool _loaded = false;
  List<_QualityCheck> _checks = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        widget.apiService.getUserDetails(widget.userId),
        widget.apiService.getBerufserfahrung(widget.userId),
        widget.apiService.getUserSchulbildung(widget.userId),
        widget.apiService.getUserQualifikationen(widget.userId),
      ]);
      if (mounted) {
        setState(() {
          _userData = results[0]['success'] == true ? (results[0]['user'] ?? {}) : {};
          _berufserfahrung = results[1]['success'] == true ? List<Map<String, dynamic>>.from(results[1]['data'] ?? []) : [];
          _schulbildung = results[2]['success'] == true ? List<Map<String, dynamic>>.from(results[2]['data'] ?? []) : [];
          final q = results[3];
          _fuehrerschein = q['success'] == true ? List<Map<String, dynamic>>.from(q['fuehrerschein'] ?? []) : [];
          _sprachen = q['success'] == true ? List<Map<String, dynamic>>.from(q['sprachen'] ?? []) : [];
          _loaded = true;
          _runQualityChecks();
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  void _runQualityChecks() {
    final checks = <_QualityCheck>[];
    final u = _userData;

    // 1. Persönliche Daten vollständig
    final hasName = (u['vorname'] ?? '').toString().isNotEmpty && (u['nachname'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Vollständiger Name (Vor- und Nachname)', hasName, hasName ? 'Name ist vorhanden' : 'Vorname oder Nachname fehlt'));

    // 2. Kontaktdaten
    final hasKontakt = (u['email'] ?? '').toString().isNotEmpty && ((u['telefon_mobil'] ?? '').toString().isNotEmpty || (u['telefon_fix'] ?? '').toString().isNotEmpty);
    checks.add(_QualityCheck('Kontaktdaten (E-Mail + Telefon)', hasKontakt, hasKontakt ? 'E-Mail und Telefon vorhanden' : 'E-Mail oder Telefonnummer fehlt'));

    // 3. Adresse vollständig
    final hasAdresse = (u['strasse'] ?? '').toString().isNotEmpty && (u['plz'] ?? '').toString().isNotEmpty && (u['ort'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Vollständige Adresse', hasAdresse, hasAdresse ? 'Straße, PLZ und Ort vorhanden' : 'Adresse unvollständig (Straße, PLZ oder Ort fehlt)'));

    // 4. Geburtsdatum
    final hasGeburt = (u['geburtsdatum'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Geburtsdatum angegeben', hasGeburt, hasGeburt ? 'Geburtsdatum vorhanden' : 'Geburtsdatum fehlt — in Deutschland üblich'));

    // 5. Berufserfahrung vorhanden
    final hasBeruf = _berufserfahrung.isNotEmpty;
    checks.add(_QualityCheck('Mindestens eine Berufserfahrung', hasBeruf, hasBeruf ? '${_berufserfahrung.length} Berufserfahrung(en) vorhanden' : 'Keine Berufserfahrung eingetragen'));

    // 6. Aufgaben bei Berufserfahrung
    final berufeOhneAufgaben = _berufserfahrung.where((be) =>
      (be['aufgabe1'] ?? '').toString().isEmpty &&
      (be['aufgabe2'] ?? '').toString().isEmpty &&
      (be['aufgabe3'] ?? '').toString().isEmpty
    ).toList();
    final hasAufgaben = berufeOhneAufgaben.isEmpty && hasBeruf;
    checks.add(_QualityCheck('Tätigkeiten bei allen Berufserfahrungen', hasAufgaben, hasAufgaben ? 'Alle Berufserfahrungen haben Aufgaben' : '${berufeOhneAufgaben.length} Berufserfahrung(en) ohne Aufgaben/Tätigkeiten'));

    // 7. Schulbildung vorhanden
    final hasSchule = _schulbildung.isNotEmpty;
    checks.add(_QualityCheck('Schulbildung angegeben', hasSchule, hasSchule ? '${_schulbildung.length} Schulbildung(en) vorhanden' : 'Keine Schulbildung eingetragen'));

    // 8. Sprachkenntnisse
    final hasSprachen = _sprachen.isNotEmpty;
    checks.add(_QualityCheck('Sprachkenntnisse angegeben', hasSprachen, hasSprachen ? '${_sprachen.length} Sprache(n) vorhanden' : 'Keine Sprachkenntnisse eingetragen'));

    // 9. Lücken & Überlappungen im Lebenslauf
    bool hasProbleme = false;
    final lueckenDetails = <String>[];

    if (_berufserfahrung.isNotEmpty) {
      // Convert all jobs to month-ranges for comparison, sort chronologically
      final jobs = <Map<String, dynamic>>[];
      for (final be in _berufserfahrung) {
        final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
        final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
        final bisM = int.tryParse(be['bis_monat']?.toString() ?? '') ?? 0;
        final bisJ = int.tryParse(be['bis_jahr']?.toString() ?? '') ?? 0;
        final isAktuell = be['aktuell'] == true || be['aktuell'] == 1 || be['aktuell'] == '1' || (bisM == 0 && bisJ == 0);
        if (vonJ > 0) {
          final now = DateTime.now();
          jobs.add({
            'firma': be['firma'] ?? '?',
            'von': vonJ * 12 + vonM,
            'bis': isAktuell ? now.year * 12 + now.month : (bisJ > 0 ? bisJ * 12 + bisM : vonJ * 12 + vonM),
            'aktuell': isAktuell,
            'vonLabel': '${vonM.toString().padLeft(2, '0')}/$vonJ',
            'bisLabel': isAktuell ? 'heute' : '${bisM.toString().padLeft(2, '0')}/$bisJ',
          });
        }
      }

      // Sort by start date (chronological)
      jobs.sort((a, b) => (a['von'] as int).compareTo(b['von'] as int));

      // Check gaps > 1 month between consecutive jobs
      for (int i = 0; i < jobs.length - 1; i++) {
        final currentEnd = jobs[i]['bis'] as int;
        final nextStart = jobs[i + 1]['von'] as int;
        final gap = nextStart - currentEnd;
        if (gap > 1) {
          hasProbleme = true;
          lueckenDetails.add('Lücke: ~$gap Monate zwischen ${jobs[i]['firma']} (bis ${jobs[i]['bisLabel']}) und ${jobs[i + 1]['firma']} (ab ${jobs[i + 1]['vonLabel']})');
        }
      }

      // Check overlaps
      for (int i = 0; i < jobs.length - 1; i++) {
        final currentEnd = jobs[i]['bis'] as int;
        final nextStart = jobs[i + 1]['von'] as int;
        if (currentEnd > nextStart) {
          final overlap = currentEnd - nextStart;
          hasProbleme = true;
          lueckenDetails.add('Überlappung: ~$overlap Monate zwischen ${jobs[i]['firma']} und ${jobs[i + 1]['firma']}');
        }
      }

      // Check if currently unemployed
      final hasAktuellenJob = jobs.any((j) => j['aktuell'] == true);
      if (!hasAktuellenJob && jobs.isNotEmpty) {
        final lastEnd = jobs.last['bis'] as int;
        final now = DateTime.now().year * 12 + DateTime.now().month;
        final gap = now - lastEnd;
        if (gap > 1) {
          hasProbleme = true;
          lueckenDetails.add('Aktuell ~$gap Monate ohne Beschäftigung seit ${jobs.last['firma']} (${jobs.last['bisLabel']}) — als "arbeitssuchend" oder "in Weiterbildung" angeben');
        }
      }
    }

    final lueckenText = hasProbleme ? lueckenDetails.join('\n') : 'Keine Lücken oder Überlappungen erkannt';
    checks.add(_QualityCheck('Keine Lücken im Lebenslauf', !hasProbleme, lueckenText));

    // 10. Führerschein (optional aber empfohlen für Helfer)
    final hasFS = _fuehrerschein.isNotEmpty;
    checks.add(_QualityCheck('Führerschein angegeben', hasFS, hasFS ? 'Führerschein: ${_fuehrerschein.map((f) => 'Klasse ${f['klasse']}').join(', ')}' : 'Kein Führerschein angegeben — für viele Helferstellen relevant'));

    // 11. Staatsangehörigkeit angegeben
    final hasStaat = (u['staatsangehoerigkeit'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Staatsangehörigkeit angegeben', hasStaat, hasStaat ? 'Staatsangehörigkeit: ${u['staatsangehoerigkeit']}' : 'Staatsangehörigkeit fehlt — relevant für Arbeitserlaubnis'));

    // 12. Berufsbezeichnung / Position bei allen Jobs
    final berufeOhnePosition = _berufserfahrung.where((be) =>
      (be['funktion'] ?? be['position'] ?? '').toString().isEmpty
    ).toList();
    final hasAllePositionen = berufeOhnePosition.isEmpty && hasBeruf;
    checks.add(_QualityCheck('Position bei allen Berufserfahrungen', hasAllePositionen, hasAllePositionen ? 'Alle Jobs haben eine Berufsbezeichnung' : '${berufeOhnePosition.length} Job(s) ohne Position/Berufsbezeichnung'));

    // 13. Zeiträume vollständig (von_monat + von_jahr bei jedem Job)
    final berufeOhneZeitraum = _berufserfahrung.where((be) =>
      (be['von_monat'] ?? '').toString().isEmpty || (be['von_jahr'] ?? '').toString().isEmpty
    ).toList();
    final hasAlleZeitraeume = berufeOhneZeitraum.isEmpty && hasBeruf;
    checks.add(_QualityCheck('Zeiträume bei allen Jobs vollständig', hasAlleZeitraeume, hasAlleZeitraeume ? 'Alle Jobs haben Von-Datum (Monat/Jahr)' : '${berufeOhneZeitraum.length} Job(s) ohne vollständigen Zeitraum — Recruiter werten das negativ'));

    // 14. Professionelle E-Mail-Adresse (keine Spitznamen)
    final emailStr = (u['email'] ?? '').toString().toLowerCase();
    final unprofEmail = emailStr.contains('69') || emailStr.contains('420') || emailStr.contains('sexy') || emailStr.contains('baby') || emailStr.contains('cool') || emailStr.contains('killer') || emailStr.contains('mausi') || emailStr.contains('hase') || emailStr.contains('schnucki');
    final hasProfEmail = emailStr.isNotEmpty && !unprofEmail;
    checks.add(_QualityCheck('Professionelle E-Mail-Adresse', hasProfEmail, hasProfEmail ? 'E-Mail wirkt professionell' : unprofEmail ? 'E-Mail enthält unprofessionelle Begriffe — vorname.nachname@... empfohlen' : 'Keine E-Mail-Adresse angegeben'));

    // 15. Mindestens 2 Sprachen (für Migranten in Deutschland)
    final hasZweiSprachen = _sprachen.length >= 2;
    checks.add(_QualityCheck('Mindestens 2 Sprachen angegeben', hasZweiSprachen, hasZweiSprachen ? '${_sprachen.length} Sprachen angegeben' : 'Nur ${_sprachen.length} Sprache(n) — Deutsch + Muttersprache empfohlen'));

    // 16. Deutsch als Sprache vorhanden
    final hasDeutsch = _sprachen.any((s) => (s['sprache'] ?? '').toString().toLowerCase().contains('deutsch'));
    checks.add(_QualityCheck('Deutsch als Sprache angegeben', hasDeutsch, hasDeutsch ? 'Deutsch ist eingetragen' : 'Deutsch fehlt in den Sprachkenntnissen — unbedingt hinzufügen'));

    // 17. Ort bei Berufserfahrung angegeben
    final berufeOhneOrt = _berufserfahrung.where((be) => (be['ort'] ?? '').toString().isEmpty).toList();
    final hasAlleOrte = berufeOhneOrt.isEmpty && hasBeruf;
    checks.add(_QualityCheck('Arbeitsort bei allen Jobs', hasAlleOrte, hasAlleOrte ? 'Alle Jobs haben einen Ort' : '${berufeOhneOrt.length} Job(s) ohne Ort — Recruiter möchten den Standort sehen'));

    // 18. Mindestens 3 Aufgaben beim aktuellsten Job
    bool hasGenugAufgabenAktuell = false;
    if (_berufserfahrung.isNotEmpty) {
      final aktuellster = _berufserfahrung.first; // sorted newest first
      final aufgabenCount = [
        if ((aktuellster['aufgabe1'] ?? '').toString().isNotEmpty) 1,
        if ((aktuellster['aufgabe2'] ?? '').toString().isNotEmpty) 1,
        if ((aktuellster['aufgabe3'] ?? '').toString().isNotEmpty) 1,
      ].length;
      hasGenugAufgabenAktuell = aufgabenCount >= 3;
    }
    checks.add(_QualityCheck('3 Aufgaben beim aktuellsten Job', hasGenugAufgabenAktuell, hasGenugAufgabenAktuell ? 'Aktuellster Job hat 3 Aufgaben' : 'Aktuellster Job hat weniger als 3 Aufgaben — Recruiter erwarten detaillierte Tätigkeitsbeschreibung'));

    // 19. Schulbildung mit Zeitraum
    final schulenOhneZeitraum = _schulbildung.where((sc) => (sc['schul_beginn'] ?? '').toString().isEmpty).toList();
    final hasSchulZeitraum = schulenOhneZeitraum.isEmpty && hasSchule;
    checks.add(_QualityCheck('Schulbildung mit Zeitraum', hasSchulZeitraum, hasSchulZeitraum ? 'Alle Schulen haben einen Zeitraum' : '${schulenOhneZeitraum.length} Schule(n) ohne Zeitraum — Schulbeginn und -ende angeben'));

    // 20. Geburtsort angegeben
    final hasGeburtsort = (u['geburtsort'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Geburtsort angegeben', hasGeburtsort, hasGeburtsort ? 'Geburtsort: ${u['geburtsort']}' : 'Geburtsort fehlt — in Deutschland noch üblich'));

    // 21. Hausnummer bei Adresse
    final hasHausnummer = (u['hausnummer'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Hausnummer bei Adresse', hasHausnummer, hasHausnummer ? 'Hausnummer vorhanden' : 'Hausnummer fehlt — Adresse unvollständig'));

    // 22. Geschlecht angegeben
    final hasGeschlecht = (u['geschlecht'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Geschlecht angegeben', hasGeschlecht, hasGeschlecht ? 'Geschlecht: ${u['geschlecht'] == 'M' ? 'Männlich' : u['geschlecht'] == 'W' ? 'Weiblich' : u['geschlecht']}' : 'Geschlecht fehlt'));

    // 23. Berufserfahrung > 0 Monate (kein leerer Zeitraum)
    final berufeOhneDauer = _berufserfahrung.where((be) {
      final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      final bisM = int.tryParse(be['bis_monat']?.toString() ?? '') ?? 0;
      final bisJ = int.tryParse(be['bis_jahr']?.toString() ?? '') ?? 0;
      if (vonJ > 0 && bisJ > 0) {
        final von = vonJ * 12 + vonM;
        final bis = bisJ * 12 + bisM;
        return bis < von; // Ende vor Anfang
      }
      return false;
    }).toList();
    final hasKorrekteDauer = berufeOhneDauer.isEmpty;
    checks.add(_QualityCheck('Korrekte Zeiträume (Ende nach Anfang)', hasKorrekteDauer, hasKorrekteDauer ? 'Alle Zeiträume sind logisch korrekt' : '${berufeOhneDauer.length} Job(s) mit Ende vor Anfang — bitte korrigieren'));

    // 24. Mindestens 1 Jahr Berufserfahrung insgesamt
    int gesamtMonate = 0;
    for (final be in _berufserfahrung) {
      final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      final bisM = int.tryParse(be['bis_monat']?.toString() ?? '') ?? 0;
      final bisJ = int.tryParse(be['bis_jahr']?.toString() ?? '') ?? 0;
      final isAktuell = be['aktuell'] == true || be['aktuell'] == 1 || be['aktuell'] == '1';
      if (vonJ > 0) {
        final von = vonJ * 12 + vonM;
        final bis = isAktuell ? DateTime.now().year * 12 + DateTime.now().month : (bisJ > 0 ? bisJ * 12 + bisM : von);
        gesamtMonate += (bis - von).abs();
      }
    }
    final hasGenugErfahrung = gesamtMonate >= 12;
    final jahre = gesamtMonate ~/ 12;
    final restMonate = gesamtMonate % 12;
    checks.add(_QualityCheck('Mindestens 1 Jahr Berufserfahrung', hasGenugErfahrung, hasGenugErfahrung ? 'Gesamt: $jahre Jahr(e) $restMonate Monat(e) Berufserfahrung' : 'Nur $gesamtMonate Monat(e) Erfahrung — mehr Berufserfahrung empfohlen'));

    // 25. Firmenname bei allen Jobs vorhanden
    final berufeOhneFirma = _berufserfahrung.where((be) => (be['firma'] ?? '').toString().isEmpty).toList();
    final hasAlleFirmen = berufeOhneFirma.isEmpty && hasBeruf;
    checks.add(_QualityCheck('Firmenname bei allen Jobs', hasAlleFirmen, hasAlleFirmen ? 'Alle Jobs haben einen Firmennamen' : '${berufeOhneFirma.length} Job(s) ohne Firmenname'));

    // 26. Keine zu kurzen Beschäftigungen (< 3 Monate = Probezeit-Risiko)
    final kurzJobs = _berufserfahrung.where((be) {
      final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      final bisM = int.tryParse(be['bis_monat']?.toString() ?? '') ?? 0;
      final bisJ = int.tryParse(be['bis_jahr']?.toString() ?? '') ?? 0;
      if (vonJ > 0 && bisJ > 0) {
        return (bisJ * 12 + bisM) - (vonJ * 12 + vonM) < 3;
      }
      return false;
    }).toList();
    final keineKurzJobs = kurzJobs.isEmpty;
    checks.add(_QualityCheck('Keine Kurzzeit-Beschäftigungen (< 3 Mon.)', keineKurzJobs, keineKurzJobs ? 'Alle Jobs dauerten mindestens 3 Monate' : '${kurzJobs.length} Job(s) unter 3 Monaten — Recruiter sehen das als Risiko (Probezeit nicht bestanden?)'));

    // 27. Mobilnummer Format (mit Vorwahl)
    final telefonStr = (u['telefon_mobil'] ?? '').toString();
    final hasTelefonFormat = telefonStr.startsWith('+') || telefonStr.startsWith('0');
    checks.add(_QualityCheck('Telefonnummer mit Vorwahl', hasTelefonFormat && telefonStr.isNotEmpty, hasTelefonFormat && telefonStr.isNotEmpty ? 'Telefon beginnt mit Vorwahl' : 'Telefonnummer fehlt oder ohne Vorwahl (+49 oder 0...)'));

    // 28. Schulname vorhanden bei allen Schulen
    final schulenOhneName = _schulbildung.where((sc) => (sc['schul_name'] ?? '').toString().isEmpty).toList();
    final hasAlleSchulnamen = schulenOhneName.isEmpty && hasSchule;
    checks.add(_QualityCheck('Schulname bei allen Schulen', hasAlleSchulnamen, hasAlleSchulnamen ? 'Alle Schulen haben einen Namen' : '${schulenOhneName.length} Schule(n) ohne Namen'));

    // 29. Antichronologische Reihenfolge (neueste zuerst)
    bool isAntichronologisch = true;
    if (_berufserfahrung.length >= 2) {
      for (int i = 0; i < _berufserfahrung.length - 1; i++) {
        final vonJ1 = int.tryParse(_berufserfahrung[i]['von_jahr']?.toString() ?? '') ?? 0;
        final vonJ2 = int.tryParse(_berufserfahrung[i + 1]['von_jahr']?.toString() ?? '') ?? 0;
        if (vonJ1 < vonJ2) { isAntichronologisch = false; break; }
      }
    }
    checks.add(_QualityCheck('Antichronologische Reihenfolge', isAntichronologisch, isAntichronologisch ? 'Jobs sind korrekt sortiert (neueste zuerst)' : 'Jobs sind nicht antichronologisch sortiert — neuester Job muss oben stehen'));

    // 30. Sprachniveau bei allen Sprachen angegeben
    final sprachenOhneNiveau = _sprachen.where((s) => (s['niveau'] ?? '').toString().isEmpty).toList();
    final hasAlleNiveaus = sprachenOhneNiveau.isEmpty && hasSprachen;
    checks.add(_QualityCheck('Sprachniveau bei allen Sprachen', hasAlleNiveaus, hasAlleNiveaus ? 'Alle Sprachen haben ein Niveau' : '${sprachenOhneNiveau.length} Sprache(n) ohne Niveau — Grundkenntnisse/Fließend/Muttersprache angeben'));

    // ══════════════════════════════════════
    // KARRIEREENTWICKLUNG (31-40)
    // ══════════════════════════════════════

    // 31. Karriereentwicklung erkennbar (verschiedene Positionen)
    final uniquePositionen = _berufserfahrung.map((be) => (be['funktion'] ?? be['position'] ?? '').toString().toLowerCase().trim()).where((p) => p.isNotEmpty).toSet();
    final hasKarriere = uniquePositionen.length >= 2 || _berufserfahrung.length <= 1;
    checks.add(_QualityCheck('Karriereentwicklung erkennbar', hasKarriere, hasKarriere ? '${uniquePositionen.length} verschiedene Position(en)' : 'Alle Jobs haben die gleiche Position — keine Entwicklung erkennbar'));

    // 32. Verschiedene Arbeitgeber (nicht nur ein Arbeitgeber)
    final uniqueFirmen = _berufserfahrung.map((be) => (be['firma'] ?? '').toString().toLowerCase().trim()).where((f) => f.isNotEmpty).toSet();
    final hasVerschFirmen = uniqueFirmen.length >= 2 || _berufserfahrung.length <= 1;
    checks.add(_QualityCheck('Verschiedene Arbeitgeber', hasVerschFirmen, hasVerschFirmen ? '${uniqueFirmen.length} verschiedene Arbeitgeber' : 'Nur 1 Arbeitgeber — geringe Flexibilität'));

    // 33. Längste Beschäftigung > 6 Monate
    int laengsteBeschaeftigung = 0;
    String laengsteFirma = '';
    for (final be in _berufserfahrung) {
      final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      final bisM = int.tryParse(be['bis_monat']?.toString() ?? '') ?? 0;
      final bisJ = int.tryParse(be['bis_jahr']?.toString() ?? '') ?? 0;
      final isAktuell = be['aktuell'] == true || be['aktuell'] == 1 || be['aktuell'] == '1';
      if (vonJ > 0) {
        final von = vonJ * 12 + vonM;
        final bis = isAktuell ? DateTime.now().year * 12 + DateTime.now().month : (bisJ > 0 ? bisJ * 12 + bisM : von);
        final dauer = (bis - von).abs();
        if (dauer > laengsteBeschaeftigung) { laengsteBeschaeftigung = dauer; laengsteFirma = be['firma'] ?? ''; }
      }
    }
    final hasLangeBeschaeftigung = laengsteBeschaeftigung >= 6;
    checks.add(_QualityCheck('Längste Beschäftigung > 6 Monate', hasLangeBeschaeftigung, hasLangeBeschaeftigung ? 'Längste: $laengsteBeschaeftigung Monate bei $laengsteFirma' : 'Keine Beschäftigung > 6 Monate — Job-Hopping-Risiko'));

    // 34. Nicht zu viele Jobwechsel (max 5 in 5 Jahren)
    final now = DateTime.now();
    final fuenfJahreVorher = (now.year - 5) * 12 + now.month;
    final recentJobs = _berufserfahrung.where((be) {
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      return vonJ * 12 + vonM >= fuenfJahreVorher;
    }).length;
    final keinJobHopping = recentJobs <= 5;
    checks.add(_QualityCheck('Kein häufiger Jobwechsel (≤ 5 in 5 J.)', keinJobHopping, keinJobHopping ? '$recentJobs Job(s) in den letzten 5 Jahren' : '$recentJobs Jobs in 5 Jahren — wirkt instabil auf Recruiter'));

    // 35. Aktuelle Berufserfahrung (letzter Job nicht älter als 2 Jahre)
    bool hasAktuelleErfahrung = false;
    if (_berufserfahrung.isNotEmpty) {
      final neuester = _berufserfahrung.first;
      final isAktuell = neuester['aktuell'] == true || neuester['aktuell'] == 1 || neuester['aktuell'] == '1';
      final bisJ = int.tryParse(neuester['bis_jahr']?.toString() ?? '') ?? 0;
      hasAktuelleErfahrung = isAktuell || bisJ >= now.year - 2;
    }
    checks.add(_QualityCheck('Aktuelle Berufserfahrung (< 2 Jahre)', hasAktuelleErfahrung, hasAktuelleErfahrung ? 'Letzte Tätigkeit ist aktuell oder max. 2 Jahre alt' : 'Letzter Job liegt über 2 Jahre zurück'));

    // ══════════════════════════════════════
    // VOLLSTÄNDIGKEIT DETAILS (36-45)
    // ══════════════════════════════════════

    // 36. Mindestens 2 Aufgaben bei jedem Job
    final berufeUnter2Aufgaben = _berufserfahrung.where((be) {
      int count = 0;
      if ((be['aufgabe1'] ?? '').toString().isNotEmpty) count++;
      if ((be['aufgabe2'] ?? '').toString().isNotEmpty) count++;
      if ((be['aufgabe3'] ?? '').toString().isNotEmpty) count++;
      return count < 2;
    }).toList();
    final hasMin2Aufgaben = berufeUnter2Aufgaben.isEmpty && hasBeruf;
    checks.add(_QualityCheck('Mind. 2 Aufgaben bei jedem Job', hasMin2Aufgaben, hasMin2Aufgaben ? 'Alle Jobs haben mindestens 2 Aufgaben' : '${berufeUnter2Aufgaben.length} Job(s) mit weniger als 2 Aufgaben'));

    // 37. Aufgaben nicht zu kurz (mind. 15 Zeichen)
    int kurzeAufgaben = 0;
    for (final be in _berufserfahrung) {
      for (final key in ['aufgabe1', 'aufgabe2', 'aufgabe3']) {
        final a = (be[key] ?? '').toString().trim();
        if (a.isNotEmpty && a.length < 15) kurzeAufgaben++;
      }
    }
    checks.add(_QualityCheck('Aufgaben aussagekräftig (≥ 15 Zeichen)', kurzeAufgaben == 0, kurzeAufgaben == 0 ? 'Alle Aufgaben sind ausreichend beschrieben' : '$kurzeAufgaben Aufgabe(n) zu kurz — detailliertere Beschreibung empfohlen'));

    // 38. Aufgaben nicht identisch bei verschiedenen Jobs
    final alleAufgaben = <String>[];
    for (final be in _berufserfahrung) {
      for (final key in ['aufgabe1', 'aufgabe2', 'aufgabe3']) {
        final a = (be[key] ?? '').toString().trim().toLowerCase();
        if (a.isNotEmpty) alleAufgaben.add(a);
      }
    }
    final uniqueAufgaben = alleAufgaben.toSet();
    final keineDoppelten = uniqueAufgaben.length == alleAufgaben.length;
    checks.add(_QualityCheck('Keine doppelten Aufgaben', keineDoppelten, keineDoppelten ? 'Alle Aufgabenbeschreibungen sind einzigartig' : '${alleAufgaben.length - uniqueAufgaben.length} doppelte Aufgabe(n) — individualisieren'));

    // 39. Schulart angegeben bei allen Schulen
    final schulenOhneArt = _schulbildung.where((sc) => (sc['schulart'] ?? '').toString().isEmpty).toList();
    final hasAlleSchularten = schulenOhneArt.isEmpty && hasSchule;
    checks.add(_QualityCheck('Schulart bei allen Schulen', hasAlleSchularten, hasAlleSchularten ? 'Alle Schulen haben eine Schulart' : '${schulenOhneArt.length} Schule(n) ohne Schulart'));

    // 40. PLZ bei Adresse (5 Ziffern für Deutschland)
    final plzStr = (u['plz'] ?? '').toString().trim();
    final hasKorrektePLZ = plzStr.length == 5 && int.tryParse(plzStr) != null;
    checks.add(_QualityCheck('PLZ korrekt (5-stellig)', hasKorrektePLZ, hasKorrektePLZ ? 'PLZ: $plzStr' : plzStr.isEmpty ? 'PLZ fehlt' : 'PLZ "$plzStr" ist nicht 5-stellig'));

    // ══════════════════════════════════════
    // SPRACHEN & QUALIFIKATIONEN (41-50)
    // ══════════════════════════════════════

    // 41. Muttersprache angegeben
    final hasMuttersprache = _sprachen.any((s) => (s['niveau'] ?? '').toString().toLowerCase().contains('mutter'));
    checks.add(_QualityCheck('Muttersprache angegeben', hasMuttersprache, hasMuttersprache ? 'Muttersprache ist eingetragen' : 'Keine Sprache als Muttersprache markiert'));

    // 42. Deutschniveau angegeben (wenn vorhanden)
    String deutschNiveau = '';
    for (final s in _sprachen) {
      if ((s['sprache'] ?? '').toString().toLowerCase().contains('deutsch')) {
        deutschNiveau = s['niveau'] ?? '';
      }
    }
    final hasDeutschNiveau = deutschNiveau.isNotEmpty;
    checks.add(_QualityCheck('Deutschniveau spezifiziert', hasDeutschNiveau, hasDeutschNiveau ? 'Deutsch: $deutschNiveau' : 'Deutsch hat kein Niveau — z.B. B1, B2, C1 angeben'));

    // 43. Nicht zu viele Sprachen (max 6 — wirkt unglaubwürdig)
    final nichtZuVieleSprachen = _sprachen.length <= 6;
    checks.add(_QualityCheck('Sprachanzahl realistisch (≤ 6)', nichtZuVieleSprachen, nichtZuVieleSprachen ? '${_sprachen.length} Sprache(n) — passt' : '${_sprachen.length} Sprachen — wirkt unglaubwürdig, auf die wichtigsten beschränken'));

    // 44. Führerschein Klasse B (Standard für Helferjobs)
    final hasKlasseB = _fuehrerschein.any((f) => (f['klasse'] ?? '').toString().toUpperCase() == 'B');
    final hasKeinenFS = _fuehrerschein.any((f) => (f['klasse'] ?? '').toString().toLowerCase() == 'keinen');
    checks.add(_QualityCheck('Führerschein Klasse B', hasKlasseB, hasKlasseB ? 'Klasse B vorhanden' : hasKeinenFS ? 'Kein Führerschein — für viele Stellen Voraussetzung' : 'Klasse B fehlt — am häufigsten verlangt'));

    // 45. Nicht mehr als 3 verschiedene Branchen
    // (basierend auf Aufgaben-Ähnlichkeit, vereinfacht über Position)
    final branchenCount = uniquePositionen.length;
    final nichtZuVieleBranchen = branchenCount <= 5;
    checks.add(_QualityCheck('Fokussiertes Berufsprofil (≤ 5 Positionen)', nichtZuVieleBranchen, nichtZuVieleBranchen ? '$branchenCount verschiedene Position(en)' : '$branchenCount verschiedene Positionen — wirkt unfokussiert'));

    // 46. Vorname nicht leer oder zu kurz
    final vornameStr = (u['vorname'] ?? '').toString().trim();
    final hasVollVorname = vornameStr.length >= 2;
    checks.add(_QualityCheck('Vorname vollständig (≥ 2 Zeichen)', hasVollVorname, hasVollVorname ? 'Vorname: $vornameStr' : 'Vorname fehlt oder zu kurz'));

    // 47. Nachname nicht leer oder zu kurz
    final nachnameStr = (u['nachname'] ?? '').toString().trim();
    final hasVollNachname = nachnameStr.length >= 2;
    checks.add(_QualityCheck('Nachname vollständig (≥ 2 Zeichen)', hasVollNachname, hasVollNachname ? 'Nachname: $nachnameStr' : 'Nachname fehlt oder zu kurz'));

    // 48. Alter zwischen 16 und 67 (arbeitsfähig)
    bool hasArbeitsAlter = false;
    String alterDetail = 'Alter kann nicht berechnet werden';
    final gebStr = (u['geburtsdatum'] ?? '').toString();
    if (gebStr.isNotEmpty) {
      try {
        final geb = DateTime.parse(gebStr);
        final alter = now.year - geb.year - (now.month < geb.month || (now.month == geb.month && now.day < geb.day) ? 1 : 0);
        hasArbeitsAlter = alter >= 16 && alter <= 67;
        alterDetail = 'Alter: $alter Jahre${!hasArbeitsAlter ? ' — außerhalb des typischen Arbeitsalters' : ''}';
      } catch (_) {}
    }
    checks.add(_QualityCheck('Arbeitsfähiges Alter (16-67)', hasArbeitsAlter, alterDetail));

    // 49. E-Mail enthält @ und Domain
    final hasEmailFormat = emailStr.contains('@') && emailStr.contains('.') && emailStr.indexOf('@') < emailStr.lastIndexOf('.');
    checks.add(_QualityCheck('E-Mail-Format korrekt', hasEmailFormat, hasEmailFormat ? 'E-Mail-Format ist gültig' : 'E-Mail-Format ungültig oder fehlt'));

    // 50. Telefon hat mindestens 8 Ziffern
    final telefonZiffern = telefonStr.replaceAll(RegExp(r'[^0-9]'), '');
    final hasTelefonLaenge = telefonZiffern.length >= 8;
    checks.add(_QualityCheck('Telefon hat mind. 8 Ziffern', hasTelefonLaenge, hasTelefonLaenge ? '${telefonZiffern.length} Ziffern' : telefonStr.isEmpty ? 'Keine Telefonnummer' : 'Nur ${telefonZiffern.length} Ziffern — zu kurz'));

    // ══════════════════════════════════════
    // KONSISTENZ & QUALITÄT (51-60)
    // ══════════════════════════════════════

    // 51. Schulende vor erstem Job (chronologisch logisch)
    bool schulVorJob = true;
    if (_schulbildung.isNotEmpty && _berufserfahrung.isNotEmpty) {
      for (final sc in _schulbildung) {
        final seStr = (sc['schul_ende'] ?? '').toString();
        if (seStr.contains('.') && seStr.split('.').length == 3) {
          final parts = seStr.split('.');
          final schulEndeMonat = int.tryParse(parts[1]) ?? 0;
          final schulEndeJahr = int.tryParse(parts[2]) ?? 0;
          if (schulEndeJahr > 0) {
            final schulEnde = schulEndeJahr * 12 + schulEndeMonat;
            for (final be in _berufserfahrung) {
              final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
              final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
              if (vonJ > 0 && vonJ * 12 + vonM < schulEnde - 12) {
                schulVorJob = false;
              }
            }
          }
        }
      }
    }
    checks.add(_QualityCheck('Schulende vor Berufsbeginn', schulVorJob, schulVorJob ? 'Chronologie Schule → Beruf ist korrekt' : 'Ein Job beginnt deutlich vor dem Schulende'));

    // 52. Keine Zukunftsdaten bei Berufserfahrung
    final nowMonth = now.year * 12 + now.month;
    final zukunftsJobs = _berufserfahrung.where((be) {
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      final vonM = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      return vonJ > 0 && vonJ * 12 + vonM > nowMonth + 1;
    }).toList();
    checks.add(_QualityCheck('Keine Zukunftsdaten bei Jobs', zukunftsJobs.isEmpty, zukunftsJobs.isEmpty ? 'Alle Startdaten liegen in der Vergangenheit' : '${zukunftsJobs.length} Job(s) mit Startdatum in der Zukunft'));

    // 53. Gesamte Berufserfahrung plausibel zum Alter
    bool erfahrungPlausibel = true;
    String plausibDetail = 'Plausibilitätsprüfung OK';
    if (gebStr.isNotEmpty && gesamtMonate > 0) {
      try {
        final geb = DateTime.parse(gebStr);
        final alter = now.year - geb.year;
        if (gesamtMonate > (alter - 14) * 12) {
          erfahrungPlausibel = false;
          plausibDetail = 'Mehr Berufserfahrung als vom Alter her möglich';
        }
      } catch (_) {}
    }
    checks.add(_QualityCheck('Erfahrung plausibel zum Alter', erfahrungPlausibel, plausibDetail));

    // 54. Mindestens 3 Jobs bei > 5 Jahren Erfahrung
    final hasGenugJobs = gesamtMonate <= 60 || _berufserfahrung.length >= 3;
    checks.add(_QualityCheck('Ausreichend Jobs für Erfahrungsdauer', hasGenugJobs, hasGenugJobs ? 'Anzahl Jobs passt zur Erfahrungsdauer' : 'Über 5 Jahre Erfahrung aber weniger als 3 Jobs — wirkt lückenhaft'));

    // 55. Familienstand angegeben
    final hasFamilienstand = (u['familienstand'] ?? '').toString().isNotEmpty;
    checks.add(_QualityCheck('Familienstand angegeben', hasFamilienstand, hasFamilienstand ? 'Familienstand: ${u['familienstand']}' : 'Familienstand fehlt — in Deutschland noch üblich'));

    // 56. Straße nicht nur Nummer
    final strasseStr = (u['strasse'] ?? '').toString().trim();
    final hasRichtigeStrasse = strasseStr.length >= 5 && strasseStr.contains(RegExp(r'[a-zA-ZäöüÄÖÜß]'));
    checks.add(_QualityCheck('Straßenname vollständig', hasRichtigeStrasse, hasRichtigeStrasse ? 'Straße: $strasseStr' : strasseStr.isEmpty ? 'Straße fehlt' : 'Straßenname zu kurz oder nur Zahlen'));

    // 57. Ort nicht zu kurz
    final ortStr = (u['ort'] ?? '').toString().trim();
    final hasRichtigerOrt = ortStr.length >= 2;
    checks.add(_QualityCheck('Ort vollständig (≥ 2 Zeichen)', hasRichtigerOrt, hasRichtigerOrt ? 'Ort: $ortStr' : 'Ort fehlt oder zu kurz'));

    // 58. Keine doppelten Firmen nacheinander (gleiche Firma 2x)
    bool keineDoppeltenFirmen = true;
    for (int i = 0; i < _berufserfahrung.length - 1; i++) {
      final f1 = (_berufserfahrung[i]['firma'] ?? '').toString().toLowerCase().trim();
      final f2 = (_berufserfahrung[i + 1]['firma'] ?? '').toString().toLowerCase().trim();
      if (f1 == f2 && f1.isNotEmpty) { keineDoppeltenFirmen = false; break; }
    }
    checks.add(_QualityCheck('Keine doppelten Firmennamen nacheinander', keineDoppeltenFirmen, keineDoppeltenFirmen ? 'Keine Duplikate erkannt' : 'Gleiche Firma erscheint nacheinander — zusammenfassen'));

    // 59. Schulbildung nicht in der Zukunft
    bool keineZukunftsschule = true;
    for (final sc in _schulbildung) {
      final begStr = (sc['schul_beginn'] ?? '').toString();
      if (begStr.contains('.') && begStr.split('.').length == 3) {
        final parts = begStr.split('.');
        final j = int.tryParse(parts[2]) ?? 0;
        if (j > now.year + 1) keineZukunftsschule = false;
      }
    }
    checks.add(_QualityCheck('Schulbeginn nicht in der Zukunft', keineZukunftsschule, keineZukunftsschule ? 'Alle Schuldaten liegen in der Vergangenheit' : 'Schulbeginn liegt in der Zukunft'));

    // 60. Mehr als nur Grundkenntnisse in Deutsch (für Arbeit)
    bool hasDeutschB1Plus = false;
    for (final s in _sprachen) {
      if ((s['sprache'] ?? '').toString().toLowerCase().contains('deutsch')) {
        final niv = (s['niveau'] ?? '').toString().toLowerCase();
        hasDeutschB1Plus = niv.contains('gut') || niv.contains('sehr') || niv.contains('fließend') || niv.contains('mutter') || niv.contains('b1') || niv.contains('b2') || niv.contains('c1') || niv.contains('c2');
      }
    }
    checks.add(_QualityCheck('Deutsch mindestens "Gut" / B1+', hasDeutschB1Plus, hasDeutschB1Plus ? 'Deutschkenntnisse ausreichend für Arbeitsmarkt' : 'Deutsch nur Grundkenntnisse — die meisten Jobs erfordern B1+'));

    // ══════════════════════════════════════
    // BEWERBUNGSREIFE (61-70)
    // ══════════════════════════════════════

    // 61. Lebenslauf nicht zu kurz (mind. 3 Einträge gesamt)
    final gesamtEintraege = _berufserfahrung.length + _schulbildung.length;
    checks.add(_QualityCheck('Mindestens 3 Einträge gesamt', gesamtEintraege >= 3, gesamtEintraege >= 3 ? '$gesamtEintraege Einträge (Jobs + Schulen)' : 'Nur $gesamtEintraege Einträge — Lebenslauf wirkt dünn'));

    // 62. Lebenslauf nicht überladen (max 15 Jobs)
    checks.add(_QualityCheck('Nicht zu viele Jobs (≤ 15)', _berufserfahrung.length <= 15, _berufserfahrung.length <= 15 ? '${_berufserfahrung.length} Job(s)' : '${_berufserfahrung.length} Jobs — auf relevante beschränken'));

    // 63. Letzte 5 Jahre abgedeckt
    bool letzte5Abgedeckt = false;
    for (final be in _berufserfahrung) {
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      if (vonJ >= now.year - 5) letzte5Abgedeckt = true;
    }
    checks.add(_QualityCheck('Letzte 5 Jahre im Lebenslauf', letzte5Abgedeckt || _berufserfahrung.isEmpty, letzte5Abgedeckt ? 'Aktuelle Berufserfahrung vorhanden' : 'Keine Einträge in den letzten 5 Jahren'));

    // 64. Schulende angegeben bei allen Schulen
    final schulenOhneEnde = _schulbildung.where((sc) => (sc['schul_ende'] ?? '').toString().isEmpty).toList();
    final hasAlleSchulEnden = schulenOhneEnde.isEmpty && hasSchule;
    checks.add(_QualityCheck('Schulende bei allen Schulen', hasAlleSchulEnden, hasAlleSchulEnden ? 'Alle Schulen haben ein Enddatum' : '${schulenOhneEnde.length} Schule(n) ohne Enddatum'));

    // 65. Vorname und Nachname beginnen mit Großbuchstabe
    final vornameGross = vornameStr.isNotEmpty && vornameStr[0] == vornameStr[0].toUpperCase();
    final nachnameGross = nachnameStr.isNotEmpty && nachnameStr[0] == nachnameStr[0].toUpperCase();
    checks.add(_QualityCheck('Name korrekt geschrieben (Großbuchstabe)', vornameGross && nachnameGross, vornameGross && nachnameGross ? 'Vor- und Nachname beginnen korrekt' : 'Name beginnt nicht mit Großbuchstabe'));

    // 66. Keine Sonderzeichen im Namen
    final nameHatSonderzeichen = RegExp(r'[0-9@#$%^&*()!+=\[\]{}<>|\\]').hasMatch('$vornameStr $nachnameStr');
    checks.add(_QualityCheck('Keine Sonderzeichen im Namen', !nameHatSonderzeichen, !nameHatSonderzeichen ? 'Name enthält keine ungewöhnlichen Zeichen' : 'Name enthält Sonderzeichen oder Zahlen'));

    // 67. Mindestens eine Aufgabe enthält ein Verb
    final verben = ['bedienung', 'transport', 'reinigung', 'verpackung', 'montage', 'sortierung', 'kontrolle', 'unterstützung', 'vorbereitung', 'bearbeitung', 'pflege', 'lieferung', 'herstellung'];
    bool hatVerb = false;
    for (final a in alleAufgaben) {
      if (verben.any((v) => a.contains(v))) { hatVerb = true; break; }
    }
    checks.add(_QualityCheck('Aufgaben enthalten Tätigkeitswörter', hatVerb || alleAufgaben.isEmpty, hatVerb || alleAufgaben.isEmpty ? 'Aufgaben beschreiben konkrete Tätigkeiten' : 'Aufgaben enthalten keine typischen Tätigkeitswörter'));

    // 68. Geburtsdatum nicht in der Zukunft
    bool gebNichtZukunft = true;
    if (gebStr.isNotEmpty) {
      try { gebNichtZukunft = DateTime.parse(gebStr).isBefore(now); } catch (_) {}
    }
    checks.add(_QualityCheck('Geburtsdatum nicht in der Zukunft', gebNichtZukunft, gebNichtZukunft ? 'Geburtsdatum ist plausibel' : 'Geburtsdatum liegt in der Zukunft!'));

    // 69. E-Mail nicht von Wegwerf-Dienst
    final wegwerfDomains = ['tempmail', 'throwaway', 'guerrilla', 'mailinator', 'yopmail', 'trashmail'];
    final isWegwerf = wegwerfDomains.any((d) => emailStr.contains(d));
    checks.add(_QualityCheck('Keine Wegwerf-E-Mail', !isWegwerf, !isWegwerf ? 'E-Mail-Adresse ist permanent' : 'Wegwerf-E-Mail erkannt — seriöse Adresse verwenden'));

    // 70. Berufserfahrung vor Schulbildung im CV (Priorität)
    checks.add(_QualityCheck('Berufserfahrung vor Schulbildung', hasBeruf || !hasSchule, hasBeruf ? 'Berufserfahrung hat Priorität im Lebenslauf' : 'Keine Berufserfahrung — Schulbildung steht allein'));

    // ══════════════════════════════════════
    // DETAILPRÜFUNG (71-80)
    // ══════════════════════════════════════

    // 71. Aktueller Job hat Position
    bool aktuellerJobHatPosition = true;
    if (_berufserfahrung.isNotEmpty) {
      final erster = _berufserfahrung.first;
      aktuellerJobHatPosition = (erster['funktion'] ?? erster['position'] ?? '').toString().isNotEmpty;
    }
    checks.add(_QualityCheck('Aktueller/letzter Job hat Position', aktuellerJobHatPosition, aktuellerJobHatPosition ? 'Position beim aktuellsten Job vorhanden' : 'Aktuellster Job ohne Positionsbezeichnung'));

    // 72. Aktueller Job hat Ort
    bool aktuellerJobHatOrt = true;
    if (_berufserfahrung.isNotEmpty) {
      aktuellerJobHatOrt = (_berufserfahrung.first['ort'] ?? '').toString().isNotEmpty;
    }
    checks.add(_QualityCheck('Aktueller/letzter Job hat Ort', aktuellerJobHatOrt, aktuellerJobHatOrt ? 'Ort beim aktuellsten Job vorhanden' : 'Aktuellster Job ohne Ortsangabe'));

    // 73. Schulort angegeben bei mindestens einer Schule
    final hasSchulOrt = _schulbildung.any((sc) => (sc['schul_plz_ort'] ?? '').toString().isNotEmpty);
    checks.add(_QualityCheck('Schulort bei mind. einer Schule', hasSchulOrt || !hasSchule, hasSchulOrt ? 'Mindestens eine Schule hat Ort' : 'Keine Schule hat einen Ort angegeben'));

    // 74. Nicht mehr als 4 Schulen (realistisch)
    checks.add(_QualityCheck('Schulanzahl realistisch (≤ 4)', _schulbildung.length <= 4, _schulbildung.length <= 4 ? '${_schulbildung.length} Schule(n)' : '${_schulbildung.length} Schulen — ungewöhnlich viele'));

    // 75. Gesamtdauer Schulbildung plausibel (4-13 Jahre)
    // Vereinfacht: prüfe ob es mindestens 4 Jahre gibt
    int schulJahre = 0;
    for (final sc in _schulbildung) {
      final begStr2 = (sc['schul_beginn'] ?? '').toString();
      final endeStr2 = (sc['schul_ende'] ?? '').toString();
      if (begStr2.contains('.') && endeStr2.contains('.')) {
        final bParts = begStr2.split('.');
        final eParts = endeStr2.split('.');
        if (bParts.length == 3 && eParts.length == 3) {
          final bJ = int.tryParse(bParts[2]) ?? 0;
          final eJ = int.tryParse(eParts[2]) ?? 0;
          if (bJ > 0 && eJ > 0) schulJahre += (eJ - bJ).abs();
        }
      }
    }
    final schulDauerOK = schulJahre >= 4 || !hasSchule;
    checks.add(_QualityCheck('Schuldauer plausibel (≥ 4 Jahre)', schulDauerOK, schulDauerOK ? 'Schulbildung: ~$schulJahre Jahre' : 'Nur ~$schulJahre Jahre Schulbildung — ungewöhnlich kurz'));

    // 76. Kein zu altes Geburtsdatum (nach 1940)
    bool gebNichtZuAlt = true;
    if (gebStr.isNotEmpty) {
      try { gebNichtZuAlt = DateTime.parse(gebStr).year >= 1940; } catch (_) {}
    }
    checks.add(_QualityCheck('Geburtsjahr nach 1940', gebNichtZuAlt, gebNichtZuAlt ? 'Geburtsjahr ist plausibel' : 'Geburtsjahr vor 1940 — bitte prüfen'));

    // 77. Berufserfahrung beginnt nicht vor 14. Lebensjahr
    bool arbeitNach14 = true;
    if (gebStr.isNotEmpty && _berufserfahrung.isNotEmpty) {
      try {
        final geb = DateTime.parse(gebStr);
        for (final be in _berufserfahrung) {
          final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
          if (vonJ > 0 && vonJ < geb.year + 14) { arbeitNach14 = false; break; }
        }
      } catch (_) {}
    }
    checks.add(_QualityCheck('Berufsbeginn nach 14. Lebensjahr', arbeitNach14, arbeitNach14 ? 'Alle Jobs beginnen im arbeitsfähigen Alter' : 'Ein Job beginnt vor dem 14. Lebensjahr — prüfen'));

    // 78. Führerschein nicht widersprüchlich (B + Keinen gleichzeitig)
    final hatKeinen = _fuehrerschein.any((f) => (f['klasse'] ?? '').toString().toLowerCase() == 'keinen');
    final hatAndere = _fuehrerschein.any((f) => (f['klasse'] ?? '').toString().toLowerCase() != 'keinen');
    final fsKonsistent = !(hatKeinen && hatAndere);
    checks.add(_QualityCheck('Führerschein konsistent', fsKonsistent, fsKonsistent ? 'Führerscheinangaben sind widerspruchsfrei' : '"Keinen" und gleichzeitig eine Klasse — widersprüchlich'));

    // 79. Mindestens ein aktueller oder kürzlich beendeter Job
    checks.add(_QualityCheck('Beruflich aktiv (aktuell oder kürzlich)', hasAktuelleErfahrung || _berufserfahrung.isEmpty, hasAktuelleErfahrung ? 'Beruflich aktiv' : 'Keine aktuelle Berufstätigkeit'));

    // 80. Vorname und Nachname nicht identisch
    final nameNichtIdentisch = vornameStr.toLowerCase() != nachnameStr.toLowerCase() || vornameStr.isEmpty;
    checks.add(_QualityCheck('Vorname ≠ Nachname', nameNichtIdentisch, nameNichtIdentisch ? 'Vor- und Nachname sind unterschiedlich' : 'Vorname und Nachname sind identisch'));

    // ══════════════════════════════════════
    // ERWEITERTE PRÜFUNG (81-90)
    // ══════════════════════════════════════

    // 81. Maximal 2 Jobs ohne Aufgaben
    final jobsOhneAufgaben = _berufserfahrung.where((be) => (be['aufgabe1'] ?? '').toString().isEmpty && (be['aufgabe2'] ?? '').toString().isEmpty && (be['aufgabe3'] ?? '').toString().isEmpty).length;
    checks.add(_QualityCheck('Max. 2 Jobs ohne Aufgaben', jobsOhneAufgaben <= 2, jobsOhneAufgaben <= 2 ? '$jobsOhneAufgaben Job(s) ohne Aufgaben' : '$jobsOhneAufgaben Jobs ohne Aufgaben — zu viele'));

    // 82. Keine identischen Start- und Enddaten bei Jobs
    final gleicheDaten = _berufserfahrung.where((be) {
      final vm = be['von_monat']?.toString() ?? '';
      final vj = be['von_jahr']?.toString() ?? '';
      final bm = be['bis_monat']?.toString() ?? '';
      final bj = be['bis_jahr']?.toString() ?? '';
      return vm == bm && vj == bj && vm.isNotEmpty && vj.isNotEmpty;
    }).toList();
    checks.add(_QualityCheck('Start ≠ Ende bei Jobs', gleicheDaten.isEmpty, gleicheDaten.isEmpty ? 'Alle Jobs haben unterschiedliche Start-/Enddaten' : '${gleicheDaten.length} Job(s) mit gleichem Start und Ende'));

    // 83. Gesamte Lebenszeit abgedeckt (Schule + Beruf ohne große Lücke zum Alter)
    bool lebenszeitAbgedeckt = true;
    if (gebStr.isNotEmpty) {
      try {
        final geb = DateTime.parse(gebStr);
        final erwarteterStart = geb.year + 6; // Einschulung ca. 6 Jahre
        int fruehesterStart = 9999;
        for (final sc in _schulbildung) {
          final begStr3 = (sc['schul_beginn'] ?? '').toString();
          if (begStr3.contains('.') && begStr3.split('.').length == 3) {
            final j = int.tryParse(begStr3.split('.')[2]) ?? 9999;
            if (j < fruehesterStart) fruehesterStart = j;
          }
        }
        for (final be in _berufserfahrung) {
          final j = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 9999;
          if (j < fruehesterStart) fruehesterStart = j;
        }
        if (fruehesterStart < 9999 && (fruehesterStart - erwarteterStart).abs() > 5) {
          lebenszeitAbgedeckt = false;
        }
      } catch (_) {}
    }
    checks.add(_QualityCheck('Lebenszeit plausibel abgedeckt', lebenszeitAbgedeckt, lebenszeitAbgedeckt ? 'Bildungsweg und Beruf passen zum Alter' : 'Große Lücke zwischen Geburt und erstem Eintrag'));

    // 84. Ortswechsel nachvollziehbar
    checks.add(_QualityCheck('Wohnort angegeben', ortStr.isNotEmpty, ortStr.isNotEmpty ? 'Aktueller Wohnort: $ortStr' : 'Kein Wohnort — Arbeitgeber brauchen dies für Anfahrt'));

    // 85. Mindestens 1 Sprache hat "Fließend" oder "Muttersprache"
    final hatFliesend = _sprachen.any((s) {
      final niv = (s['niveau'] ?? '').toString().toLowerCase();
      return niv.contains('fließend') || niv.contains('mutter') || niv.contains('c1') || niv.contains('c2');
    });
    checks.add(_QualityCheck('Mind. 1 Sprache fließend/Muttersprache', hatFliesend || _sprachen.isEmpty, hatFliesend ? 'Mindestens eine Sprache auf hohem Niveau' : 'Keine Sprache als fließend oder Muttersprache'));

    // 86. Aufgaben nicht zu lang (max 100 Zeichen pro Aufgabe)
    int langeAufgaben = 0;
    for (final be in _berufserfahrung) {
      for (final key in ['aufgabe1', 'aufgabe2', 'aufgabe3']) {
        final a = (be[key] ?? '').toString().trim();
        if (a.length > 100) langeAufgaben++;
      }
    }
    checks.add(_QualityCheck('Aufgaben nicht zu lang (≤ 100 Zeichen)', langeAufgaben == 0, langeAufgaben == 0 ? 'Alle Aufgaben haben passende Länge' : '$langeAufgaben Aufgabe(n) über 100 Zeichen — kürzer formulieren'));

    // 87. Telefon enthält keine Buchstaben
    final telefonHatBuchstaben = RegExp(r'[a-zA-Z]').hasMatch(telefonStr);
    checks.add(_QualityCheck('Telefon enthält keine Buchstaben', !telefonHatBuchstaben || telefonStr.isEmpty, !telefonHatBuchstaben ? 'Telefonnummer ist korrekt formatiert' : 'Telefonnummer enthält Buchstaben'));

    // 88. Keine doppelten Schulen (gleicher Name)
    final schulNamen = _schulbildung.map((sc) => (sc['schul_name'] ?? '').toString().toLowerCase().trim()).where((n) => n.isNotEmpty).toList();
    final uniqueSchulNamen = schulNamen.toSet();
    checks.add(_QualityCheck('Keine doppelten Schulen', uniqueSchulNamen.length == schulNamen.length, uniqueSchulNamen.length == schulNamen.length ? 'Keine Duplikate bei Schulen' : 'Gleiche Schule mehrfach eingetragen'));

    // 89. Mindestens 5 Jahre seit Schulende (für Berufserfahrung relevant)
    // Skip wenn noch in der Schule
    bool genugZeitSeitSchule = true;
    if (_schulbildung.isNotEmpty && _berufserfahrung.isEmpty) {
      final letzteSchule = _schulbildung.first;
      final endeStr3 = (letzteSchule['schul_ende'] ?? '').toString();
      if (endeStr3.contains('.') && endeStr3.split('.').length == 3) {
        final j = int.tryParse(endeStr3.split('.')[2]) ?? 0;
        if (j > 0 && now.year - j > 2) genugZeitSeitSchule = false;
      }
    }
    checks.add(_QualityCheck('Berufserfahrung nach Schulende', genugZeitSeitSchule, genugZeitSeitSchule ? 'Beruflicher Werdegang dokumentiert' : 'Mehr als 2 Jahre seit Schulende ohne Berufserfahrung'));

    // 90. Keine doppelten Sprachen
    final sprachNamen = _sprachen.map((s) => (s['sprache'] ?? '').toString().toLowerCase().trim()).where((n) => n.isNotEmpty).toList();
    final uniqueSprachNamen = sprachNamen.toSet();
    checks.add(_QualityCheck('Keine doppelten Sprachen', uniqueSprachNamen.length == sprachNamen.length, uniqueSprachNamen.length == sprachNamen.length ? 'Keine Duplikate bei Sprachen' : 'Gleiche Sprache mehrfach eingetragen'));

    // ══════════════════════════════════════
    // FEINSCHLIFF (91-100)
    // ══════════════════════════════════════

    // 91. Nicht nur 1 Monat bei irgendeinem Job
    final einMonatJobs = _berufserfahrung.where((be) {
      final vm = be['von_monat']?.toString() ?? '';
      final vj = be['von_jahr']?.toString() ?? '';
      final bm = be['bis_monat']?.toString() ?? '';
      final bj = be['bis_jahr']?.toString() ?? '';
      if (vj.isNotEmpty && bj.isNotEmpty && vm.isNotEmpty && bm.isNotEmpty) {
        final von = int.parse(vj) * 12 + int.parse(vm);
        final bis = int.parse(bj) * 12 + int.parse(bm);
        return (bis - von).abs() <= 1 && be['aktuell'] != true;
      }
      return false;
    }).length;
    checks.add(_QualityCheck('Keine 1-Monats-Jobs', einMonatJobs == 0, einMonatJobs == 0 ? 'Alle Jobs dauern mindestens 2 Monate' : '$einMonatJobs Job(s) mit nur 1 Monat Dauer'));

    // 92. E-Mail nicht komplett in Großbuchstaben
    final emailNichtGross = emailStr == emailStr.toLowerCase() || emailStr.isEmpty;
    checks.add(_QualityCheck('E-Mail in Kleinbuchstaben', emailNichtGross, emailNichtGross ? 'E-Mail korrekt formatiert' : 'E-Mail enthält Großbuchstaben — Kleinschreibung empfohlen'));

    // 93. Geburtsort nicht gleich aktueller Wohnort (Mobilitätsbereitschaft)
    // Nur Info, nicht negativ
    final gebOrt = (u['geburtsort'] ?? '').toString().toLowerCase().trim();
    final wohnOrt = ortStr.toLowerCase().trim();
    final hatMobilitaet = gebOrt != wohnOrt && gebOrt.isNotEmpty && wohnOrt.isNotEmpty;
    checks.add(_QualityCheck('Mobilitätsbereitschaft erkennbar', hatMobilitaet || gebOrt.isEmpty || wohnOrt.isEmpty, hatMobilitaet ? 'Umzugsbereitschaft: $gebOrt → $ortStr' : gebOrt.isEmpty || wohnOrt.isEmpty ? 'Nicht prüfbar (Ort fehlt)' : 'Geburtsort = Wohnort — Mobilität nicht erkennbar'));

    // 94. PLZ passt zum Ort (Plausibilität — vereinfacht)
    final plzStartValid = plzStr.isNotEmpty && !plzStr.startsWith('00');
    checks.add(_QualityCheck('PLZ beginnt nicht mit 00', plzStartValid || plzStr.isEmpty, plzStartValid || plzStr.isEmpty ? 'PLZ ist plausibel' : 'PLZ beginnt mit 00 — ungültig in Deutschland'));

    // 95. Gesamtprofil: mind. 5 ausgefüllte Felder in persönlichen Daten
    int persFelder = 0;
    if (vornameStr.isNotEmpty) persFelder++;
    if (nachnameStr.isNotEmpty) persFelder++;
    if (gebStr.isNotEmpty) persFelder++;
    if (strasseStr.isNotEmpty) persFelder++;
    if (plzStr.isNotEmpty) persFelder++;
    if (ortStr.isNotEmpty) persFelder++;
    if (emailStr.isNotEmpty) persFelder++;
    if (telefonStr.isNotEmpty) persFelder++;
    if ((u['geburtsort'] ?? '').toString().isNotEmpty) persFelder++;
    if ((u['staatsangehoerigkeit'] ?? '').toString().isNotEmpty) persFelder++;
    checks.add(_QualityCheck('Mind. 5 persönliche Datenfelder', persFelder >= 5, persFelder >= 5 ? '$persFelder/10 persönliche Felder ausgefüllt' : 'Nur $persFelder/10 — mehr Daten angeben'));

    // 96. Mindestens 2 verschiedene Aufgabentypen (Vielseitigkeit)
    checks.add(_QualityCheck('Vielseitige Aufgaben', uniqueAufgaben.length >= 3 || alleAufgaben.isEmpty, uniqueAufgaben.length >= 3 ? '${uniqueAufgaben.length} verschiedene Aufgaben' : 'Nur ${uniqueAufgaben.length} verschiedene Aufgabe(n) — mehr Vielseitigkeit zeigen'));

    // 97. Berufserfahrung hat Firma aus Datenbank (verifiziert)
    final verifizierteJobs = _berufserfahrung.where((be) => be['arbeitgeber_db_id'] != null && be['arbeitgeber_db_id'].toString().isNotEmpty).length;
    checks.add(_QualityCheck('Jobs mit verifizierten Firmen', verifizierteJobs > 0 || _berufserfahrung.isEmpty, verifizierteJobs > 0 ? '$verifizierteJobs Job(s) mit Firma aus Datenbank' : 'Keine Firma aus der Firmendatenbank — Verifizierung empfohlen'));

    // 98. Kein Job älter als 20 Jahre (Relevanz)
    final alteJobs = _berufserfahrung.where((be) {
      final vonJ = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0;
      return vonJ > 0 && now.year - vonJ > 20;
    }).length;
    checks.add(_QualityCheck('Keine Jobs älter als 20 Jahre', alteJobs == 0, alteJobs == 0 ? 'Alle Jobs sind relevant (< 20 Jahre)' : '$alteJobs Job(s) älter als 20 Jahre — Relevanz fraglich'));

    // 99. Mindestens 1 Schule aus Datenbank (verifiziert)
    // Schulen aus DB haben typischerweise schul_telefon oder schul_email
    final verifiziertSchulen = _schulbildung.where((sc) => (sc['schul_telefon'] ?? '').toString().isNotEmpty || (sc['schul_email'] ?? '').toString().isNotEmpty).length;
    checks.add(_QualityCheck('Schulen mit Kontaktdaten (verifiziert)', verifiziertSchulen > 0 || !hasSchule, verifiziertSchulen > 0 ? '$verifiziertSchulen Schule(n) mit Kontaktdaten' : 'Keine Schule hat Kontaktdaten — Schule aus Datenbank empfohlen'));

    // 100. Monat gültig (01-12) bei allen Jobs
    final ungueltigeMonate = _berufserfahrung.where((be) {
      final vm = int.tryParse(be['von_monat']?.toString() ?? '') ?? 0;
      final bm = int.tryParse(be['bis_monat']?.toString() ?? '') ?? 0;
      return (vm > 0 && (vm < 1 || vm > 12)) || (bm > 0 && (bm < 1 || bm > 12));
    }).length;
    checks.add(_QualityCheck('Gültige Monate (01-12) bei Jobs', ungueltigeMonate == 0, ungueltigeMonate == 0 ? 'Alle Monate sind gültig' : '$ungueltigeMonate Job(s) mit ungültigem Monat'));

    // 101. Branchenrelevante Keywords
    final branchenKW = ['produktion', 'lager', 'transport', 'montage', 'verpackung', 'maschine', 'qualität', 'reinigung', 'pflege', 'küche', 'service', 'bau', 'fertigung', 'logistik', 'kommission'];
    int kwTreffer = 0;
    for (final a in alleAufgaben) { if (branchenKW.any((k) => a.contains(k))) kwTreffer++; }
    checks.add(_QualityCheck('Branchen-Keywords in Aufgaben', kwTreffer > 0 || alleAufgaben.isEmpty, kwTreffer > 0 ? '$kwTreffer Aufgabe(n) mit Keywords' : 'Keine branchenspezifischen Begriffe'));

    // 102. Aktionsverben in Aufgaben
    final aktVerben = ['bedien', 'transport', 'reinig', 'verpack', 'montier', 'sortier', 'kontroll', 'unterstütz', 'vorbereit', 'bearbeit', 'prüf', 'organisier', 'überwach', 'durchführ'];
    int avTreffer = 0;
    for (final a in alleAufgaben) { if (aktVerben.any((v) => a.contains(v))) avTreffer++; }
    checks.add(_QualityCheck('Aktionsverben in Aufgaben', avTreffer > 0 || alleAufgaben.isEmpty, avTreffer > 0 ? '$avTreffer Aufgabe(n) mit Aktionsverben' : 'Keine Aktionsverben — "Bedienung von..." empfohlen'));

    // 103. Aufgaben > 2 Wörter
    int nurKurzAufg = 0;
    for (final a in alleAufgaben) { if (a.split(' ').length <= 2) nurKurzAufg++; }
    checks.add(_QualityCheck('Aufgaben > 2 Wörter', nurKurzAufg == 0, nurKurzAufg == 0 ? 'Alle Aufgaben ausführlich' : '$nurKurzAufg Aufgabe(n) mit nur 1-2 Wörtern'));

    // 104. Abwechslungsreiche Aufgabenstarts
    final aufgStarts = alleAufgaben.map((a) => a.split(' ').first).toSet();
    final varStarts = aufgStarts.length >= (alleAufgaben.length * 0.5).ceil() || alleAufgaben.length <= 2;
    checks.add(_QualityCheck('Abwechslungsreiche Aufgaben', varStarts, varStarts ? 'Aufgaben beginnen unterschiedlich' : 'Viele gleiche Anfänge — variieren'));

    // 105. Messbare Ergebnisse (Zahlen in Aufgaben)
    final aufgMitZahlen = alleAufgaben.where((a) => RegExp(r'\d').hasMatch(a)).length;
    checks.add(_QualityCheck('Messbare Ergebnisse in Aufgaben', aufgMitZahlen > 0 || alleAufgaben.isEmpty, aufgMitZahlen > 0 ? '$aufgMitZahlen Aufgabe(n) mit Zahlen' : 'Keine Zahlen — "50 Pakete/Tag" empfohlen'));

    // 106. Positionen ohne Sonderzeichen
    int posSonderz = 0;
    for (final be in _berufserfahrung) { if (RegExp(r'[@#\$%^&*!+=\[\]{}<>|\\]').hasMatch((be['funktion'] ?? be['position'] ?? '').toString())) posSonderz++; }
    checks.add(_QualityCheck('Positionen ohne Sonderzeichen', posSonderz == 0, posSonderz == 0 ? 'Positionen korrekt' : '$posSonderz Position(en) mit Sonderzeichen'));

    // 107. Firmennamen ≥ 3 Zeichen
    final kurzFirm = _berufserfahrung.where((be) { final f = (be['firma'] ?? '').toString().trim(); return f.isNotEmpty && f.length < 3; }).length;
    checks.add(_QualityCheck('Firmennamen ≥ 3 Zeichen', kurzFirm == 0, kurzFirm == 0 ? 'Firmennamen vollständig' : '$kurzFirm zu kurz'));

    // 108. Position ≠ Firmenname
    int posFirma = 0;
    for (final be in _berufserfahrung) { if ((be['firma'] ?? '').toString().toLowerCase().trim() == (be['funktion'] ?? be['position'] ?? '').toString().toLowerCase().trim() && (be['firma'] ?? '').toString().isNotEmpty) posFirma++; }
    checks.add(_QualityCheck('Position ≠ Firmenname', posFirma == 0, posFirma == 0 ? 'OK' : '$posFirma Mal identisch'));

    // 109. E-Mail enthält Namen
    final emailName = emailStr.contains(vornameStr.toLowerCase()) || emailStr.contains(nachnameStr.toLowerCase());
    checks.add(_QualityCheck('E-Mail enthält Namen', emailName || emailStr.isEmpty || vornameStr.isEmpty, emailName ? 'Professionelle E-Mail' : 'vorname.nachname@... empfohlen'));

    // 110. E-Mail ohne Leerzeichen
    checks.add(_QualityCheck('E-Mail ohne Leerzeichen', !emailStr.contains(' ') || emailStr.isEmpty, !emailStr.contains(' ') ? 'OK' : 'Leerzeichen in E-Mail'));

    // 111. Deutsch als erste Sprache
    bool dZuerst = true;
    if (_sprachen.length >= 2) dZuerst = (_sprachen.first['sprache'] ?? '').toString().toLowerCase().contains('deutsch');
    checks.add(_QualityCheck('Deutsch als erste Sprache', dZuerst || _sprachen.length < 2, dZuerst ? 'Deutsch an erster Stelle' : 'Deutsch sollte zuerst stehen'));

    // 112. Schulbeginn vor erstem Job
    bool bildVorBeruf = true;
    if (_schulbildung.isNotEmpty && _berufserfahrung.isNotEmpty) {
      int frSch = 9999; int frJob = 9999;
      for (final sc in _schulbildung) { final b = (sc['schul_beginn'] ?? '').toString(); if (b.contains('.') && b.split('.').length == 3) { final j = int.tryParse(b.split('.')[2]) ?? 9999; if (j < frSch) frSch = j; } }
      for (final be in _berufserfahrung) { final j = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 9999; if (j < frJob) frJob = j; }
      if (frSch < 9999 && frJob < 9999) bildVorBeruf = frSch <= frJob;
    }
    checks.add(_QualityCheck('Schulbeginn vor erstem Job', bildVorBeruf, bildVorBeruf ? 'Chronologisch korrekt' : 'Job beginnt vor Schulbeginn'));

    // 113-120: Weitere Konsistenz-Checks
    checks.add(_QualityCheck('FS-Klassen realistisch (≤ 5)', _fuehrerschein.where((f) => (f['klasse'] ?? '').toString().toLowerCase() != 'keinen').length <= 5, 'Führerscheinklassen geprüft'));
    final altJobs = _berufserfahrung.where((be) { final v = int.tryParse(be['von_jahr']?.toString() ?? '') ?? 0; return v > 0 && v < 1970; }).length;
    checks.add(_QualityCheck('Keine Jobs vor 1970', altJobs == 0, altJobs == 0 ? 'Alle Jobs im relevanten Zeitraum' : '$altJobs zu alt'));
    int ortZahl = 0;
    for (final be in _berufserfahrung) { if ((be['ort'] ?? '').toString().trim().isNotEmpty && RegExp(r'^[0-9]').hasMatch((be['ort'] ?? '').toString().trim())) ortZahl++; }
    checks.add(_QualityCheck('Ortsangaben korrekt (kein PLZ)', ortZahl == 0, ortZahl == 0 ? 'Orte korrekt' : '$ortZahl Ort(e) mit PLZ'));
    int jobGlAufg = 0;
    for (final be in _berufserfahrung) { final a1 = (be['aufgabe1'] ?? '').toString().toLowerCase().trim(); final a2 = (be['aufgabe2'] ?? '').toString().toLowerCase().trim(); final a3 = (be['aufgabe3'] ?? '').toString().toLowerCase().trim(); if (a1.isNotEmpty && (a1 == a2 || a1 == a3 || (a2.isNotEmpty && a2 == a3))) jobGlAufg++; }
    checks.add(_QualityCheck('Aufgaben pro Job unterschiedlich', jobGlAufg == 0, jobGlAufg == 0 ? 'OK' : '$jobGlAufg Job(s) mit identischen Aufgaben'));
    checks.add(_QualityCheck('Zweiter Vorname geprüft', true, (u['vorname2'] ?? '').toString().isNotEmpty ? '2. Vorname: ${u['vorname2']}' : 'Kein 2. Vorname — OK'));
    checks.add(_QualityCheck('Schulklasse angegeben', _schulbildung.any((sc) => (sc['klasse'] ?? '').toString().isNotEmpty) || _schulbildung.isEmpty, 'Schulklasse geprüft'));
    final detAufg = alleAufgaben.where((a) => a.length >= 30).length;
    checks.add(_QualityCheck('Mind. 1 Aufgabe ≥ 30 Zeichen', detAufg > 0 || alleAufgaben.isEmpty, detAufg > 0 ? '$detAufg detaillierte Aufgabe(n)' : 'Keine Aufgabe ausführlich genug'));

    // 121-130: Cross-Referencing
    checks.add(_QualityCheck('Mindestens 5 Aufgaben gesamt', alleAufgaben.length >= 5, alleAufgaben.length >= 5 ? '${alleAufgaben.length} Aufgaben' : 'Nur ${alleAufgaben.length} — mehr beschreiben'));
    final wOrt = ortStr.toLowerCase();
    final lokJob = _berufserfahrung.any((be) => (be['ort'] ?? '').toString().toLowerCase().contains(wOrt)) || wOrt.isEmpty;
    checks.add(_QualityCheck('Wohnort passt zu Arbeitsorten', lokJob || _berufserfahrung.isEmpty, lokJob ? 'Job am Wohnort' : 'Kein Job am Wohnort'));
    bool keineIdZeitr = true;
    for (int i = 0; i < _berufserfahrung.length; i++) { for (int j = i + 1; j < _berufserfahrung.length; j++) { final a = _berufserfahrung[i]; final b = _berufserfahrung[j]; if (a['von_monat'] == b['von_monat'] && a['von_jahr'] == b['von_jahr'] && a['bis_monat'] == b['bis_monat'] && a['bis_jahr'] == b['bis_jahr'] && (a['von_jahr'] ?? '').toString().isNotEmpty) keineIdZeitr = false; } }
    checks.add(_QualityCheck('Keine identischen Zeiträume', keineIdZeitr, keineIdZeitr ? 'Alle einzigartig' : 'Zwei Jobs gleicher Zeitraum'));
    bool schAlterOK = true;
    if (gebStr.isNotEmpty && _schulbildung.isNotEmpty) { try { final geb2 = DateTime.parse(gebStr); for (final sc in _schulbildung) { final b = (sc['schul_beginn'] ?? '').toString(); if (b.contains('.') && b.split('.').length == 3) { final j = int.tryParse(b.split('.')[2]) ?? 0; if (j > 0 && (j - geb2.year < 4 || j - geb2.year > 12)) schAlterOK = false; } } } catch (_) {} }
    checks.add(_QualityCheck('Einschulungsalter plausibel', schAlterOK, schAlterOK ? 'Alter bei Schulbeginn passt' : 'Einschulung unter 4 oder über 12'));
    bool dauerPl = true;
    if (gebStr.isNotEmpty) { try { final geb3 = DateTime.parse(gebStr); final lM = (now.year - geb3.year) * 12; if (gesamtMonate + schulJahre * 12 > lM + 24) dauerPl = false; } catch (_) {} }
    checks.add(_QualityCheck('Gesamtdauer passt zur Lebenszeit', dauerPl, dauerPl ? 'Beruf + Schule plausibel' : 'Dauert länger als Lebensjahre'));
    bool famOK = true;
    if (gebStr.isNotEmpty && (u['familienstand'] ?? '').toString().isNotEmpty) { try { final geb4 = DateTime.parse(gebStr); if (now.year - geb4.year < 16 && ['verheiratet', 'geschieden', 'verwitwet'].contains(u['familienstand'])) famOK = false; } catch (_) {} }
    checks.add(_QualityCheck('Familienstand altersgemäß', famOK, famOK ? 'OK' : 'Nicht altersgemäß'));
    final nurZahlAufg = alleAufgaben.where((a) => RegExp(r'^[\d\s.,]+$').hasMatch(a)).length;
    checks.add(_QualityCheck('Aufgaben sind Text', nurZahlAufg == 0, nurZahlAufg == 0 ? 'OK' : '$nurZahlAufg nur Zahlen'));
    checks.add(_QualityCheck('Telefon ≤ 15 Ziffern', telefonZiffern.length <= 15 || telefonStr.isEmpty, telefonZiffern.length <= 15 ? '${telefonZiffern.length} Ziffern' : 'Zu lang'));
    checks.add(_QualityCheck('Berufserfahrung in DE', _berufserfahrung.where((be) { final o = (be['ort'] ?? '').toString().toLowerCase(); return o.isNotEmpty; }).isNotEmpty || _berufserfahrung.isEmpty, 'Arbeitsorte geprüft'));

    // 131-140: Format
    final einstellM = _berufserfahrung.where((be) { final vm = (be['von_monat'] ?? '').toString(); return vm.isNotEmpty && vm.length == 1; }).length;
    checks.add(_QualityCheck('Monate zweistellig formatiert', einstellM == 0, einstellM == 0 ? 'OK' : '$einstellM einstellig'));
    final kurzJ = _berufserfahrung.where((be) { final vj = (be['von_jahr'] ?? '').toString(); return vj.isNotEmpty && vj.length != 4; }).length;
    checks.add(_QualityCheck('Jahre vierstellig', kurzJ == 0, kurzJ == 0 ? 'OK' : '$kurzJ nicht vierstellig'));
    bool schDatK = true;
    for (final sc in _schulbildung) { final b = (sc['schul_beginn'] ?? '').toString(); if (b.isNotEmpty && !b.contains('.')) schDatK = false; }
    checks.add(_QualityCheck('Schuldaten Format TT.MM.JJJJ', schDatK, schDatK ? 'Einheitlich' : 'Format inkonsistent'));
    final falschNiv = _sprachen.where((s) { final n = (s['niveau'] ?? '').toString().toLowerCase(); return n.contains('deutsch') || n.contains('englisch'); }).length;
    checks.add(_QualityCheck('Sprachniveau korrekt', falschNiv == 0, falschNiv == 0 ? 'OK' : '$falschNiv mit Sprachname als Niveau'));
    final fsDup = _fuehrerschein.map((f) => (f['klasse'] ?? '').toString().toLowerCase()).toList();
    checks.add(_QualityCheck('Keine doppelten FS-Klassen', fsDup.toSet().length == fsDup.length, fsDup.toSet().length == fsDup.length ? 'OK' : 'Duplikat'));
    final j3Aufg = _berufserfahrung.where((be) => (be['aufgabe1'] ?? '').toString().isNotEmpty && (be['aufgabe2'] ?? '').toString().isNotEmpty && (be['aufgabe3'] ?? '').toString().isNotEmpty).length;
    checks.add(_QualityCheck('Mind. 2 Jobs mit 3 Aufgaben', j3Aufg >= 2 || _berufserfahrung.length < 2, j3Aufg >= 2 ? '$j3Aufg vollständig' : 'Nur $j3Aufg'));
    final avgD = _berufserfahrung.isNotEmpty ? gesamtMonate / _berufserfahrung.length : 0;
    checks.add(_QualityCheck('Ø Jobdauer > 6 Monate', avgD >= 6 || _berufserfahrung.isEmpty, avgD >= 6 ? 'Ø ${avgD.round()} Mon.' : 'Ø nur ${avgD.round()} Mon.'));
    checks.add(_QualityCheck('Persönliche Daten ≥ 80%', persFelder >= 8, '$persFelder/10 Felder'));
    checks.add(_QualityCheck('Komplettes Profil', hasBeruf && hasSchule && hasSprachen, hasBeruf && hasSchule && hasSprachen ? 'Alle Bereiche vorhanden' : 'Bereiche fehlen'));

    // 141-149: Feinschliff
    checks.add(_QualityCheck('Name nicht GROSSBUCHSTABEN', vornameStr != vornameStr.toUpperCase() || vornameStr.length <= 1, 'Geprüft'));
    int dp = 0;
    if (vornameStr.isNotEmpty) dp++; if (nachnameStr.isNotEmpty) dp++; if (gebStr.isNotEmpty) dp++; if (emailStr.isNotEmpty) dp++; if (telefonStr.isNotEmpty) dp++;
    dp += _berufserfahrung.length + _schulbildung.length + _sprachen.length + _fuehrerschein.length;
    checks.add(_QualityCheck('Mind. 10 Datenpunkte', dp >= 10, dp >= 10 ? '$dp Datenpunkte' : 'Nur $dp'));
    bool schAnti = true;
    if (_schulbildung.length >= 2) { for (int i = 0; i < _schulbildung.length - 1; i++) { final b1 = (_schulbildung[i]['schul_beginn'] ?? '').toString(); final b2 = (_schulbildung[i + 1]['schul_beginn'] ?? '').toString(); if (b1.contains('.') && b2.contains('.')) { final j1 = int.tryParse(b1.split('.').last) ?? 0; final j2 = int.tryParse(b2.split('.').last) ?? 0; if (j1 < j2) schAnti = false; } } }
    checks.add(_QualityCheck('Schulbildung antichronologisch', schAnti, schAnti ? 'Korrekt sortiert' : 'Neueste Schule zuerst'));
    checks.add(_QualityCheck('Max. 8 Sprachen', _sprachen.length <= 8, '${_sprachen.length} Sprache(n)'));
    bool gebFmtOK = true;
    if (gebStr.isNotEmpty) { try { DateTime.parse(gebStr); } catch (_) { gebFmtOK = false; } }
    checks.add(_QualityCheck('Geburtsdatum Format gültig', gebFmtOK, gebFmtOK ? 'OK' : 'Ungültiges Format'));
    final txtQ = alleAufgaben.isNotEmpty ? alleAufgaben.map((a) => a.length).reduce((a, b) => a + b) / alleAufgaben.length : 0.0;
    checks.add(_QualityCheck('Aufgaben Ø > 20 Zeichen', txtQ >= 20 || alleAufgaben.isEmpty, txtQ >= 20 ? 'Ø ${txtQ.round()} Zeichen' : 'Ø nur ${txtQ.round()} — ausführlicher'));
    final pflicht = [vornameStr, nachnameStr, emailStr, telefonStr, strasseStr, plzStr, ortStr];
    final leerP = pflicht.where((f) => f.isEmpty).length;
    checks.add(_QualityCheck('Alle Pflichtfelder ausgefüllt', leerP == 0, leerP == 0 ? '7/7 Pflichtfelder' : '$leerP fehlen'));
    int gefuellt = 0; int gesamt2 = 0;
    for (final be in _berufserfahrung) { for (final key in ['firma', 'funktion', 'ort', 'von_monat', 'von_jahr', 'aufgabe1', 'aufgabe2', 'aufgabe3']) { gesamt2++; if ((be[key] ?? be[key == 'funktion' ? 'position' : key] ?? '').toString().isNotEmpty) gefuellt++; } }
    final fg = gesamt2 > 0 ? (gefuellt / gesamt2 * 100).round() : 100;
    checks.add(_QualityCheck('Datenqualität Jobs ≥ 70%', fg >= 70, '$fg% ausgefüllt'));

    // ══════════════════════════════════════
    // 150. GESAMTBEWERTUNG
    // ══════════════════════════════════════
    final bBest = checks.where((c) => c.passed).length;
    final bGes = checks.length;
    final pz = bGes > 0 ? (bBest / bGes * 100).round() : 0;
    checks.add(_QualityCheck('BEWERBUNGSREIF (≥ 80%)', pz >= 80, pz >= 80 ? 'Lebenslauf bewerbungsreif: $pz% ($bBest/$bGes)' : 'Nur $pz% ($bBest/$bGes) — mind. 80% empfohlen'));

    setState(() => _checks = checks);
  }

  int get _score => _checks.where((c) => c.passed).length;
  int get _total => _checks.length;

  Color _scoreColor() {
    final pct = _total > 0 ? _score / _total : 0.0;
    if (pct >= 0.8) return Colors.green;
    if (pct >= 0.5) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: AlertDialog(
        title: Row(children: [
          Icon(Icons.description, size: 22, color: Colors.green.shade700),
          const SizedBox(width: 8),
          const Expanded(child: Text('Lebenslauf', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))),
          IconButton(icon: const Icon(Icons.close, size: 20), onPressed: () => Navigator.pop(context), padding: EdgeInsets.zero, constraints: const BoxConstraints()),
        ]),
        content: SizedBox(
          width: 600,
          height: 500,
          child: Column(children: [
            TabBar(
              labelColor: Colors.green.shade700,
              unselectedLabelColor: Colors.grey.shade600,
              indicatorColor: Colors.green.shade700,
              labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: [
                const Tab(text: 'Lebenslauf generieren'),
                Tab(child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Text('Qualitätsprüfung'),
                  if (_loaded) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: _scoreColor(), borderRadius: BorderRadius.circular(10)),
                      child: Text('$_score/$_total', style: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ])),
              ],
            ),
            Expanded(child: TabBarView(children: [
              // === TAB 1: GENERIEREN ===
              _loaded
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: Colors.green.shade50, borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.green.shade200)),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text('Lebenslauf-Vorschau', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                            const SizedBox(height: 12),
                            _previewRow('Name', '${_userData['vorname'] ?? ''} ${_userData['nachname'] ?? ''}'.trim()),
                            _previewRow('Adresse', '${_userData['strasse'] ?? ''} ${_userData['hausnummer'] ?? ''}, ${_userData['plz'] ?? ''} ${_userData['ort'] ?? ''}'.trim()),
                            _previewRow('Berufserfahrung', '${_berufserfahrung.length} Einträge'),
                            _previewRow('Schulbildung', '${_schulbildung.length} Einträge'),
                            _previewRow('Sprachen', '${_sprachen.length} Sprache(n)'),
                            _previewRow('Führerschein', _fuehrerschein.isEmpty ? 'Nicht angegeben' : _fuehrerschein.map((f) => 'Klasse ${f['klasse']}').join(', ')),
                          ]),
                        ),
                        const SizedBox(height: 20),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final pCtx = widget.parentContext;
                              Navigator.pop(context);
                              await Future.delayed(const Duration(milliseconds: 150));
                              if (!pCtx.mounted) return;
                              await LebenslaufGenerator.generate(pCtx, widget.apiService, widget.userId);
                            },
                            icon: const Icon(Icons.picture_as_pdf, size: 20),
                            label: const Text('PDF generieren und öffnen', style: TextStyle(fontSize: 14)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green.shade700,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text('ATS-optimiert: Einfaches Layout, Standard-Schriftart, keine Grafiken', style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontStyle: FontStyle.italic)),
                      ]),
                    )
                  : const Center(child: CircularProgressIndicator()),

              // === TAB 2: QUALITÄTSPRÜFUNG ===
              _loaded
                  ? SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        // Score overview
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: _scoreColor().withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: _scoreColor().withValues(alpha: 0.3)),
                          ),
                          child: Row(children: [
                            Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(shape: BoxShape.circle, color: _scoreColor()),
                              child: Center(child: Text('$_score/$_total', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white))),
                            ),
                            const SizedBox(width: 16),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                _score == _total ? 'Ausgezeichnet!' : _score >= _total * 0.8 ? 'Sehr gut!' : _score >= _total * 0.5 ? 'Verbesserungsbedarf' : 'Dringend verbessern',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: _scoreColor()),
                              ),
                              Text(
                                '$_score von $_total Kriterien erfüllt',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ])),
                          ]),
                        ),
                        const SizedBox(height: 16),
                        // Individual checks
                        ..._checks.asMap().entries.map((entry) {
                          final i = entry.key;
                          final check = entry.value;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: check.passed ? Colors.green.shade50 : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: check.passed ? Colors.green.shade200 : Colors.red.shade200),
                            ),
                            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Icon(check.passed ? Icons.check_circle : Icons.cancel, size: 18, color: check.passed ? Colors.green : Colors.red),
                              const SizedBox(width: 8),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text('${i + 1}. ${check.label}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: check.passed ? Colors.green.shade800 : Colors.red.shade800)),
                                Text(check.detail, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                              ])),
                            ]),
                          );
                        }),
                      ]),
                    )
                  : const Center(child: CircularProgressIndicator()),
            ])),
          ]),
        ),
        contentPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      ),
    );
  }

  Widget _previewRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(children: [
        SizedBox(width: 120, child: Text(label, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))),
        Expanded(child: Text(value.isNotEmpty ? value : '–', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
      ]),
    );
  }
}

class _QualityCheck {
  final String label;
  final bool passed;
  final String detail;
  _QualityCheck(this.label, this.passed, this.detail);
}
