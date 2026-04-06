import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../services/logger_service.dart';
import '../widgets/eastern.dart';

final _log = LoggerService();

class FinanzverwaltungScreen extends StatefulWidget {
  const FinanzverwaltungScreen({super.key});

  @override
  State<FinanzverwaltungScreen> createState() => _FinanzverwaltungScreenState();
}

class _FinanzverwaltungScreenState extends State<FinanzverwaltungScreen> with SingleTickerProviderStateMixin {
  final _apiService = ApiService();
  late TabController _tabController;

  // Beitragszahlungen (Übersicht ab Aug 2025)
  List<Map<String, dynamic>> _beitragsListe = [];
  Map<String, dynamic> _beitragsStats = {};
  bool _beitragsLoading = false;
  double _beitragProMonat = 25.0;
  int _anzahlMonate = 0;

  // Banktransaktionen
  List<Map<String, dynamic>> _transaktionen = [];
  double _einnahmen = 0;
  double _ausgaben = 0;
  double _saldo = 0;
  bool _transaktionenLoading = false;
  int? _transaktionenMonat;
  int _transaktionenJahr = DateTime.now().year;
  String? _transaktionenTyp;

  // Spenden
  List<Map<String, dynamic>> _spenden = [];
  double _spendenTotal = 0;
  int _spendenAnzahl = 0;
  int _spendenMitQuittung = 0;
  bool _spendenLoading = false;
  int _spendenJahr = DateTime.now().year;

  // Verein-Daten für Zuwendungsbestätigung (aus Datenbank via API)
  String _vereinName = '';
  String _vereinAdresse = '';
  String _vereinSteuernummer = '';
  String _vereinFinanzamt = '';
  String _vereinFreistellungDatum = '';
  String _vereinFreistellungZeitraum = '';
  String _vereinZweck = '';

  static const _monatNamen = [
    'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
    'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadBeitragszahlungen();
    _loadTransaktionen();
    _loadSpenden();
    _loadVereinSettings();
  }

  Future<void> _loadVereinSettings() async {
    try {
      final result = await _apiService.getVereineinstellungen();
      if (result['success'] == true && result['data'] != null && mounted) {
        final d = result['data'];
        setState(() {
          _vereinName = (d['vereinsname'] ?? '').toString();
          _vereinAdresse = (d['adresse'] ?? '').toString();
          _vereinSteuernummer = (d['steuernummer'] ?? '').toString();
          _vereinFinanzamt = (d['finanzamt'] ?? '').toString();
          _vereinFreistellungDatum = (d['freistellung_datum'] ?? '').toString();
          _vereinFreistellungZeitraum = (d['freistellung_zeitraum'] ?? '').toString();
          _vereinZweck = (d['zweck'] ?? '').toString();
        });
      }
    } catch (e) {
      _log.error('Failed to load Vereineinstellungen: $e', tag: 'FINANZ');
    }
  }

