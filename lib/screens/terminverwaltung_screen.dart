import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/termin_service.dart';
import '../services/ticket_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../widgets/termin_dialogs.dart';
import '../widgets/eastern.dart';

/// CustomPainter for diagonal stripes (past time slots)
class _DiagonalStripesPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    // Draw diagonal lines from top-left to bottom-right
    const gap = 6.0;
    for (double i = -size.height; i < size.width + size.height; i += gap + 1.0) {
      canvas.drawLine(
        Offset(i, 0),
        Offset(i + size.height, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class TerminverwaltungScreen extends StatefulWidget {
  final String currentMitgliedernummer;

  const TerminverwaltungScreen({
    super.key,
    required this.currentMitgliedernummer,
  });

  @override
  State<TerminverwaltungScreen> createState() => _TerminverwaltungScreenState();
}

class _TerminverwaltungScreenState extends State<TerminverwaltungScreen> {
  final _terminService = TerminService();
  final _apiService = ApiService();
  final _ticketService = TicketService();

  List<Termin> _termine = [];
  List<Map<String, dynamic>> _urlaub = [];
  List<Map<String, dynamic>> _feiertage = [];
  List<User> _users = [];
  List<Ticket> _tickets = [];
  bool _isLoadingTermine = false;
  DateTime _currentWeekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  String _selectedBundesland = 'ALL';

  static const Map<String, String> _bundeslaender = {
    'ALL': 'Nur national',
    'BW': 'Baden-Württemberg',
    'BY': 'Bayern',
    'BE': 'Berlin',
    'BB': 'Brandenburg',
    'HB': 'Bremen',
    'HH': 'Hamburg',
    'HE': 'Hessen',
    'MV': 'Mecklenburg-Vorpommern',
    'NI': 'Niedersachsen',
    'NW': 'Nordrhein-Westfalen',
    'RP': 'Rheinland-Pfalz',
    'SL': 'Saarland',
    'SN': 'Sachsen',
    'ST': 'Sachsen-Anhalt',
    'SH': 'Schleswig-Holstein',
    'TH': 'Thüringen',
  };

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('de_DE', null);
    _loadData();
  }

  Future<void> _loadData() async {
    _terminService.setToken(_apiService.token);
    await Future.wait([
      _loadTermine(),
      _loadUsers(),
      _loadTickets(),
    ]);
  }

  Future<void> _loadTermine() async {
    setState(() => _isLoadingTermine = true);

    _terminService.setToken(_apiService.token);

    final weekEnd = _currentWeekStart.add(const Duration(days: 7));

    final results = await Future.wait([
      _terminService.getAllTermine(from: _currentWeekStart, to: weekEnd),
      _terminService.getUrlaub(from: _currentWeekStart, to: weekEnd),
      _terminService.getFeiertage(
        from: _currentWeekStart,
        to: weekEnd,
        bundesland: _selectedBundesland,
      ),
    ]);

    final termineResult = results[0];
    final urlaubResult = results[1];
    final feiertageResult = results[2];

    if (mounted && termineResult['success'] == true) {
      final termineList = termineResult['termine'] as List;
      final urlaubList = urlaubResult['success'] == true ? (urlaubResult['urlaub'] as List) : [];
      final feiertageList = feiertageResult['success'] == true ? (feiertageResult['feiertage'] as List) : [];

      setState(() {
        _termine = termineList.map((t) => Termin.fromJson(t)).toList();
        _urlaub = urlaubList.cast<Map<String, dynamic>>();
        _feiertage = feiertageList.cast<Map<String, dynamic>>();
        _isLoadingTermine = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingTermine = false);
    }
  }

  Future<void> _loadUsers() async {
    final result = await _apiService.getUsers();
    if (result['success'] == true && mounted) {
      final usersList = result['users'] as List;
      setState(() {
        _users = usersList.map((u) => User.fromJson(u)).toList();
      });
    }
  }

  Future<void> _loadTickets() async {
    final result = await _ticketService.getAdminTickets(widget.currentMitgliedernummer);
    if (result != null && mounted) {
      setState(() {
        _tickets = result.tickets;
      });
    }
  }

  Future<void> _showUrlaubDialog() async {
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now().add(const Duration(days: 7));
    final beschreibungController = TextEditingController(text: 'Urlaub');

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.beach_access, color: Colors.red),
            SizedBox(width: 8),
            Text('Urlaub hinzufügen'),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: startDate,
                    firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setDialogState(() => startDate = date);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text('Von: ${DateFormat('dd.MM.yyyy').format(startDate)}'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final date = await showDatePicker(
                    context: context,
                    initialDate: endDate,
                    firstDate: startDate,
                    lastDate: DateTime.now().add(const Duration(days: 365)),
                  );
                  if (date != null) setDialogState(() => endDate = date);
                },
                icon: const Icon(Icons.calendar_today),
                label: Text('Bis: ${DateFormat('dd.MM.yyyy').format(endDate)}'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: beschreibungController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Beschreibung',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
          ElevatedButton(
            onPressed: () async {
              final res = await _terminService.createUrlaub(
                startDate: startDate,
                endDate: endDate,
                beschreibung: beschreibungController.text,
              );
              if (ctx.mounted && res['success'] == true) {
                Navigator.pop(ctx, true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Hinzufügen'),
          ),
        ],
      ),
    );

    beschreibungController.dispose();

    if (result == true) {
      _loadTermine();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Urlaub hinzugefügt'), backgroundColor: Colors.green),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dayOfYear = int.parse(DateFormat('D').format(_currentWeekStart));
    final weekNumber = ((dayOfYear - _currentWeekStart.weekday + 10) / 7).floor();
    final weekEnd = _currentWeekStart.add(const Duration(days: 7));
    final weekRange = '${DateFormat('dd.').format(_currentWeekStart)} - ${DateFormat('dd. MMMM yyyy', 'de_DE').format(weekEnd)}';

    // Build holidays map from API data
    final holidays = <String, String>{};
    for (final f in _feiertage) {
      holidays[f['datum']] = f['name'];
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Terminverwaltung'),
        backgroundColor: Colors.green.shade700,
        foregroundColor: Colors.white,
      ),
      body: SeasonalBackground(
        child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Header with navigation
            Row(
              children: [
                Icon(Icons.calendar_month, size: 32, color: Colors.green.shade700),
                const SizedBox(width: 12),
                const Text('Terminverwaltung', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () {
                    setState(() {
                      _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
                    });
                    _loadTermine();
                  },
                  tooltip: 'Vorherige Woche',
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    'KW $weekNumber • $weekRange',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green.shade900),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () {
                    setState(() {
                      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
                    });
                    _loadTermine();
                  },
                  tooltip: 'Nächste Woche',
                ),
                const SizedBox(width: 16),
                // Bundesland dropdown for regional holidays
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: Colors.indigo.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.indigo.shade200),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _selectedBundesland,
                      icon: Icon(Icons.flag, size: 16, color: Colors.indigo.shade700),
                      style: TextStyle(fontSize: 13, color: Colors.indigo.shade900),
                      items: _bundeslaender.entries.map((e) => DropdownMenuItem(
                        value: e.key,
                        child: Text(e.value, style: const TextStyle(fontSize: 13)),
                      )).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedBundesland = val);
                          _loadTermine();
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: _showUrlaubDialog,
                  icon: const Icon(Icons.beach_access),
                  label: const Text('Urlaub'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton.icon(
                  onPressed: () async {
                    await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      builder: (ctx) => CreateTerminDialog(
                        terminService: _terminService,
                        users: _users,
                        tickets: _tickets,
                        onTerminCreated: _loadTermine,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Neuer Termin'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Weekly Calendar Grid
            Expanded(
              child: _isLoadingTermine
                  ? const Center(child: CircularProgressIndicator())
                  : Card(
                      child: Column(
                        children: [
                          // Week days header
                          Container(
                            color: Colors.grey.shade100,
                            child: Row(
                              children: ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag']
                                  .map((day) => Expanded(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(vertical: 12),
                                          decoration: BoxDecoration(
                                            border: Border(right: BorderSide(color: Colors.grey.shade300)),
                                          ),
                                          child: Text(
                                            day,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                            ),
                          ),
                          // Week days grid
                          Expanded(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: List.generate(7, (dayIndex) {
                                final currentDay = _currentWeekStart.add(Duration(days: dayIndex));
                                final isToday = currentDay.year == DateTime.now().year &&
                                    currentDay.month == DateTime.now().month &&
                                    currentDay.day == DateTime.now().day;
                                final isWeekend = dayIndex >= 5;

                                final dayTermine = _termine.where((t) {
                                  return t.terminDate.year == currentDay.year &&
                                      t.terminDate.month == currentDay.month &&
                                      t.terminDate.day == currentDay.day;
                                }).toList();

                                final isUrlaub = _urlaub.any((u) {
                                  final start = DateTime.parse(u['start_date']);
                                  final end = DateTime.parse(u['end_date']);
                                  final dayOnly = DateTime(currentDay.year, currentDay.month, currentDay.day);
                                  // Check if day is within range (inclusive)
                                  return dayOnly.compareTo(start) >= 0 && dayOnly.compareTo(end) <= 0;
                                });

                                final dayStr = DateFormat('yyyy-MM-dd').format(currentDay);
                                final feiertag = holidays[dayStr];
                                final isFeiertag = feiertag != null;

                                return Expanded(
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: isFeiertag
                                          ? Colors.indigo.shade50
                                          : isUrlaub
                                              ? Colors.red.shade50
                                              : (isWeekend ? Colors.grey.shade50 : Colors.white),
                                      border: Border(
                                        right: BorderSide(color: Colors.grey.shade300),
                                        top: BorderSide(color: Colors.grey.shade300),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: isFeiertag
                                                ? Colors.indigo.shade100
                                                : isUrlaub
                                                    ? Colors.red.shade100
                                                    : (isToday ? Colors.blue.shade100 : null),
                                            border: isFeiertag
                                                ? Border.all(color: Colors.indigo.shade700, width: 2)
                                                : isUrlaub
                                                    ? Border.all(color: Colors.red.shade700, width: 2)
                                                    : (isToday ? Border.all(color: Colors.blue.shade700, width: 2) : null),
                                          ),
                                          child: Text(
                                            DateFormat('dd').format(currentDay),
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: (isToday || isUrlaub || isFeiertag) ? FontWeight.bold : FontWeight.normal,
                                              color: isFeiertag
                                                  ? Colors.indigo.shade900
                                                  : isUrlaub
                                                      ? Colors.red.shade900
                                                      : (isToday ? Colors.blue.shade900 : Colors.black),
                                            ),
                                          ),
                                        ),
                                        Expanded(
                                          child: isFeiertag
                                              ? Center(
                                                  child: Column(
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Icon(Icons.flag, color: Colors.indigo.shade700, size: 32),
                                                      const SizedBox(height: 8),
                                                      Text(
                                                        'Feiertag',
                                                        style: TextStyle(
                                                          color: Colors.indigo.shade700,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 4),
                                                      Text(
                                                        feiertag,
                                                        style: TextStyle(
                                                          color: Colors.indigo.shade500,
                                                          fontSize: 10,
                                                        ),
                                                        textAlign: TextAlign.center,
                                                      ),
                                                    ],
                                                  ),
                                                )
                                              : isUrlaub
                                              ? GestureDetector(
                                                  onTap: () async {
                                                    final dayOnly = DateTime(currentDay.year, currentDay.month, currentDay.day);
                                                    final urlaubPeriod = _urlaub.firstWhere((u) {
                                                      final start = DateTime.parse(u['start_date']);
                                                      final end = DateTime.parse(u['end_date']);
                                                      return dayOnly.compareTo(start) >= 0 && dayOnly.compareTo(end) <= 0;
                                                    });

                                                    final start = DateTime.parse(urlaubPeriod['start_date']);
                                                    final end = DateTime.parse(urlaubPeriod['end_date']);
                                                    final isFirstDay = dayOnly.compareTo(start) == 0;
                                                    final isLastDay = dayOnly.compareTo(end) == 0;
                                                    final isSingleDay = start.compareTo(end) == 0;
                                                    final messenger = ScaffoldMessenger.of(context);

                                                    final action = await showDialog<String>(
                                                      context: context,
                                                      builder: (ctx) => AlertDialog(
                                                        title: Text('Urlaub: ${DateFormat('dd.MM.yyyy').format(dayOnly)}'),
                                                        content: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text('${urlaubPeriod['beschreibung']}', style: const TextStyle(fontWeight: FontWeight.bold)),
                                                            const SizedBox(height: 8),
                                                            Text('Periode: ${DateFormat('dd.MM.yyyy').format(start)} - ${DateFormat('dd.MM.yyyy').format(end)}'),
                                                            const Divider(height: 24),
                                                            const Text('Was möchten Sie tun?', style: TextStyle(fontWeight: FontWeight.bold)),
                                                          ],
                                                        ),
                                                        actions: [
                                                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Abbrechen')),
                                                          if (isSingleDay)
                                                            ElevatedButton(
                                                              onPressed: () => Navigator.pop(ctx, 'delete'),
                                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                              child: const Text('Löschen'),
                                                            )
                                                          else ...[
                                                            if (isFirstDay)
                                                              ElevatedButton(
                                                                onPressed: () => Navigator.pop(ctx, 'remove_first'),
                                                                child: const Text('Erste Tag entfernen'),
                                                              ),
                                                            if (isLastDay)
                                                              ElevatedButton(
                                                                onPressed: () => Navigator.pop(ctx, 'remove_last'),
                                                                child: const Text('Letzte Tag entfernen'),
                                                              ),
                                                            if (!isFirstDay && !isLastDay)
                                                              const Text('Mittlere Tag - bitte gesamte Periode löschen', style: TextStyle(fontSize: 12, color: Colors.grey)),
                                                            ElevatedButton(
                                                              onPressed: () => Navigator.pop(ctx, 'delete'),
                                                              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                                              child: const Text('Gesamte Periode löschen'),
                                                            ),
                                                          ],
                                                        ],
                                                      ),
                                                    );

                                                    if (action == 'remove_first') {
                                                      final newStart = start.add(const Duration(days: 1));
                                                      final res = await _terminService.updateUrlaub(
                                                        urlaubId: urlaubPeriod['id'],
                                                        startDate: newStart,
                                                        endDate: end,
                                                      );
                                                      if (res['success'] == true) {
                                                        _loadTermine();
                                                        messenger.showSnackBar(const SnackBar(content: Text('Tag entfernt'), backgroundColor: Colors.green));
                                                      }
                                                    } else if (action == 'remove_last') {
                                                      final newEnd = end.subtract(const Duration(days: 1));
                                                      final res = await _terminService.updateUrlaub(
                                                        urlaubId: urlaubPeriod['id'],
                                                        startDate: start,
                                                        endDate: newEnd,
                                                      );
                                                      if (res['success'] == true) {
                                                        _loadTermine();
                                                        messenger.showSnackBar(const SnackBar(content: Text('Tag entfernt'), backgroundColor: Colors.green));
                                                      }
                                                    } else if (action == 'delete') {
                                                      final res = await _terminService.deleteUrlaub(urlaubPeriod['id']);
                                                      if (res['success'] == true) {
                                                        _loadTermine();
                                                        messenger.showSnackBar(const SnackBar(content: Text('Urlaub gelöscht'), backgroundColor: Colors.green));
                                                      }
                                                    }
                                                  },
                                                  child: Center(
                                                    child: Column(
                                                      mainAxisAlignment: MainAxisAlignment.center,
                                                      children: [
                                                        Icon(Icons.beach_access, color: Colors.red.shade700, size: 32),
                                                        const SizedBox(height: 8),
                                                        Text(
                                                          'Urlaub',
                                                          style: TextStyle(
                                                            color: Colors.red.shade700,
                                                            fontWeight: FontWeight.bold,
                                                            fontSize: 14,
                                                          ),
                                                        ),
                                                        const SizedBox(height: 4),
                                                        Text(
                                                          '(Click)',
                                                          style: TextStyle(
                                                            color: Colors.red.shade400,
                                                            fontSize: 10,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                )
                                              : ListView(
                                                  padding: const EdgeInsets.all(4),
                                                  children: [
                                                    _buildTimeSlot(currentDay, 8, dayTermine),
                                                    _buildTimeSlot(currentDay, 9, dayTermine),
                                                    _buildTimeSlot(currentDay, 10, dayTermine),
                                                    _buildTimeSlot(currentDay, 11, dayTermine),
                                                    _buildTimeSlot(currentDay, 12, dayTermine),
                                                    _buildTimeSlot(currentDay, 13, dayTermine),
                                                    _buildTimeSlot(currentDay, 14, dayTermine),
                                                    _buildTimeSlot(currentDay, 15, dayTermine),
                                                    _buildTimeSlot(currentDay, 16, dayTermine),
                                                    _buildTimeSlot(currentDay, 17, dayTermine),
                                                    _buildTimeSlot(currentDay, 18, dayTermine),
                                                    _buildTimeSlot(currentDay, 19, dayTermine),
                                                  ],
                                                ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }),
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Check if a time slot is in the past
  bool _isSlotPassed(DateTime date, int hour) {
    final now = DateTime.now();
    final slotDateTime = DateTime(date.year, date.month, date.day, hour);

    // If the slot date+time is before now, it's passed
    return slotDateTime.isBefore(now);
  }

  /// Build a cell for past time slots with diagonal stripes
  Widget _buildPastSlotCell(int hour) {
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade200,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(
          painter: _DiagonalStripesPainter(),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Text(
              '$hour:00',
              style: TextStyle(
                fontSize: 11,
                color: Colors.grey.shade500,
                fontWeight: FontWeight.w500,
                decoration: TextDecoration.lineThrough,
                decorationColor: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTimeSlot(DateTime day, int hour, List<Termin> dayTermine) {
    final slotStart = DateTime(day.year, day.month, day.day, hour);
    final slotEnd = DateTime(day.year, day.month, day.day, hour + 1);

    // Find ALL termine that cover this hour slot
    final termine = dayTermine.where((t) {
      return t.terminDate.isBefore(slotEnd) && t.terminEndTime.isAfter(slotStart);
    }).toList();

    final isPast = _isSlotPassed(day, hour);

    // If there are termine covering this slot, show them
    if (termine.isNotEmpty) {
      Widget buildSingleTerminCard(Termin termin, {bool compact = false}) {
        final isStartSlot = termin.terminDate.hour == hour;
        final durationHours = '${DateFormat('HH:mm').format(termin.terminDate)} - ${DateFormat('HH:mm').format(termin.terminEndTime)}';

        return GestureDetector(
          onTap: () async {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (ctx) => EditTerminDialog(
                termin: termin,
                terminService: _terminService,
                users: _users,
                tickets: _tickets,
                onTerminUpdated: _loadTermine,
                currentMitgliedernummer: widget.currentMitgliedernummer,
              ),
            );
          },
          child: Container(
            padding: EdgeInsets.all(compact ? 4 : 8),
            decoration: BoxDecoration(
              color: isPast
                  ? Colors.grey.shade200
                  : termin.categoryColor.withValues(alpha: isStartSlot ? 0.2 : 0.1),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: isPast
                    ? Colors.grey.shade400
                    : termin.categoryColor.withValues(alpha: 0.4),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isStartSlot) ...[
                  Text(
                    durationHours,
                    style: TextStyle(
                      fontSize: compact ? 10 : 12,
                      fontWeight: FontWeight.bold,
                      color: isPast ? Colors.grey.shade500 : termin.categoryColor,
                      decoration: isPast ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.grey.shade500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    termin.title,
                    style: TextStyle(
                      fontSize: compact ? 9 : 11,
                      fontWeight: FontWeight.w600,
                      color: isPast ? Colors.grey.shade500 : null,
                      decoration: isPast ? TextDecoration.lineThrough : null,
                      decorationColor: Colors.grey.shade500,
                    ),
                    maxLines: compact ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (!compact && termin.totalParticipants != null)
                    Text(
                      '${termin.confirmedCount}/${termin.totalParticipants}',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.grey.shade700,
                      ),
                    ),
                ] else ...[
                  Row(
                    children: [
                      Icon(Icons.more_vert, size: 12, color: isPast ? Colors.grey.shade400 : termin.categoryColor.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          termin.title,
                          style: TextStyle(fontSize: compact ? 9 : 10, color: isPast ? Colors.grey.shade400 : Colors.grey.shade600, fontStyle: FontStyle.italic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      }

      // Single termin: full width
      if (termine.length == 1) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: buildSingleTerminCard(termine.first),
        );
      }

      // Multiple termine: split side by side
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(
          children: termine.map((t) => Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: t == termine.last ? 0 : 2),
              child: buildSingleTerminCard(t, compact: true),
            ),
          )).toList(),
        ),
      );
    }

    // Empty slot - show past styling if passed
    if (isPast) {
      return _buildPastSlotCell(hour);
    }

    // Future empty slot
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Text(
        '$hour:00',
        style: TextStyle(fontSize: 11, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }
}
