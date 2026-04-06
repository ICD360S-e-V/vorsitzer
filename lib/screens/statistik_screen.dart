import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/ticket_service.dart';
import '../models/user.dart';
import '../widgets/eastern.dart';

class StatistikScreen extends StatefulWidget {
  final ApiService apiService;
  final List<User> users;
  final String currentMitgliedernummer;

  const StatistikScreen({
    super.key,
    required this.apiService,
    required this.users,
    required this.currentMitgliedernummer,
  });

  @override
  State<StatistikScreen> createState() => _StatistikScreenState();
}

class _StatistikScreenState extends State<StatistikScreen> {
  // Beitrag stats
  Map<String, dynamic> _beitragsStats = {};
  double _beitragProMonat = 0;
  bool _beitragLoading = true;

  // Spenden stats
  int _spendenAnzahl = 0;
  double _spendenTotal = 0;
  int _spendenMitQuittung = 0;
  bool _spendenLoading = true;

  // Arbeitszeit stats
  final TicketService _ticketService = TicketService();
  WeeklyTimeSummary? _weeklyTime;
  bool _arbeitszeitLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([
      _loadBeitragStats(),
      _loadSpendenStats(),
      _loadArbeitszeitStats(),
    ]);
  }

  Future<void> _loadArbeitszeitStats() async {
    try {
      final result = await _ticketService.getWeeklyTimeSummary(
        mitgliedernummer: widget.currentMitgliedernummer,
      );
      if (mounted) {
        setState(() {
          _weeklyTime = result;
          _arbeitszeitLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _arbeitszeitLoading = false);
    }
  }

  Future<void> _loadBeitragStats() async {
    try {
      final result = await widget.apiService.getBeitragszahlungen();
      if (result['success'] == true && mounted) {
        setState(() {
          _beitragsStats = Map<String, dynamic>.from(result['stats'] ?? {});
          _beitragProMonat = (result['beitrag_pro_monat'] ?? 0).toDouble();
          _beitragLoading = false;
        });
      } else if (mounted) {
        setState(() => _beitragLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _beitragLoading = false);
    }
  }

  Future<void> _loadSpendenStats() async {
    try {
      final result = await widget.apiService.getSpenden();
      if (result['success'] == true && mounted) {
        setState(() {
          _spendenAnzahl = result['anzahl'] ?? 0;
          _spendenTotal = (result['total_betrag'] ?? 0).toDouble();
          _spendenMitQuittung = result['mit_quittung'] ?? 0;
          _spendenLoading = false;
        });
      } else if (mounted) {
        setState(() => _spendenLoading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _spendenLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.bar_chart, size: 28, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              const Text(
                'Statistik',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
                onPressed: () {
                  setState(() {
                    _beitragLoading = true;
                    _spendenLoading = true;
                    _arbeitszeitLoading = true;
                  });
                  _loadData();
                },
              ),
            ],
          ),
          const SizedBox(height: 24),
          // 2 rows of 2 cards
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildMitgliederCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildBeitragCard()),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: _buildSpendenCard()),
                      const SizedBox(width: 16),
                      Expanded(child: _buildArbeitszeitCard()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  // ==================== CARD 1: MITGLIEDER ====================

  Widget _buildMitgliederCard() {
    final users = widget.users;
    final total = users.length;
    final aktiv = users.where((u) => u.isActive).length;
    final neu = users.where((u) => u.isNeu).length;
    final gesperrt = users.where((u) => u.isSuspended).length;
    final gekuendigt = users.where((u) => u.isGekuendigt).length;

    final mitglieder = users.where((u) => u.role == 'mitglied').length;
    final vorsitzer = users.where((u) => u.role == 'vorsitzer').length;
    final schatzmeister = users.where((u) => u.role == 'schatzmeister').length;
    final kassierer = users.where((u) => u.role == 'kassierer').length;
    final ehrenmitglied = users.where((u) => u.role == 'ehrenmitglied').length;
    final foerdermitglied = users.where((u) => u.role == 'foerdermitglied').length;

    return _buildStatCard(
      title: 'Mitglieder',
      icon: Icons.people,
      color: Colors.blue,
      children: [
        _statRow(Icons.people, 'Gesamt Benutzer', '$total', Colors.blue),
        _statRow(Icons.check_circle, 'Aktiv', '$aktiv', Colors.green),
        _statRow(Icons.fiber_new, 'Neu', '$neu', Colors.amber.shade700),
        _statRow(Icons.pause_circle, 'Gesperrt', '$gesperrt', Colors.orange),
        _statRow(Icons.exit_to_app, 'Gekündigt', '$gekuendigt', Colors.brown),
        const Divider(height: 24),
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Rollen',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _statRow(Icons.person, 'Mitglieder', '$mitglieder', Colors.blue),
        _statRow(Icons.admin_panel_settings, 'Vorsitzer', '$vorsitzer', Colors.purple),
        _statRow(Icons.account_balance, 'Schatzmeister', '$schatzmeister', Colors.indigo),
        _statRow(Icons.point_of_sale, 'Kassierer', '$kassierer', Colors.teal),
        if (ehrenmitglied > 0)
          _statRow(Icons.star, 'Ehrenmitglieder', '$ehrenmitglied', Colors.amber),
        if (foerdermitglied > 0)
          _statRow(Icons.favorite, 'Fördermitglieder', '$foerdermitglied', Colors.pink),
      ],
    );
  }

  // ==================== CARD 2: MITGLIEDSBEITRAG ====================

  Widget _buildBeitragCard() {
    if (_beitragLoading) {
      return _buildStatCard(
        title: 'Mitgliedsbeitrag',
        icon: Icons.euro,
        color: Colors.indigo,
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    final gesamtMitglieder = _beitragsStats['gesamt_mitglieder'] ?? 0;
    final mitSchulden = _beitragsStats['mitglieder_mit_schulden'] ?? 0;
    final totalSchulden = (_beitragsStats['total_schulden'] ?? 0).toDouble();
    final totalBezahlt = (_beitragsStats['total_bezahlt'] ?? 0).toDouble();

    return _buildStatCard(
      title: 'Mitgliedsbeitrag',
      icon: Icons.euro,
      color: Colors.indigo,
      children: [
        _statRow(Icons.payments, 'Beitrag/Monat', '${_beitragProMonat.toStringAsFixed(2)} €', Colors.indigo),
        const Divider(height: 24),
        _statRow(Icons.people, 'Beitragspflichtig', '$gesamtMitglieder', Colors.blue),
        _statRow(Icons.check_circle, 'Bezahlt gesamt', '${totalBezahlt.toStringAsFixed(2)} €', Colors.green),
        _statRow(Icons.warning_amber, 'Offene Schulden', '${totalSchulden.toStringAsFixed(2)} €', totalSchulden > 0 ? Colors.red : Colors.green),
        _statRow(Icons.person_off, 'Mitglieder mit Schulden', '$mitSchulden', mitSchulden > 0 ? Colors.orange : Colors.green),
      ],
    );
  }

  // ==================== CARD 3: SPENDEN ====================

  Widget _buildSpendenCard() {
    if (_spendenLoading) {
      return _buildStatCard(
        title: 'Spenden',
        icon: Icons.volunteer_activism,
        color: Colors.purple,
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    final durchschnitt = _spendenAnzahl > 0 ? _spendenTotal / _spendenAnzahl : 0.0;

    return _buildStatCard(
      title: 'Spenden',
      icon: Icons.volunteer_activism,
      color: Colors.purple,
      children: [
        _statRow(Icons.tag, 'Anzahl Spenden', '$_spendenAnzahl', Colors.purple),
        _statRow(Icons.euro, 'Gesamtbetrag', '${_spendenTotal.toStringAsFixed(2)} €', Colors.purple.shade700),
        _statRow(Icons.receipt_long, 'Mit Quittung (>300€)', '$_spendenMitQuittung', Colors.green),
        _statRow(Icons.analytics, 'Durchschnitt/Spende', '${durchschnitt.toStringAsFixed(2)} €', Colors.blue),
      ],
    );
  }

  // ==================== CARD 4: ARBEITSZEIT ====================

  Widget _buildArbeitszeitCard() {
    if (_arbeitszeitLoading) {
      return _buildStatCard(
        title: 'Arbeitszeit',
        icon: Icons.timer,
        color: Colors.green,
        children: [
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      );
    }

    final wt = _weeklyTime;
    if (wt == null) {
      return _buildStatCard(
        title: 'Arbeitszeit',
        icon: Icons.timer,
        color: Colors.green,
        children: [
          _statRow(Icons.info_outline, 'Keine Daten', 'N/A', Colors.grey),
        ],
      );
    }

    final progressColor = wt.isOverLimit ? Colors.red : Colors.green;
    final progressValue = wt.progressPercent.clamp(0.0, 1.0);

    return _buildStatCard(
      title: 'Arbeitszeit',
      icon: Icons.timer,
      color: Colors.green,
      children: [
        // KW + date range
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'KW ${wt.kw}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blue.shade700),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${wt.weekStart.substring(8, 10)}.${wt.weekStart.substring(5, 7)}. - ${wt.weekEnd.substring(8, 10)}.${wt.weekEnd.substring(5, 7)}.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const Spacer(),
            if (wt.isOverLimit)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.warning_amber, size: 12, color: Colors.red.shade700),
                    const SizedBox(width: 3),
                    Text('Limit', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red.shade700)),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        // Progress bar
        Row(
          children: [
            Icon(Icons.timer, color: progressColor, size: 18),
            const SizedBox(width: 6),
            Text(
              wt.totalDisplay,
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: progressColor),
            ),
            Text(
              ' / ${wt.maxDisplay}',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: progressValue,
            minHeight: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(progressColor),
          ),
        ),
        const Divider(height: 24),
        // Category breakdown
        _statRow(Icons.directions_car, 'Fahrzeit', wt.summary.fahrzeitDisplay, Colors.blue),
        _statRow(Icons.work, 'Arbeitszeit', wt.summary.arbeitszeitDisplay, Colors.green),
        _statRow(Icons.hourglass_empty, 'Wartezeit', wt.summary.wartezeitDisplay, Colors.orange),
        _statRow(Icons.functions, 'Gesamt', wt.summary.gesamtDisplay, Colors.grey.shade700),
        // Daily breakdown
        if (wt.daily.isNotEmpty) ...[
          const Divider(height: 24),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Tagesübersicht',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          ...wt.daily.where((d) => d.totalSeconds > 0).map((d) {
            final day = d.date.substring(8, 10);
            final month = d.date.substring(5, 7);
            return _statRow(Icons.calendar_today, '$day.$month.', d.display, Colors.blueGrey);
          }),
        ],
      ],
    );
  }

  // ==================== HELPERS ====================

  Widget _buildStatCard({
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: children,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statRow(IconData icon, String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