  Future<void> _saveVereinSettings() async {
    try {
      await _apiService.updateVereineinstellungen({
        'vereinsname': _vereinName,
        'adresse': _vereinAdresse,
        'steuernummer': _vereinSteuernummer,
        'finanzamt': _vereinFinanzamt,
        'freistellung_datum': _vereinFreistellungDatum,
        'freistellung_zeitraum': _vereinFreistellungZeitraum,
        'zweck': _vereinZweck,
      });
    } catch (e) {
      _log.error('Failed to save Vereineinstellungen: $e', tag: 'FINANZ');
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadBeitragszahlungen() async {
    setState(() => _beitragsLoading = true);
    try {
      final result = await _apiService.getBeitragszahlungen();
      if (mounted && result['success'] == true) {
        setState(() {
          _beitragsListe = List<Map<String, dynamic>>.from(result['liste'] ?? []);
          _beitragsStats = Map<String, dynamic>.from(result['stats'] ?? {});
          _beitragProMonat = (result['beitrag_pro_monat'] ?? 25).toDouble();
          _anzahlMonate = result['anzahl_monate'] ?? 0;
          _beitragsLoading = false;
        });
        return;
      }
    } catch (e) {
      _log.error('Beitragszahlungen laden fehlgeschlagen: $e', tag: 'FINANZ');
    }
    if (mounted) setState(() => _beitragsLoading = false);
  }

  Future<void> _loadTransaktionen() async {
    setState(() => _transaktionenLoading = true);
    try {
      final result = await _apiService.getBankTransaktionen(
        monat: _transaktionenMonat,
        jahr: _transaktionenJahr,
        typ: _transaktionenTyp,
      );
      if (mounted && result['success'] == true) {
        setState(() {
          _transaktionen = List<Map<String, dynamic>>.from(result['transaktionen'] ?? []);
          _einnahmen = (result['einnahmen'] ?? 0).toDouble();
          _ausgaben = (result['ausgaben'] ?? 0).toDouble();
          _saldo = (result['saldo'] ?? 0).toDouble();
          _transaktionenLoading = false;
        });
        return;
      }
    } catch (e) {
      _log.error('Transaktionen laden fehlgeschlagen: $e', tag: 'FINANZ');
    }
    if (mounted) setState(() => _transaktionenLoading = false);
  }

  Future<void> _loadSpenden() async {
    setState(() => _spendenLoading = true);
    try {
      final result = await _apiService.getSpenden(jahr: _spendenJahr);
      if (mounted && result['success'] == true) {
        setState(() {
          _spenden = List<Map<String, dynamic>>.from(result['spenden'] ?? []);
          _spendenTotal = (result['total_betrag'] ?? 0).toDouble();
          _spendenAnzahl = result['anzahl'] ?? 0;
          _spendenMitQuittung = result['mit_quittung'] ?? 0;
          _spendenLoading = false;
        });
        return;
      }
    } catch (e) {
      _log.error('Spenden laden fehlgeschlagen: $e', tag: 'FINANZ');
    }
    if (mounted) setState(() => _spendenLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                Icon(Icons.account_balance_wallet, size: 28, color: Colors.green.shade700),
                const SizedBox(width: 12),
                const Text('Finanzverwaltung', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.green.shade700,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.green.shade700,
              tabs: const [
                Tab(icon: Icon(Icons.payment), text: 'Beitragszahlung'),
                Tab(icon: Icon(Icons.account_balance), text: 'Banktransaktionen'),
                Tab(icon: Icon(Icons.volunteer_activism), text: 'Spenden'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildBeitragszahlungenTab(),
                _buildTransaktionenTab(),
                _buildSpendenTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // TAB 1: BEITRAGSZAHLUNG - Übersicht ab August 2025 (25€/Monat)
  // =========================================================================

  Widget _buildBeitragszahlungenTab() {
    return Column(
      children: [
        _buildBeitragsHeader(),
        const Divider(height: 1),
        Expanded(
          child: _beitragsLoading
              ? const Center(child: CircularProgressIndicator())
              : _beitragsListe.isEmpty
                  ? const Center(child: Text('Keine Mitglieder gefunden'))
                  : _buildBeitragsTable(),
        ),
      ],
    );
  }

  Widget _buildBeitragsHeader() {
    final gesamtMitglieder = _beitragsStats['gesamt_mitglieder'] ?? 0;
    final mitSchulden = _beitragsStats['mitglieder_mit_schulden'] ?? 0;
    final totalSchulden = (_beitragsStats['total_schulden'] ?? 0).toDouble();
    final totalBezahlt = (_beitragsStats['total_bezahlt'] ?? 0).toDouble();

    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.grey.shade600),
              const SizedBox(width: 8),
              Text(
                'Beitrag: ${_beitragProMonat.toStringAsFixed(0)} €/Monat • ab August 2025 • $_anzahlMonate Monate',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700, fontWeight: FontWeight.w500),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
                onPressed: _loadBeitragszahlungen,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _statChip('Mitglieder', '$gesamtMitglieder', Colors.blue),
              _statChip('Mit Schulden', '$mitSchulden', Colors.red),
              _statChip('Offene Schulden', '${totalSchulden.toStringAsFixed(2)} €', Colors.red.shade800),
              _statChip('Bezahlt', '${totalBezahlt.toStringAsFixed(2)} €', Colors.green),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(color: color, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildBeitragsTable() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _beitragsListe.length,
      itemBuilder: (context, index) {
        final item = _beitragsListe[index];
        final name = item['name'] ?? '';
        final mn = item['mitgliedernummer'] ?? '';
        final schulden = (item['schulden'] ?? 0).toDouble();
        final bezahltMonate = item['bezahlt_monate'] ?? 0;
        final offenMonate = item['offen_monate'] ?? 0;
        final anzahlMonate = item['anzahl_monate'] ?? 0;
        final bezahltBetrag = (item['bezahlt_betrag'] ?? 0).toDouble();

        final hatSchulden = schulden > 0;
        final allesBezahlt = offenMonate == 0;

        Color cardColor;
        IconData cardIcon;
        if (allesBezahlt) {
          cardColor = Colors.green;
          cardIcon = Icons.check_circle;
        } else if (offenMonate >= 3) {
          cardColor = Colors.red;
          cardIcon = Icons.error;
        } else {
          cardColor = Colors.orange;
          cardIcon = Icons.warning_amber;
        }

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: hatSchulden ? BorderSide(color: cardColor.withValues(alpha: 0.3)) : BorderSide.none,
          ),
          child: ExpansionTile(
            leading: CircleAvatar(
              backgroundColor: cardColor.withValues(alpha: 0.15),
              child: Icon(cardIcon, color: cardColor, size: 22),
            ),
            title: Text(name, style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: Text(
              '$mn • $bezahltMonate/$anzahlMonate Monate bezahlt',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (hatSchulden)
                  Text(
                    '-${schulden.toStringAsFixed(2)} €',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.red.shade700),
                  )
                else
                  Text(
                    '${bezahltBetrag.toStringAsFixed(2)} €',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.green.shade700),
                  ),
                Text(
                  hatSchulden ? '$offenMonate Monate offen' : 'Alles bezahlt',
                  style: TextStyle(fontSize: 11, color: hatSchulden ? Colors.red : Colors.green),
                ),
              ],
            ),
            children: [
              _buildMonateDetails(item),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMonateDetails(Map<String, dynamic> item) {
    final monateDetails = List<Map<String, dynamic>>.from(item['monate_details'] ?? []);
    final mn = item['mitgliedernummer'] ?? '';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Column(
        children: [
          const Divider(),
          ...monateDetails.map((monat) {
            final monatLabel = monat['monat'] ?? '';
            final status = monat['status'] ?? 'offen';
            final betrag = (monat['betrag'] ?? 25).toDouble();

            final isBezahlt = status == 'bezahlt' || status == 'befreit';

            // Parse monat/jahr from "MM/YYYY"
            final parts = monatLabel.split('/');
            final monatNum = int.tryParse(parts.isNotEmpty ? parts[0] : '') ?? 1;
            final jahrNum = int.tryParse(parts.length > 1 ? parts[1] : '') ?? 2025;
            final monatName = _monatNamen[monatNum - 1];

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Icon(
                    isBezahlt ? Icons.check_circle : Icons.cancel,
                    size: 18,
                    color: isBezahlt ? Colors.green : Colors.red,
                  ),
                  const SizedBox(width: 8),
                  Text('$monatName $jahrNum', style: const TextStyle(fontSize: 13)),
                  const Spacer(),
                  Text(
                    '${betrag.toStringAsFixed(2)} €',
                    style: TextStyle(
                      fontSize: 13,
                      color: isBezahlt ? Colors.green.shade700 : Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: (isBezahlt ? Colors.green : Colors.red).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      isBezahlt ? (status == 'befreit' ? 'Befreit' : 'Bezahlt') : 'Offen',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isBezahlt ? Colors.green : Colors.red,
                      ),
                    ),
                  ),
                  if (!isBezahlt) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: const Icon(Icons.check, size: 18),
                      tooltip: 'Als bezahlt markieren',
                      color: Colors.green,
                      onPressed: () => _markAsBezahlt(mn, monatNum, jahrNum, betrag),
                    ),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _markAsBezahlt(String mn, int monat, int jahr, double betrag) async {
    try {
      final result = await _apiService.updateBeitragszahlung(
        mitgliedernummer: mn,
        monat: monat,
        jahr: jahr,
        betrag: betrag,
        status: 'bezahlt',
        zahlungsdatum: DateFormat('yyyy-MM-dd').format(DateTime.now()),
      );
      if (result['success'] == true) {
        _loadBeitragszahlungen();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${_monatNamen[monat - 1]} $jahr als bezahlt markiert'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      _log.error('Beitrag mark bezahlt failed: $e', tag: 'FINANZ');
    }
  }

  // =========================================================================
  // TAB 2: BANKTRANSAKTIONEN
  // =========================================================================

  Widget _buildTransaktionenTab() {
    return Column(
      children: [
        _buildTransaktionenHeader(),
        const Divider(height: 1),
        Expanded(
          child: _transaktionenLoading
              ? const Center(child: CircularProgressIndicator())
              : _transaktionen.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.account_balance, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('Keine Transaktionen', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  : _buildTransaktionenList(),
        ),
      ],
    );
  }

  Widget _buildTransaktionenHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _transaktionenJahr--);
                  _loadTransaktionen();
                },
              ),
              Text('$_transaktionenJahr', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _transaktionenJahr++);
                  _loadTransaktionen();
                },
              ),
              const SizedBox(width: 16),
              DropdownButton<int?>(
                value: _transaktionenMonat,
                hint: const Text('Alle Monate'),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('Alle Monate')),
                  for (int i = 1; i <= 12; i++)
                    DropdownMenuItem(value: i, child: Text(_monatNamen[i - 1])),
                ],
                onChanged: (val) {
                  setState(() => _transaktionenMonat = val);
                  _loadTransaktionen();
                },
              ),
              const SizedBox(width: 16),
              DropdownButton<String?>(
                value: _transaktionenTyp,
                hint: const Text('Alle'),
                items: const [
                  DropdownMenuItem<String?>(value: null, child: Text('Alle')),
                  DropdownMenuItem(value: 'einnahme', child: Text('Einnahmen')),
                  DropdownMenuItem(value: 'ausgabe', child: Text('Ausgaben')),
                ],
                onChanged: (val) {
                  setState(() => _transaktionenTyp = val);
                  _loadTransaktionen();
                },
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _showTransaktionDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neue Transaktion'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
                onPressed: _loadTransaktionen,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _statChip('Einnahmen', '${_einnahmen.toStringAsFixed(2)} €', Colors.green),
              _statChip('Ausgaben', '${_ausgaben.toStringAsFixed(2)} €', Colors.red),
              _statChip('Saldo', '${_saldo.toStringAsFixed(2)} €', _saldo >= 0 ? Colors.green.shade800 : Colors.red.shade800),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTransaktionenList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transaktionen.length,
      itemBuilder: (context, index) {
        final t = _transaktionen[index];
        final isEinnahme = t['typ'] == 'einnahme';
        final betrag = double.tryParse(t['betrag']?.toString() ?? '0') ?? 0;
        final datum = t['datum'] ?? '';
        final beschreibung = t['beschreibung'] ?? '';
        final empfaenger = t['empfaenger_absender'] ?? '';
        final kategorie = t['kategorie'] ?? '';

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: (isEinnahme ? Colors.green : Colors.red).withValues(alpha: 0.15),
              child: Icon(
                isEinnahme ? Icons.arrow_downward : Icons.arrow_upward,
                color: isEinnahme ? Colors.green : Colors.red,
                size: 22,
              ),
            ),
            title: Text(
              beschreibung.isNotEmpty ? beschreibung : (isEinnahme ? 'Einnahme' : 'Ausgabe'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [datum, empfaenger, kategorie].where((s) => s.isNotEmpty).join(' • '),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${isEinnahme ? '+' : '-'}${betrag.toStringAsFixed(2)} €',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                    color: isEinnahme ? Colors.green.shade700 : Colors.red.shade700,
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                  tooltip: 'Löschen',
                  onPressed: () => _deleteTransaktion(t),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showTransaktionDialog() {
    final datumController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final betragController = TextEditingController();
    final beschreibungController = TextEditingController();
    final empfaengerController = TextEditingController();
    final kategorieController = TextEditingController();
    final referenzController = TextEditingController();
    String typ = 'einnahme';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.add_card, color: Colors.green.shade700),
              const SizedBox(width: 12),
              const Text('Neue Transaktion'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'einnahme', label: Text('Einnahme'), icon: Icon(Icons.arrow_downward)),
                      ButtonSegment(value: 'ausgabe', label: Text('Ausgabe'), icon: Icon(Icons.arrow_upward)),
                    ],
                    selected: {typ},
                    onSelectionChanged: (set) => setDialogState(() => typ = set.first),
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return typ == 'einnahme' ? Colors.green.shade50 : Colors.red.shade50;
                        }
                        return null;
                      }),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: datumController,
                    decoration: InputDecoration(
                      labelText: 'Datum',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        locale: const Locale('de', 'DE'),
                      );
                      if (picked != null) {
                        datumController.text = DateFormat('yyyy-MM-dd').format(picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: betragController,
                    decoration: InputDecoration(
                      labelText: 'Betrag (€)',
                      prefixIcon: const Icon(Icons.euro),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: beschreibungController,
                    decoration: InputDecoration(
                      labelText: 'Beschreibung',
                      prefixIcon: const Icon(Icons.description),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: empfaengerController,
                    decoration: InputDecoration(
                      labelText: typ == 'einnahme' ? 'Absender' : 'Empfänger',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: kategorieController,
                    decoration: InputDecoration(
                      labelText: 'Kategorie',
                      prefixIcon: const Icon(Icons.category),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'z.B. Mitgliedsbeitrag, Miete, Spende...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: referenzController,
                    decoration: InputDecoration(
                      labelText: 'Referenz / Verwendungszweck',
                      prefixIcon: const Icon(Icons.tag),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final betrag = double.tryParse(betragController.text);
                if (betrag == null || betrag <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Bitte gültigen Betrag eingeben'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                try {
                  final result = await _apiService.createBankTransaktion(
                    datum: datumController.text,
                    betrag: betrag,
                    typ: typ,
                    kategorie: kategorieController.text.isNotEmpty ? kategorieController.text : null,
                    beschreibung: beschreibungController.text.isNotEmpty ? beschreibungController.text : null,
                    empfaengerAbsender: empfaengerController.text.isNotEmpty ? empfaengerController.text : null,
                    referenz: referenzController.text.isNotEmpty ? referenzController.text : null,
                  );
                  if (result['success'] == true && ctx.mounted) {
                    Navigator.pop(ctx);
                    _loadTransaktionen();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Transaktion erstellt'), backgroundColor: Colors.green),
                      );
                    }
                  }
                } catch (e) {
                  _log.error('Create transaction failed: $e', tag: 'FINANZ');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteTransaktion(Map<String, dynamic> t) async {
    final id = t['id'];
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transaktion löschen?'),
        content: Text('Möchten Sie die Transaktion "${t['beschreibung'] ?? 'ohne Beschreibung'}" wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final result = await _apiService.deleteBankTransaktion(int.parse(id.toString()));
        if (result['success'] == true) {
          _loadTransaktionen();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Transaktion gelöscht'), backgroundColor: Colors.green),
            );
          }
        }
      } catch (e) {
        _log.error('Delete transaction failed: $e', tag: 'FINANZ');
      }
    }
  }

  // =========================================================================
  // TAB 3: SPENDEN
  // =========================================================================

  Widget _buildSpendenTab() {
    return Column(
      children: [
        _buildSpendenHeader(),
        const Divider(height: 1),
        Expanded(
          child: _spendenLoading
              ? const Center(child: CircularProgressIndicator())
              : _spenden.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.volunteer_activism, size: 64, color: Colors.grey.shade300),
                          const SizedBox(height: 16),
                          Text('Keine Spenden', style: TextStyle(color: Colors.grey.shade500)),
                        ],
                      ),
                    )
                  : _buildSpendenList(),
        ),
      ],
    );
  }

  Widget _buildSpendenHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      color: Colors.grey.shade50,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() => _spendenJahr--);
                  _loadSpenden();
                },
              ),
              Text('$_spendenJahr', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() => _spendenJahr++);
                  _loadSpenden();
                },
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _showVereinSettingsDialog,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Vereinsdaten'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _showSpendeDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neue Spende'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
                onPressed: _loadSpenden,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _statChip('Spenden', '$_spendenAnzahl', Colors.purple),
              _statChip('Gesamt', '${_spendenTotal.toStringAsFixed(2)} €', Colors.purple.shade800),
              _statChip('Mit Quittung', '$_spendenMitQuittung', Colors.green),
            ],
          ),
          const SizedBox(height: 12),
          // 300 EUR Info Banner
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Zuwendungsbestätigung nur ab 300,00 € erforderlich. '
                    'Für Spenden bis 300,00 € genügt dem Finanzamt ein Kontoauszug als Nachweis (§ 50 Abs. 4 EStDV).',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade800),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpendenList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _spenden.length,
      itemBuilder: (context, index) {
        final s = _spenden[index];
        final betrag = double.tryParse(s['betrag']?.toString() ?? '0') ?? 0;
        final datum = s['datum'] ?? '';
        final spenderName = s['spender_name'] ?? '';
        final spenderMn = s['spender_mitgliedernummer'] ?? '';
        final spenderAdresse = s['spender_adresse'] ?? '';
        final zweck = s['zweck'] ?? '';
        final quittung = s['quittung_ausgestellt'] == 1 || s['quittung_ausgestellt'] == '1';
        final notiz = s['notiz'] ?? '';
        final kannQuittung = betrag > 300;

        return Card(
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.purple.withValues(alpha: 0.15),
              child: const Icon(Icons.volunteer_activism, color: Colors.purple, size: 22),
            ),
            title: Text(
              spenderName,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              [
                datum,
                if (spenderMn.isNotEmpty) spenderMn,
                if (spenderAdresse.isNotEmpty) spenderAdresse,
                if (zweck.isNotEmpty) zweck,
                if (notiz.isNotEmpty) notiz,
              ].join(' • '),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '+${betrag.toStringAsFixed(2)} €',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.purple.shade700),
                    ),
                    if (quittung)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.receipt_long, size: 12, color: Colors.green.shade600),
                          const SizedBox(width: 2),
                          Text('Quittung', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                        ],
                      )
                    else if (!kannQuittung)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.account_balance, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 2),
                          Text('Kontoauszug', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
                        ],
                      ),
                  ],
                ),
                if (kannQuittung) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.picture_as_pdf, color: Colors.red.shade600, size: 22),
                    tooltip: 'Zuwendungsbestätigung erstellen (PDF)',
                    onPressed: () => _generateZuwendungsbestaetigung(s),
                  ),
                ],
                const SizedBox(width: 4),
                IconButton(
                  icon: Icon(Icons.delete_outline, color: Colors.red.shade300, size: 20),
                  tooltip: 'Löschen',
                  onPressed: () => _deleteSpende(s),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSpendeDialog() {
    final datumController = TextEditingController(text: DateFormat('yyyy-MM-dd').format(DateTime.now()));
    final betragController = TextEditingController();
    final spenderNameController = TextEditingController();
    final spenderAdresseController = TextEditingController();
    final spenderMnController = TextEditingController();
    final zweckController = TextEditingController();
    final notizController = TextEditingController();
    bool quittung = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.volunteer_activism, color: Colors.purple.shade700),
              const SizedBox(width: 12),
              const Text('Neue Spende'),
            ],
          ),
          content: SizedBox(
            width: 450,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: datumController,
                    decoration: InputDecoration(
                      labelText: 'Datum',
                      prefixIcon: const Icon(Icons.calendar_today),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    readOnly: true,
                    onTap: () async {
                      final picked = await showDatePicker(
                        context: ctx,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        locale: const Locale('de', 'DE'),
                      );
                      if (picked != null) {
                        datumController.text = DateFormat('yyyy-MM-dd').format(picked);
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: spenderNameController,
                    decoration: InputDecoration(
                      labelText: 'Spendername *',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: spenderAdresseController,
                    decoration: InputDecoration(
                      labelText: 'Anschrift des Spenders (für Quittung > 300 €)',
                      prefixIcon: const Icon(Icons.home),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'Straße Nr., PLZ Ort',
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: spenderMnController,
                    decoration: InputDecoration(
                      labelText: 'Mitgliedernummer (optional)',
                      prefixIcon: const Icon(Icons.badge),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'Falls der Spender Mitglied ist',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: betragController,
                    decoration: InputDecoration(
                      labelText: 'Betrag (€) *',
                      prefixIcon: const Icon(Icons.euro),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: zweckController,
                    decoration: InputDecoration(
                      labelText: 'Zweck / Verwendung',
                      prefixIcon: const Icon(Icons.description),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      hintText: 'z.B. Allgemeine Spende, Vereinsförderung...',
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: notizController,
                    decoration: InputDecoration(
                      labelText: 'Notiz',
                      prefixIcon: const Icon(Icons.note),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    value: quittung,
                    onChanged: (val) => setDialogState(() => quittung = val ?? false),
                    title: const Text('Spendenquittung ausgestellt'),
                    secondary: Icon(Icons.receipt_long, color: quittung ? Colors.green : Colors.grey),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            ElevatedButton(
              onPressed: () async {
                final betrag = double.tryParse(betragController.text);
                if (betrag == null || betrag <= 0) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Bitte gültigen Betrag eingeben'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                if (spenderNameController.text.isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    const SnackBar(content: Text('Bitte Spendername eingeben'), backgroundColor: Colors.orange),
                  );
                  return;
                }
                try {
                  final result = await _apiService.createSpende(
                    datum: datumController.text,
                    betrag: betrag,
                    spenderName: spenderNameController.text,
                    spenderAdresse: spenderAdresseController.text.isNotEmpty ? spenderAdresseController.text : null,
                    spenderMitgliedernummer: spenderMnController.text.isNotEmpty ? spenderMnController.text : null,
                    zweck: zweckController.text.isNotEmpty ? zweckController.text : null,
                    quittungAusgestellt: quittung,
                    notiz: notizController.text.isNotEmpty ? notizController.text : null,
                  );
                  if (result['success'] == true && ctx.mounted) {
                    Navigator.pop(ctx);
                    _loadSpenden();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Spende erstellt'), backgroundColor: Colors.green),
                      );
                    }
                  }
                } catch (e) {
                  _log.error('Create spende failed: $e', tag: 'FINANZ');
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple.shade700,
                foregroundColor: Colors.white,
              ),
              child: const Text('Speichern'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteSpende(Map<String, dynamic> s) async {
    final id = s['id'];
    if (id == null) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Spende löschen?'),
        content: Text('Möchten Sie die Spende von "${s['spender_name'] ?? ''}" wirklich löschen?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Löschen'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        final result = await _apiService.deleteSpende(int.parse(id.toString()));
        if (result['success'] == true) {
          _loadSpenden();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Spende gelöscht'), backgroundColor: Colors.green),
            );
          }
        }
      } catch (e) {
        _log.error('Delete spende failed: $e', tag: 'FINANZ');
      }
    }
  }

  // =========================================================================
  // VEREINSDATEN SETTINGS (für Zuwendungsbestätigung)
  // =========================================================================

  void _showVereinSettingsDialog() {
    final nameCtrl = TextEditingController(text: _vereinName);
    final adresseCtrl = TextEditingController(text: _vereinAdresse);
    final steuernummerCtrl = TextEditingController(text: _vereinSteuernummer);
    final finanzamtCtrl = TextEditingController(text: _vereinFinanzamt);
    final freistellungDatumCtrl = TextEditingController(text: _vereinFreistellungDatum);
    final freistellungZeitraumCtrl = TextEditingController(text: _vereinFreistellungZeitraum);
    final zweckCtrl = TextEditingController(text: _vereinZweck);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.business, color: Colors.green.shade700),
            const SizedBox(width: 12),
            const Expanded(child: Text('Vereinsdaten für Zuwendungsbestätigung')),
          ],
        ),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Diese Daten werden auf der Zuwendungsbestätigung (Spendequittung) gedruckt. '
                  'Bitte alle Felder ausfüllen.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: 'Vereinsname *',
                    prefixIcon: const Icon(Icons.business),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. ICD360S e.V.',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: adresseCtrl,
                  decoration: InputDecoration(
                    labelText: 'Vereinsadresse *',
                    prefixIcon: const Icon(Icons.location_on),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'Straße Nr., PLZ Ort',
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: steuernummerCtrl,
                  decoration: InputDecoration(
                    labelText: 'Steuernummer *',
                    prefixIcon: const Icon(Icons.numbers),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. 123/456/78900',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: finanzamtCtrl,
                  decoration: InputDecoration(
                    labelText: 'Zuständiges Finanzamt *',
                    prefixIcon: const Icon(Icons.account_balance),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. Finanzamt München I',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: freistellungDatumCtrl,
                  decoration: InputDecoration(
                    labelText: 'Datum Freistellungsbescheid *',
                    prefixIcon: const Icon(Icons.calendar_today),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. 15.03.2025',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: freistellungZeitraumCtrl,
                  decoration: InputDecoration(
                    labelText: 'Letzter Veranlagungszeitraum *',
                    prefixIcon: const Icon(Icons.date_range),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. 2024',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: zweckCtrl,
                  decoration: InputDecoration(
                    labelText: 'Steuerbegünstigter Zweck *',
                    prefixIcon: const Icon(Icons.flag),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    hintText: 'z.B. Förderung der Bildung und Erziehung',
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () {
              setState(() {
                _vereinName = nameCtrl.text;
                _vereinAdresse = adresseCtrl.text;
                _vereinSteuernummer = steuernummerCtrl.text;
                _vereinFinanzamt = finanzamtCtrl.text;
                _vereinFreistellungDatum = freistellungDatumCtrl.text;
                _vereinFreistellungZeitraum = freistellungZeitraumCtrl.text;
                _vereinZweck = zweckCtrl.text;
              });
              _saveVereinSettings();
              Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Vereinsdaten gespeichert'), backgroundColor: Colors.green),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // ZUWENDUNGSBESTÄTIGUNG PDF GENERATION
  // =========================================================================

  Future<void> _generateZuwendungsbestaetigung(Map<String, dynamic> spende) async {
    // Validiere Vereinsdaten
    if (_vereinName.isEmpty || _vereinAdresse.isEmpty || _vereinSteuernummer.isEmpty ||
        _vereinFinanzamt.isEmpty || _vereinFreistellungDatum.isEmpty || _vereinZweck.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Bitte zuerst Vereinsdaten ausfüllen (Button "Vereinsdaten")'),
            backgroundColor: Colors.orange,
            action: SnackBarAction(
              label: 'Ausfüllen',
              textColor: Colors.white,
              onPressed: _showVereinSettingsDialog,
            ),
          ),
        );
      }
      return;
    }

    final betrag = double.tryParse(spende['betrag']?.toString() ?? '0') ?? 0;
    final spenderName = spende['spender_name'] ?? '';
    final spenderAdresse = spende['spender_adresse'] ?? '';
    final datum = spende['datum'] ?? '';
    final zweck = spende['zweck'] ?? '';

    if (spenderAdresse.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Anschrift des Spenders fehlt. Bitte Spende bearbeiten und Adresse hinzufügen.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    try {
      final pdf = pw.Document();
      final betragInWorten = _betragInWorten(betrag);
      final heute = DateFormat('dd.MM.yyyy').format(DateTime.now());
      final spendeZweck = zweck.isNotEmpty ? zweck : _vereinZweck;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(40),
          build: (pw.Context context) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Aussteller (Verein)
                pw.Text(
                  _vereinName,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(_vereinAdresse, style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 20),

                // Titel
                pw.Center(
                  child: pw.Text(
                    'Bestätigung über Geldzuwendungen/Mitgliedsbeitrag',
                    style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
                  ),
                ),
                pw.Center(
                  child: pw.Text(
                    'im Sinne des § 10b des Einkommensteuergesetzes an eine der in § 5 Abs. 1 Nr. 9\n'
                    'des Körperschaftsteuergesetzes bezeichneten Körperschaften, Personenvereinigungen\n'
                    'oder Vermögensmassen',
                    style: const pw.TextStyle(fontSize: 9),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
                pw.SizedBox(height: 20),

                // Spender
                _pdfLabelValue('Name und Anschrift des Zuwendenden:', '$spenderName, $spenderAdresse'),
                pw.SizedBox(height: 12),

                // Betrag
                pw.Row(
                  children: [
                    pw.Expanded(
                      child: _pdfLabelValue('Betrag der Zuwendung - in Ziffern:', '${betrag.toStringAsFixed(2)} EUR'),
                    ),
                    pw.Expanded(
                      child: _pdfLabelValue('- in Buchstaben:', betragInWorten),
                    ),
                  ],
                ),
                pw.SizedBox(height: 8),
                _pdfLabelValue('Tag der Zuwendung:', datum),
                pw.SizedBox(height: 12),

                // Verzicht auf Erstattung
                pw.Row(
                  children: [
                    pw.Text('Es handelt sich um den Verzicht auf Erstattung von Aufwendungen:  ',
                        style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Ja [ ]  ', style: const pw.TextStyle(fontSize: 9)),
                    pw.Text('Nein [X]', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 12),

                // Freistellungsbescheid
                pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 9),
                    children: [
                      const pw.TextSpan(text: 'Wir sind wegen '),
                      pw.TextSpan(
                        text: 'Förderung $spendeZweck',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(
                        text: ' nach dem Freistellungsbescheid bzw. nach der Anlage zum '
                            'Körperschaftsteuerbescheid des Finanzamtes ',
                      ),
                      pw.TextSpan(
                        text: _vereinFinanzamt,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(text: ', StNr. '),
                      pw.TextSpan(
                        text: _vereinSteuernummer,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(text: ', vom '),
                      pw.TextSpan(
                        text: _vereinFreistellungDatum,
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(text: ' für den letzten Veranlagungszeitraum '),
                      pw.TextSpan(
                        text: _vereinFreistellungZeitraum.isNotEmpty ? _vereinFreistellungZeitraum : '____',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
                      ),
                      const pw.TextSpan(
                        text: ' nach § 5 Abs. 1 Nr. 9 des Körperschaftsteuergesetzes von der '
                            'Körperschaftsteuer und nach § 3 Nr. 6 des Gewerbesteuergesetzes '
                            'von der Gewerbesteuer befreit.',
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(height: 12),

                // Bestätigung Verwendung
                pw.Text(
                  'Es wird bestätigt, dass die Zuwendung nur zur Förderung $spendeZweck '
                  '(im Sinne der Anlage 1 - zu § 48 Abs. 2 EStDV - Abschnitt A Nr. ____) '
                  'verwendet wird.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 8),

                // Mitgliedsbeitrag-Ausschluss
                pw.Text(
                  'Es wird bestätigt, dass es sich nicht um einen Mitgliedsbeitrag handelt, '
                  'dessen Abzug nach § 10b Abs. 1 des Einkommensteuergesetzes ausgeschlossen ist.',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(height: 16),
                pw.Divider(),
                pw.SizedBox(height: 8),

                // Haftungshinweis (PFLICHT)
                pw.Text(
                  'Hinweis:',
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text(
                  'Wer vorsätzlich oder grob fahrlässig eine unrichtige Zuwendungsbestätigung erstellt '
                  'oder veranlasst, dass Zuwendungen nicht zu den in der Zuwendungsbestätigung angegebenen '
                  'steuerbegünstigten Zwecken verwendet werden, haftet für die entgangene Steuer '
                  '(§ 10b Abs. 4 EStG, § 9 Abs. 3 KStG, § 9 Nr. 5 GewStG).',
                  style: const pw.TextStyle(fontSize: 8),
                ),
                pw.SizedBox(height: 8),
                pw.Text(
                  'Diese Bestätigung wird nicht als Nachweis für die steuerliche Berücksichtigung '
                  'der Zuwendung anerkannt, wenn das Datum des Freistellungsbescheides länger als '
                  '5 Jahre bzw. das Datum der Feststellung der Einhaltung der satzungsmäßigen '
                  'Voraussetzungen nach § 60a Abs. 1 AO länger als 3 Jahre seit Ausstellung '
                  'des Bescheides zurückliegt und zwischenzeitlich kein neuer Bescheid ergangen ist.',
                  style: const pw.TextStyle(fontSize: 8),
                ),

                pw.Spacer(),

                // Unterschrift
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 200,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(width: 0.5)),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Ort, Datum', style: const pw.TextStyle(fontSize: 8)),
                        pw.Text(heute, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                      ],
                    ),
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Container(
                          width: 200,
                          decoration: const pw.BoxDecoration(
                            border: pw.Border(top: pw.BorderSide(width: 0.5)),
                          ),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text('Unterschrift des Zuwendungsempfängers', style: const pw.TextStyle(fontSize: 8)),
                      ],
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      );

      // Save PDF to temp directory
      final output = await getTemporaryDirectory();
      final safeName = spenderName.replaceAll(RegExp(r'[^\w\s-]'), '').replaceAll(' ', '_');
      final file = File('${output.path}/Zuwendungsbestaetigung_${safeName}_$datum.pdf');
      await file.writeAsBytes(await pdf.save());

      // Preview / Print dialog
      if (mounted) {
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Row(
              children: [
                Icon(Icons.picture_as_pdf, color: Colors.red.shade700),
                const SizedBox(width: 12),
                const Expanded(child: Text('Zuwendungsbestätigung')),
              ],
            ),
            content: SizedBox(
              width: 600,
              height: 500,
              child: PdfPreview(
                build: (format) => pdf.save(),
                canChangeOrientation: false,
                canChangePageFormat: false,
                pdfFileName: 'Zuwendungsbestaetigung_${safeName}_$datum.pdf',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  await OpenFilex.open(file.path);
                },
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Öffnen'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        );

        // Mark quittung as ausgestellt
        if (spende['quittung_ausgestellt'] != 1 && spende['quittung_ausgestellt'] != '1') {
          // Reload to reflect changes
          _loadSpenden();
        }
      }
    } catch (e) {
      _log.error('PDF generation failed: $e', tag: 'FINANZ');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('PDF Erstellung fehlgeschlagen: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  pw.Widget _pdfLabelValue(String label, String value) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
        pw.SizedBox(height: 2),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
          ),
          child: pw.Text(value, style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }

  /// Betrag in deutschen Worten (z.B. 1.250,50 -> "Eintausendzweihundertfünfzig Euro und fünfzig Cent")
  String _betragInWorten(double betrag) {
    final euro = betrag.truncate();
    final cent = ((betrag - euro) * 100).round();

    String result = '${_zahlInWorten(euro)} Euro';
    if (cent > 0) {
      result += ' und ${_zahlInWorten(cent)} Cent';
    }
    return result;
  }

  String _zahlInWorten(int zahl) {
    if (zahl == 0) return 'Null';

    const einer = ['', 'ein', 'zwei', 'drei', 'vier', 'fünf', 'sechs', 'sieben', 'acht', 'neun',
      'zehn', 'elf', 'zwölf', 'dreizehn', 'vierzehn', 'fünfzehn', 'sechzehn', 'siebzehn', 'achtzehn', 'neunzehn'];
    const zehner = ['', '', 'zwanzig', 'dreißig', 'vierzig', 'fünfzig', 'sechzig', 'siebzig', 'achtzig', 'neunzig'];

    String result = '';

    if (zahl >= 1000000) {
      final millionen = zahl ~/ 1000000;
      result += millionen == 1 ? 'eine Million ' : '${_zahlInWorten(millionen)} Millionen ';
      zahl %= 1000000;
    }

    if (zahl >= 1000) {
      final tausend = zahl ~/ 1000;
      result += tausend == 1 ? 'eintausend' : '${_zahlInWorten(tausend)}tausend';
      zahl %= 1000;
    }

    if (zahl >= 100) {
      result += '${einer[zahl ~/ 100]}hundert';
      zahl %= 100;
    }

    if (zahl >= 20) {
      final e = zahl % 10;
      if (e > 0) {
        result += '${einer[e]}und';
      }
      result += zehner[zahl ~/ 10];
    } else if (zahl > 0) {
      result += einer[zahl];
    }

    // Capitalize first letter
    if (result.isNotEmpty) {
      result = result[0].toUpperCase() + result.substring(1);
    }

    return result;
  }
}
