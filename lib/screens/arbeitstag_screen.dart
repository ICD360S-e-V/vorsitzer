import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/arbeitstag_service.dart';

class ArbeitstagScreen extends StatefulWidget {
  const ArbeitstagScreen({super.key});

  @override
  State<ArbeitstagScreen> createState() => _ArbeitstagScreenState();
}

class _ArbeitstagScreenState extends State<ArbeitstagScreen> {
  final _svc = ArbeitstagService();
  late int _kwYear;
  late int _kwNumber;
  ArbeitstagWoche? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _kwYear = _isoYear(now);
    _kwNumber = _isoWeek(now);
    _load();
  }

  static int _isoWeek(DateTime d) {
    final thursday = d.add(Duration(days: 4 - (d.weekday)));
    final firstThursday = DateTime(thursday.year, 1, 1)
        .add(Duration(days: (4 - DateTime(thursday.year, 1, 1).weekday + 7) % 7));
    return ((thursday.difference(firstThursday).inDays) / 7).floor() + 1;
  }

  static int _isoYear(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
    return thursday.year;
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await _svc.getWoche(kwYear: _kwYear, kwNumber: _kwNumber);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  void _shiftKw(int delta) {
    var monday = DateTime.now();
    if (_data != null) monday = _data!.monday;
    final next = monday.add(Duration(days: 7 * delta));
    setState(() {
      _kwYear = _isoYear(next);
      _kwNumber = _isoWeek(next);
    });
    _load();
  }

  Future<void> _toggleChip(ArbeitstagMember m, String typ) async {
    bool currentlyDone;
    switch (typ) {
      case 'ticket':
        currentlyDone = m.ticketDone;
        break;
      case 'termin':
        currentlyDone = m.terminDone;
        break;
      case 'routine':
      default:
        currentlyDone = m.routineDone;
    }

    if (currentlyDone) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bearbeitung zurücksetzen?'),
          content: Text('Bifa "${_typLabel(typ)}" pentru ${m.name} va fi ștearsă.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Zurücksetzen')),
          ],
        ),
      );
      if (ok != true) return;
      final success = await _svc.bearbeitet(
        kwYear: _kwYear,
        kwNumber: _kwNumber,
        userId: m.userId,
        typ: typ,
        action: 'reset',
      );
      if (success) _load();
    } else {
      final success = await _svc.bearbeitet(
        kwYear: _kwYear,
        kwNumber: _kwNumber,
        userId: m.userId,
        typ: typ,
        action: 'set',
      );
      if (success) _load();
    }
  }

  String _typLabel(String typ) {
    switch (typ) {
      case 'ticket': return 'Ticket';
      case 'termin': return 'Termin';
      case 'routine': return 'Routine';
      default: return typ;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          _buildHeader(theme),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final data = _data;
    final rangeStr = data == null
        ? ''
        : '${DateFormat('dd.MM').format(data.monday)} – ${DateFormat('dd.MM.yyyy').format(data.sunday)}';
    final stats = data?.stats;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: theme.colorScheme.surface,
      child: Row(
        children: [
          IconButton(
            onPressed: () => _shiftKw(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Vorherige KW',
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Arbeitstag – KW $_kwNumber / $_kwYear',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              if (rangeStr.isNotEmpty)
                Text(rangeStr, style: theme.textTheme.bodySmall),
            ],
          ),
          IconButton(
            onPressed: () => _shiftKw(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächste KW',
          ),
          const Spacer(),
          if (stats != null) ...[
            _statChip(
              icon: Icons.check_circle,
              label: '${stats.totalDone} / ${stats.totalMembers} DONE',
              color: Colors.green,
            ),
            const SizedBox(width: 8),
            if (stats.totalUrgent > 0)
              _statChip(
                icon: Icons.warning,
                label: '${stats.totalUrgent} dringend',
                color: Colors.red,
              ),
            const SizedBox(width: 8),
          ],
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Aktualisieren',
          ),
        ],
      ),
    );
  }

  Widget _statChip({required IconData icon, required String label, required Color color}) {
    return Chip(
      avatar: Icon(icon, size: 18, color: color),
      label: Text(label),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.3)),
    );
  }

  Widget _buildBody() {
    if (_loading && _data == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_data == null) {
      return const Center(child: Text('Fehler beim Laden'));
    }
    if (_data!.members.isEmpty) {
      return const Center(child: Text('Keine aktiven Mitglieder'));
    }
    // Split: not-done first (by prio), done at bottom
    final active = _data!.members.where((m) => !m.allDone).toList();
    final done = _data!.members.where((m) => m.allDone).toList();
    return ListView.separated(
      itemCount: active.length + (done.isNotEmpty ? 1 + done.length : 0),
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        if (i < active.length) return _buildRow(active[i]);
        if (i == active.length) return _buildDoneHeader(done.length);
        return _buildRow(done[i - active.length - 1], dimmed: true);
      },
    );
  }

  Widget _buildDoneHeader(int n) {
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text('✓ Erledigt diese KW ($n)',
          style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w600)),
    );
  }

  Color _prioColor(int prio) {
    switch (prio) {
      case 1: return Colors.red;
      case 2: return Colors.orange;
      case 3: return Colors.amber;
      case 4: return Colors.blueGrey;
      default: return Colors.grey;
    }
  }

  Widget _buildRow(ArbeitstagMember m, {bool dimmed = false}) {
    final theme = Theme.of(context);
    final prioColor = _prioColor(m.prioritaet);
    return Opacity(
      opacity: dimmed ? 0.55 : 1.0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Container(
              width: 8, height: 40,
              decoration: BoxDecoration(color: prioColor, borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(m.name.isNotEmpty ? m.name : '${m.vorname ?? ''} ${m.nachname ?? ''}'.trim(),
                      style: theme.textTheme.titleMedium),
                  Row(
                    children: [
                      Text(m.mitgliedernummer, style: theme.textTheme.bodySmall),
                      if (m.prioGrund != null && m.prioGrund!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('• ${m.prioGrund!}',
                            style: theme.textTheme.bodySmall?.copyWith(color: prioColor)),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            _chip('Ticket', Icons.confirmation_number, m.ticketDone, m.openTicketsCount,
                () => _toggleChip(m, 'ticket')),
            const SizedBox(width: 6),
            _chip('Termin', Icons.calendar_month, m.terminDone, m.termineKwCount,
                () => _toggleChip(m, 'termin')),
            const SizedBox(width: 6),
            _chip('Routine', Icons.repeat, m.routineDone, m.routinesPendingCount,
                () => _toggleChip(m, 'routine')),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, IconData icon, bool done, int badgeCount, VoidCallback onTap) {
    final color = done ? Colors.green : Colors.grey;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: done ? Colors.green.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(done ? Icons.check_circle : icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            if (!done && badgeCount > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('$badgeCount',
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
