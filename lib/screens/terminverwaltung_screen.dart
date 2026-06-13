import 'dart:math' as math;

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
            // Wochenstatistik der Termin-Nachbearbeitung
            _NachbearbeitungStatsBar(
              key: ValueKey('${_currentWeekStart.toIso8601String()}_stats'),
              terminService: _terminService,
              from: _currentWeekStart,
              to: _currentWeekStart.add(const Duration(days: 6)),
            ),
            const SizedBox(height: 12),
            // Legend — wrap so it stays readable on narrower windows
            Wrap(
              spacing: 8,
              runSpacing: 6,
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
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade200,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade400),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.do_not_disturb_on, size: 16, color: Colors.grey.shade700),
                      const SizedBox(width: 6),
                      Text(
                        '08–12 Vormittag (kein Service)',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade800, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade300),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: Colors.green.shade700),
                      const SizedBox(width: 6),
                      Text(
                        '13–17 Sprechzeiten',
                        style: TextStyle(fontSize: 12, color: Colors.green.shade900, fontWeight: FontWeight.w600),
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
                              itemCount: 11,
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
                                        final dayLanes = _computeLanes(dayTermine);
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
                                                  dayLanes,
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

  /// Assign each termin to a lane (first-fit). Termine in the same lane never
  /// overlap. Lane 0 = leftmost, lane 1 = right of it, etc. brauchtMich-true
  /// termine get sorted earlier so they tend to land in lane 0 (most visible).
  Map<int, int> _computeLanes(List<Termin> dayTermine) {
    final lanes = <int, int>{};
    if (dayTermine.isEmpty) return lanes;
    final sorted = [...dayTermine]..sort((a, b) {
      // brauchtMich first so it gets lane 0
      if (a.brauchtMich != b.brauchtMich) return a.brauchtMich ? -1 : 1;
      // then by start time
      final c = a.terminDate.compareTo(b.terminDate);
      if (c != 0) return c;
      return a.id.compareTo(b.id);
    });
    final laneEnds = <DateTime>[];
    for (final t in sorted) {
      int? lane;
      for (int i = 0; i < laneEnds.length; i++) {
        if (!t.terminDate.isBefore(laneEnds[i])) {
          lane = i;
          laneEnds[i] = t.terminEndTime;
          break;
        }
      }
      lane ??= () { laneEnds.add(t.terminEndTime); return laneEnds.length - 1; }();
      lanes[t.id] = lane;
    }
    return lanes;
  }

  /// Background color of the time zone:
  /// - 8-12 Uhr  = Vormittag, kein Service (grey)
  /// - 13-17 Uhr = Sprechzeiten (light green)
  /// - 18 Uhr    = letzter Slot (default white / weekend grey)
  Color _zoneColor(int hour, bool isWeekend) {
    if (hour >= 8 && hour <= 12) {
      return isWeekend ? Colors.grey.shade300 : Colors.grey.shade200;
    }
    if (hour >= 13 && hour <= 17) {
      return isWeekend ? Colors.green.shade100 : Colors.green.shade50;
    }
    return isWeekend ? Colors.grey.shade100 : Colors.white;
  }

  /// Hour label on the left of each row (8, 9, …, 18). Color matches the zone.
  /// 12 = lunch — adds restaurant icon under the number.
  Widget _buildHourLabel(int hour) {
    final Color bgColor;
    final Color textColor;
    if (hour >= 8 && hour <= 12) {
      bgColor = Colors.grey.shade200;
      textColor = Colors.grey.shade800;
    } else if (hour >= 13 && hour <= 17) {
      bgColor = Colors.green.shade50;
      textColor = Colors.green.shade900;
    } else {
      bgColor = Colors.grey.shade50;
      textColor = Colors.black87;
    }
    return Container(
      width: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(color: Colors.grey.shade300),
          top: BorderSide(color: Colors.grey.shade300),
        ),
      ),
      child: hour == 12
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$hour',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                ),
                Tooltip(
                  message: 'Mittagspause',
                  child: Icon(Icons.restaurant, size: 13, color: Colors.brown.shade600),
                ),
              ],
            )
          : Text(
              '$hour',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
            ),
    );
  }

  /// Single 15-min cell in the grid. The cell is the intersection of a day and
  /// a quarter-of-an-hour. Color: red = brauchtMich, yellow = does not need me.
  /// A 30-min appointment spans 2 consecutive cells; details (title + duration)
  /// only appear on the start cell; continuation cells render colored background.
  /// When N termine overlap in the same cell, the cell is split into N side-by-side
  /// mini-boxes (one per lane). Click opens EditTerminDialog for the clicked box.
  Widget _buildQuarterSlot(
    DateTime day,
    int hour,
    int minute,
    List<Termin> dayTermine,
    Map<int, int> dayLanes, {
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
    final zoneColor = _zoneColor(hour, isWeekend);

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
    final cellTermine = dayTermine.where((t) {
      return t.terminDate.isBefore(slotEnd) && t.terminEndTime.isAfter(slotStart);
    }).toList();

    if (cellTermine.isNotEmpty) {
      // Number of lanes needed for THIS cell = max lane index among termine here + 1.
      // (Not max lanes for the whole day — so a non-conflicting slot stays full width.)
      final laneIdx = cellTermine
          .map((t) => dayLanes[t.id] ?? 0)
          .reduce(math.max);
      final numLanes = laneIdx + 1;

      return Container(
        decoration: BoxDecoration(color: zoneColor, border: cellBorder),
        padding: const EdgeInsets.all(2),
        child: Row(
          children: List.generate(numLanes, (lane) {
            Termin? termin;
            for (final t in cellTermine) {
              if ((dayLanes[t.id] ?? -1) == lane) {
                termin = t;
                break;
              }
            }
            if (termin == null) {
              // Empty lane in this cell (other termin occupies it on neighbour cells).
              return Expanded(child: Container(color: zoneColor));
            }
            return Expanded(child: _buildTerminBox(termin, slotStart, slotEnd, isPast));
          }),
        ),
      );
    }

    // Empty slot — zone color (gray for 8-12, green for 13-17, white/weekend for 18).
    // At 12:00 add a lunch marker icon (one per day column).
    final cell = Container(
      decoration: BoxDecoration(color: zoneColor, border: cellBorder),
      child: (hour == 12 && minute == 0)
          ? Tooltip(
              message: 'Mittagspause',
              child: Center(child: Icon(Icons.restaurant, size: 14, color: Colors.brown.shade400)),
            )
          : null,
    );
    if (isPast) {
      return ClipRect(child: CustomPaint(painter: _DiagonalStripesPainter(), child: cell));
    }
    return cell;
  }

  /// Coloured mini-box for one termin in one lane of a quarter-cell.
  /// Title + time only render on the START quarter; continuation quarters
  /// just paint the colour so the user can see the termin extends.
  Widget _buildTerminBox(Termin termin, DateTime slotStart, DateTime slotEnd, bool isPast) {
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
        margin: const EdgeInsets.symmetric(horizontal: 1),
        color: shade,
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

// ════════════════════════════════════════════════════════════════════════
//  Wochen-Statistik der Termin-Nachbearbeitung
//  Zeigt für alle Termine im Zeitraum [from..to] die Verteilung
//  wahrgenommen / nicht_wahrgenommen / offen + Feedback-Quote +
//  Legende mit Farb-Codes.
// ════════════════════════════════════════════════════════════════════════
class _NachbearbeitungStatsBar extends StatefulWidget {
  final TerminService terminService;
  final DateTime from;
  final DateTime to;
  const _NachbearbeitungStatsBar({super.key, required this.terminService, required this.from, required this.to});
  @override
  State<_NachbearbeitungStatsBar> createState() => _NachbearbeitungStatsBarState();
}

class _NachbearbeitungStatsBarState extends State<_NachbearbeitungStatsBar> {
  int _wahr = 0, _nicht = 0, _offen = 0, _feedback = 0, _gesamt = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await widget.terminService.getTerminStats(from: widget.from, to: widget.to);
      if (r['success'] == true && mounted) {
        setState(() {
          _wahr     = (r['wahrgenommen'] ?? 0) as int;
          _nicht    = (r['nicht_wahrgenommen'] ?? 0) as int;
          _offen    = (r['offen'] ?? 0) as int;
          _feedback = (r['mit_feedback'] ?? 0) as int;
          _gesamt   = (r['gesamt'] ?? 0) as int;
          _loading  = false;
        });
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _loading = false);
  }

  Widget _chip(IconData ic, String label, int value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(ic, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$value', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: color)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.85))),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox(height: 50, child: Center(child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))));
    }
    if (_gesamt == 0) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: Colors.grey.shade600),
          const SizedBox(width: 8),
          Text('Keine Termine in dieser Woche', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart, size: 18, color: Colors.indigo.shade700),
          const SizedBox(width: 6),
          Text('Diese Woche (${_gesamt} Termine)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo.shade900)),
          const Spacer(),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _chip(Icons.check_circle, 'wahrgenommen', _wahr, Colors.green.shade700),
            _chip(Icons.cancel, 'nicht wahrg.', _nicht, Colors.red.shade700),
            _chip(Icons.hourglass_empty, 'offen', _offen, Colors.grey.shade700),
            _chip(Icons.campaign, 'mit Feedback', _feedback, Colors.orange.shade700),
          ]),
        ]),
        const SizedBox(height: 6),
        // Legende
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 2),
          child: Wrap(spacing: 12, runSpacing: 4, children: [
            _legendDot(Colors.green.shade700, 'grün = Mitglied war beim Termin'),
            _legendDot(Colors.red.shade700, 'rot = nicht wahrgenommen (mit Grund)'),
            _legendDot(Colors.grey.shade700, 'grau = noch nicht nachbearbeitet'),
            _legendDot(Colors.orange.shade700, 'orange = Feedback / Rückmeldung erhalten'),
          ]),
        ),
      ]),
    );
  }

  Widget _legendDot(Color c, String t) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 8, height: 8, decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
    const SizedBox(width: 4),
    Text(t, style: TextStyle(fontSize: 10, color: Colors.indigo.shade900)),
  ]);
}
