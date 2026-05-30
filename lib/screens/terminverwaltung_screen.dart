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
            const SizedBox(height: 12),
            // Legend
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_pin_circle, size: 16, color: Colors.red.shade700),
                      const SizedBox(width: 6),
                      Text(
                        'Wird von ICD360S e.V. begleitet (Übersetzung / Assistenz)',
                        style: TextStyle(fontSize: 12, color: Colors.red.shade900, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.amber.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event, size: 16, color: Colors.amber.shade800),
                      const SizedBox(width: 6),
                      Text(
                        'Ohne Begleitung durch ICD360S e.V.',
                        style: TextStyle(fontSize: 12, color: Colors.amber.shade900, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Weekly Calendar Grid — hours on the LEFT, days × 4 quarters on top.
            Expanded(
              child: _isLoadingTermine
                  ? const Center(child: CircularProgressIndicator())
                  : Card(
                      child: Column(
                        children: [
                          // Two-row header: day name + (:00 :15 :30 :45) subcolumns
                          _buildCalendarHeader(holidays),
                          // Body: one row per hour, with hour label + 7 days × 4 quarter cells
                          Expanded(
                            child: ListView.builder(
                              itemCount: 12,
                              itemBuilder: (ctx, hourIdx) {
                                final hour = 8 + hourIdx;
                                return SizedBox(
                                  height: 56,
                                  child: Row(
                                    children: [
                                      _buildHourLabel(hour),
                                      ...List.generate(7, (dayIdx) {
                                        final day = _currentWeekStart.add(Duration(days: dayIdx));
                                        final dayTermine = _termine.where((t) =>
                                            t.terminDate.year == day.year &&
                                            t.terminDate.month == day.month &&
                                            t.terminDate.day == day.day).toList();
                                        final dayStr = DateFormat('yyyy-MM-dd').format(day);
                                        final feiertag = holidays[dayStr];
                                        final urlaubPeriod = _urlaub.firstWhere(
                                          (u) {
                                            final start = DateTime.parse(u['start_date']);
                                            final end = DateTime.parse(u['end_date']);
                                            final dayOnly = DateTime(day.year, day.month, day.day);
                                            return dayOnly.compareTo(start) >= 0 && dayOnly.compareTo(end) <= 0;
                                          },
                                          orElse: () => <String, dynamic>{},
                                        );
                                        final isWeekend = dayIdx >= 5;
                                        return Expanded(
                                          flex: 4,
                                          child: Row(
                                            children: List.generate(4, (qIdx) {
                                              final minute = qIdx * 15;
                                              final isLastQuarterOfDay = qIdx == 3;
                                              return Expanded(
                                                child: _buildQuarterSlot(
                                                  day,
                                                  hour,
                                                  minute,
                                                  dayTermine,
                                                  feiertagName: feiertag,
                                                  urlaubPeriod: urlaubPeriod.isEmpty ? null : urlaubPeriod,
                                                  isWeekend: isWeekend,
                                                  isLastQuarterOfDay: isLastQuarterOfDay,
                                                ),
                                              );
                                            }),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                );
                              },
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

  /// Top header of the grid: day names (Mo/Di/Mi/…) plus a row of :00 :15 :30 :45
  /// subcolumns under each day. Aligned with `_buildHourLabel` on the left.
  Widget _buildCalendarHeader(Map<String, String> holidays) {
    const dayShort = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return Container(
      color: Colors.grey.shade100,
      child: Row(
        children: [
          // Spacer over the hour column
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            ),
            alignment: Alignment.center,
            child: Text('Uhr', style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
          ),
          ...List.generate(7, (dayIdx) {
            final day = _currentWeekStart.add(Duration(days: dayIdx));
            final isToday = day.year == DateTime.now().year && day.month == DateTime.now().month && day.day == DateTime.now().day;
            final dayStr = DateFormat('yyyy-MM-dd').format(day);
            final isFeiertag = holidays[dayStr] != null;
            final isUrlaub = _urlaub.any((u) {
              final start = DateTime.parse(u['start_date']);
              final end = DateTime.parse(u['end_date']);
              final dayOnly = DateTime(day.year, day.month, day.day);
              return dayOnly.compareTo(start) >= 0 && dayOnly.compareTo(end) <= 0;
            });
            final headerBg = isFeiertag
                ? Colors.indigo.shade100
                : isUrlaub
                    ? Colors.red.shade100
                    : (isToday ? Colors.blue.shade100 : null);
            return Expanded(
              flex: 4,
              child: Container(
                decoration: BoxDecoration(
                  color: headerBg,
                  border: Border(right: BorderSide(color: Colors.grey.shade300)),
                ),
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  children: [
                    Text(
                      '${dayShort[dayIdx]} ${DateFormat('dd.MM').format(day)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isFeiertag
                            ? Colors.indigo.shade900
                            : isUrlaub
                                ? Colors.red.shade900
                                : (isToday ? Colors.blue.shade900 : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: const [
                        Expanded(child: Text(':00', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey))),
                        Expanded(child: Text(':15', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey))),
                        Expanded(child: Text(':30', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey))),
                        Expanded(child: Text(':45', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: Colors.grey))),
                      ],
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

  /// Hour label on the left of each row (8, 9, …, 19).
  Widget _buildHourLabel(int hour) {
    return Container(
      width: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: Text(
        '$hour',
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
      ),
    );
  }

  /// Single 15-min cell in the grid. The cell is the intersection of a day and
  /// a quarter-of-an-hour. Color: red = brauchtMich, yellow = does not need me.
  /// A 30-min appointment spans 2 consecutive cells; details (title + duration)
  /// only appear on the start cell; continuation cells render colored background.
  /// Click opens EditTerminDialog (or Urlaub dialog for vacation cells).
  Widget _buildQuarterSlot(
    DateTime day,
    int hour,
    int minute,
    List<Termin> dayTermine, {
    String? feiertagName,
    Map<String, dynamic>? urlaubPeriod,
    bool isWeekend = false,
    bool isLastQuarterOfDay = false,
  }) {
    final slotStart = DateTime(day.year, day.month, day.day, hour, minute);
    final slotEnd = slotStart.add(const Duration(minutes: 15));
    final isPast = slotStart.isBefore(DateTime.now());
    final rightBorder = BorderSide(
      color: Colors.grey.shade300,
      width: isLastQuarterOfDay ? 1.2 : 0.4,
    );
    final cellBorder = Border(
      right: rightBorder,
      top: BorderSide(color: Colors.grey.shade300, width: 0.6),
    );

    // Feiertag — show indigo background; click does nothing (informational)
    if (feiertagName != null) {
      return Tooltip(
        message: 'Feiertag: $feiertagName',
        child: Container(
          decoration: BoxDecoration(color: Colors.indigo.shade50, border: cellBorder),
          child: (hour == 12 && minute == 0)
              ? Center(child: Icon(Icons.flag, size: 14, color: Colors.indigo.shade400))
              : null,
        ),
      );
    }

    // Urlaub — red background; click opens the urlaub dialog
    if (urlaubPeriod != null) {
      return GestureDetector(
        onTap: () => _showUrlaubEditDialog(urlaubPeriod, DateTime(day.year, day.month, day.day)),
        child: Container(
          decoration: BoxDecoration(color: Colors.red.shade50, border: cellBorder),
          child: (hour == 12 && minute == 0)
              ? Center(child: Icon(Icons.beach_access, size: 14, color: Colors.red.shade400))
              : null,
        ),
      );
    }

    // Appointments covering this slot
    final termine = dayTermine.where((t) {
      return t.terminDate.isBefore(slotEnd) && t.terminEndTime.isAfter(slotStart);
    }).toList();

    if (termine.isNotEmpty) {
      // For overlapping termine: show the most prominent (brauchtMich wins).
      termine.sort((a, b) => (b.brauchtMich ? 1 : 0) - (a.brauchtMich ? 1 : 0));
      final termin = termine.first;
      final isStartSlot = !termin.terminDate.isBefore(slotStart) && termin.terminDate.isBefore(slotEnd);
      final color = termin.brauchtMich ? Colors.red : Colors.amber;
      final shade = isPast ? color.shade200 : color.shade400;

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
          decoration: BoxDecoration(color: shade, border: cellBorder),
          padding: const EdgeInsets.all(2),
          child: isStartSlot
              ? Tooltip(
                  message: '${DateFormat('HH:mm').format(termin.terminDate)}–${DateFormat('HH:mm').format(termin.terminEndTime)}\n${termin.title}',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        DateFormat('HH:mm').format(termin.terminDate),
                        style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isPast ? Colors.grey.shade700 : Colors.black87),
                      ),
                      Expanded(
                        child: Text(
                          termin.title,
                          style: TextStyle(fontSize: 9, color: isPast ? Colors.grey.shade700 : Colors.black87, decoration: isPast ? TextDecoration.lineThrough : null),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
      );
    }

    // Empty slot
    final bgColor = isWeekend ? Colors.grey.shade100 : Colors.white;
    final cell = Container(decoration: BoxDecoration(color: bgColor, border: cellBorder));
    if (isPast) {
      return ClipRect(child: CustomPaint(painter: _DiagonalStripesPainter(), child: cell));
    }
    return cell;
  }

  /// Show the urlaub editing dialog (remove first/last day, delete period).
  Future<void> _showUrlaubEditDialog(Map<String, dynamic> urlaubPeriod, DateTime dayOnly) async {
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
      final res = await _terminService.updateUrlaub(
        urlaubId: urlaubPeriod['id'],
        startDate: start.add(const Duration(days: 1)),
        endDate: end,
      );
      if (res['success'] == true) {
        _loadTermine();
        messenger.showSnackBar(const SnackBar(content: Text('Tag entfernt'), backgroundColor: Colors.green));
      }
    } else if (action == 'remove_last') {
      final res = await _terminService.updateUrlaub(
        urlaubId: urlaubPeriod['id'],
        startDate: start,
        endDate: end.subtract(const Duration(days: 1)),
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
  }
}
