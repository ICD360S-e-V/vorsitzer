import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../services/termin_service.dart';
import '../services/termin_weather_service.dart';
import '../services/ticket_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../widgets/termin_dialogs.dart';
import '../widgets/eastern.dart';
import '../widgets/faltbare_kopfleiste.dart';
import '../utils/app_farben.dart';

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
  /// Termin id to auto-open dialog on first frame (deep-link din Arbeitswochen)
  final int? initialFocusTerminId;

  final VoidCallback? onFocusConsumed;

  const TerminverwaltungScreen({
    super.key,
    required this.currentMitgliedernummer,
    this.initialFocusTerminId,
    this.onFocusConsumed,
  });

  @override
  State<TerminverwaltungScreen> createState() => _TerminverwaltungScreenState();
}

class _TerminverwaltungScreenState extends State<TerminverwaltungScreen> {
  final _terminService = TerminService();
  final _terminWeather = TerminWeatherService();
  final _apiService = ApiService();
  final _ticketService = TicketService();

  List<Termin> _termine = [];
  List<Map<String, dynamic>> _urlaub = [];
  List<Map<String, dynamic>> _feiertage = [];
  List<User> _users = [];
  List<Ticket> _tickets = [];
  bool _isLoadingTermine = false;
  int? _pendingFocusTerminId;
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
    _pendingFocusTerminId = widget.initialFocusTerminId;
    _loadData();
  }

  /// Ein NEUES Sprungziel, während der Bildschirm schon steht.
  ///
  /// ⚠️ `initState` läuft genau einmal. Ist die Terminverwaltung bereits
  /// offen — man ist gerade dort, oder man war eben schon einmal —, dann
  /// wechselt das Dashboard nur `initialFocusTerminId`, und ohne diese Stelle
  /// passiert **gar nichts**: kein Dialog, keine Meldung, nicht von einem
  /// Fehlgriff zu unterscheiden.
  ///
  /// Betrifft den Sprung aus einer Benachrichtigung heraus (`focusTerminId`
  /// im Dashboard) — der geht ins Leere, sobald dieser Bildschirm zufällig
  /// schon offen ist.
  ///
  /// ⚠️ Bleibt der Termin trotzdem unauffindbar, liegt er ausserhalb der
  /// geladenen Woche: `_loadTermine` holt nur `_currentWeekStart` + 7 Tage.
  /// Dafür müsste der Sprung den TAG des Termins mitbringen, damit hier auf
  /// die richtige Woche gestellt werden kann; die Benachrichtigung liefert
  /// ihn heute nicht. Offener Punkt, nicht neu.
  @override
  void didUpdateWidget(TerminverwaltungScreen alt) {
    super.didUpdateWidget(alt);
    final id = widget.initialFocusTerminId;
    if (id == null || id == alt.initialFocusTerminId) return;
    _pendingFocusTerminId = id;
    _consumeFocusTerminIfPossible();
  }

  void _consumeFocusTerminIfPossible() {
    final id = _pendingFocusTerminId;
    if (id == null || !mounted) return;
    Termin? found;
    for (final t in _termine) {
      if (t.id == id) { found = t; break; }
    }
    if (found == null) return;
    _pendingFocusTerminId = null;
    widget.onFocusConsumed?.call();
    final termin = found;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => EditTerminDialog(
          termin: termin,
          terminService: _terminService,
          users: _users,
          tickets: _tickets,
          onTerminUpdated: _loadTermine,
          currentMitgliedernummer: widget.currentMitgliedernummer,
          weatherHint: _terminWeather.hintFor(termin.id),
        ),
      );
    });
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
      // ⚠️ `as List` ohne Fragezeichen: antwortet der Server `success: true`
      // ohne den erwarteten Schlüssel, wirft der Cast auf `null` — und zwar
      // aus einem Future heraus, also am Bildschirm vorbei. Der Kalender
      // bliebe wortlos leer. Urlaub und Feiertage sind ohnehin Beiwerk; sie
      // dürfen die Termine nicht mitreißen.
      final termineList = termineResult['termine'] as List? ?? const [];
      final urlaubList = urlaubResult['urlaub'] as List? ?? const [];
      final feiertageList = feiertageResult['feiertage'] as List? ?? const [];

      setState(() {
        _termine = termineList.map((t) => Termin.fromJson(t)).toList();
        _urlaub = urlaubList.cast<Map<String, dynamic>>();
        _feiertage = feiertageList.cast<Map<String, dynamic>>();
        _isLoadingTermine = false;
      });
      _consumeFocusTerminIfPossible();
      // Kick off weather advisory computation in the background — the calendar
      // renders immediately, weather badges pop in a moment later.
      unawaited(_terminWeather.refreshForTermine(_termine).then((_) {
        if (mounted) setState(() {});
      }));
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

    // ⚠️ Die Stundenzeile war fest 56 dp hoch, ihr Inhalt skaliert aber mit
    // der Systemschrift: bei Schriftgröße 2,0 lief die Beschriftung von 12
    // und 18 Uhr (Zahl + Symbol übereinander) um 38 px unten heraus. Android
    // erlaubt 2,0, die App setzt nirgends einen eigenen textScaler — also
    // wächst die Zeile mit. Gedeckelt, damit eine Woche bei großer Schrift
    // nicht ins Endlose läuft; das Raster scrollt ohnehin mit der Seite.
    final schriftFaktor =
        MediaQuery.textScalerOf(context).scale(14) / 14;
    final zeilenHoehe = 56.0 * schriftFaktor.clamp(1.0, 2.2);

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
        child: SingleChildScrollView(
          // Bei doppelter Systemschrift braucht der Inhalt mehr Höhe, als die
          // Fläche hat. Scrollbar statt unten abgeschnitten.
          child: Column(
          children: [
            // Header with navigation
            FaltbareKopfleiste(
              // Bei doppelter Systemschrift passt die Beschriftung des
              // Knopfes allein nicht mehr neben die Überschrift — kein
              // Kürzen hilft da, nur Umbrechen.
              links: [
                Icon(Icons.calendar_month, size: 32, color: F.h(Colors.green, 700)),
                const Text('Terminverwaltung', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              ],
              aktionen: [
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
                    color: F.h(Colors.green, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.green, 200)),
                  ),
                  child: Text(
                    'KW $weekNumber • $weekRange',
                    style: TextStyle(fontWeight: FontWeight.bold, color: F.h(Colors.green, 900)),
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
                // Bundesland dropdown for regional holidays
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    color: F.h(Colors.indigo, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.indigo, 200)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      // Ohne isExpanded richtet sich das Dropdown nach seinem
                      // breitesten Eintrag statt nach dem Feld.
                      isExpanded: true,
                      value: _selectedBundesland,
                      icon: Icon(Icons.flag, size: 16, color: F.h(Colors.indigo, 700)),
                      style: TextStyle(fontSize: 13, color: F.h(Colors.indigo, 900)),
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
                ElevatedButton.icon(
                  onPressed: _showUrlaubDialog,
                  icon: const Icon(Icons.beach_access),
                  label: const Text('Urlaub'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
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
            // Wetter-Warnungen Summary Banner (nur echte Warnungen, keine
            // "schönes Wetter"-Hinweise — dafür gibt es das Emoji in der Zelle)
            if (_terminWeather.hints.values.any((h) => h.hasWarning))
              _buildWeatherHintsSummary(),
            if (_terminWeather.hints.values.any((h) => h.hasWarning))
              const SizedBox(height: 12),
            // Legend — wrap so it stays readable on narrower windows
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: F.h(Colors.red, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.red, 300)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.person_pin_circle, size: 16, color: F.h(Colors.red, 700)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        'Wird von ICD360S e.V. begleitet (Übersetzung / Assistenz)',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.red, 900), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: F.h(Colors.amber, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.amber, 300)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.event, size: 16, color: F.h(Colors.amber, 800)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        'Ohne Begleitung durch ICD360S e.V.',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.amber, 900), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: F.h(Colors.grey, 200),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.grey, 400)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.do_not_disturb_on, size: 16, color: F.h(Colors.grey, 700)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        '08–12 Vormittag (kein Service)',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 800), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: F.h(Colors.green, 50),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: F.h(Colors.green, 300)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.check_circle_outline, size: 16, color: F.h(Colors.green, 700)),
                      const SizedBox(width: 6),
                      Flexible(child: Text(
                        '13–17 Sprechzeiten',
                        style: TextStyle(fontSize: 12, color: F.h(Colors.green, 900), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Weekly Calendar Grid — hours on the LEFT, days × 4 quarters on top.
            //
            // ⚠️ KEIN Expanded hier und keines um die Stundenliste: dieser
            // Bildschirm liegt seit #197 in einem SingleChildScrollView, dort
            // ist die Höhe UNBEGRENZT. Ein Flex-Kind wirft dann
            // „RenderFlex children have non-zero flex but incoming height
            // constraints are unbounded", die Column bekommt keine Größe — und
            // im Release-Build heißt das: der ganze Kalender fehlt wortlos.
            // Genau so waren die Termine unsichtbar, obwohl der Server sie
            // liefert. Das Raster hat eine feste Höhe (11 × 56 dp), also
            // scrollt es nicht selbst, sondern die Seite scrollt es mit.
            _isLoadingTermine
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : Card(
                      child: Column(
                        children: [
                          // Two-row header: day name + (:00 :15 :30 :45) subcolumns
                          _buildCalendarHeader(holidays),
                          // Body: one row per hour, with hour label + 7 days × 4 quarter cells
                          ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: 11,
                              itemBuilder: (ctx, hourIdx) {
                                final hour = 8 + hourIdx;
                                return SizedBox(
                                  height: zeilenHoehe,
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
                        ],
                      ),
                    ),
          ],
        ),
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
      color: F.h(Colors.grey, 100),
      child: Row(
        children: [
          // Spacer over the hour column
          Container(
            width: 44,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: F.h(Colors.grey, 300))),
            ),
            alignment: Alignment.center,
            child: Text('Uhr', style: TextStyle(fontSize: 11, color: F.h(Colors.grey, 600))),
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
                  border: Border(right: BorderSide(color: F.h(Colors.grey, 300))),
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
                            ? F.h(Colors.indigo, 900)
                            : isUrlaub
                                ? F.h(Colors.red, 900)
                                : (isToday ? F.h(Colors.blue, 900) : F.textStark),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(child: Text(':00', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 500)))),
                        Expanded(child: Text(':15', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 500)))),
                        Expanded(child: Text(':30', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 500)))),
                        Expanded(child: Text(':45', textAlign: TextAlign.center, style: TextStyle(fontSize: 9, color: F.h(Colors.grey, 500)))),
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
  /// - 8-11 Uhr  = Vormittag, kein Service (grey)
  /// - 12 Uhr    = Mittagspause (grey + Restaurant-Icon)
  /// - 13-17 Uhr = Sprechzeiten (light green) — letzter buchbarer Slot 17:00
  /// - 18 Uhr    = Abendessen, keine Terminbuchung (orange + dinner_dining-Icon)
  Color _zoneColor(int hour, bool isWeekend) {
    if (hour >= 8 && hour <= 12) {
      return isWeekend ? F.h(Colors.grey, 300) : F.h(Colors.grey, 200);
    }
    if (hour >= 13 && hour <= 17) {
      return isWeekend ? F.h(Colors.green, 100) : F.h(Colors.green, 50);
    }
    if (hour == 18) {
      return isWeekend ? F.h(Colors.orange, 100) : F.h(Colors.orange, 50);
    }
    return isWeekend ? F.h(Colors.grey, 100) : F.flaeche;
  }

  /// Hour label on the left of each row (8, 9, …, 18). Color matches the zone.
  /// 12 = Mittagspause (restaurant icon), 18 = Abendessen (dinner icon).
  Widget _buildHourLabel(int hour) {
    final Color bgColor;
    final Color textColor;
    if (hour >= 8 && hour <= 12) {
      bgColor = F.h(Colors.grey, 200);
      textColor = F.h(Colors.grey, 800);
    } else if (hour >= 13 && hour <= 17) {
      bgColor = F.h(Colors.green, 50);
      textColor = F.h(Colors.green, 900);
    } else if (hour == 18) {
      bgColor = F.h(Colors.orange, 50);
      textColor = F.h(Colors.orange, 900);
    } else {
      bgColor = F.h(Colors.grey, 50);
      textColor = F.textStark;
    }
    return Container(
      width: 44,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          right: BorderSide(color: F.h(Colors.grey, 300)),
          top: BorderSide(color: F.h(Colors.grey, 300)),
        ),
      ),
      child: (hour == 12 || hour == 18)
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$hour',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: textColor),
                ),
                Tooltip(
                  message: hour == 12 ? 'Mittagspause' : 'Abendessen',
                  child: Icon(
                    hour == 12 ? Icons.restaurant : Icons.dinner_dining,
                    size: 13,
                    color: hour == 12 ? F.h(Colors.brown, 600) : F.h(Colors.orange, 700),
                  ),
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
      color: F.h(Colors.grey, 300),
      width: isLastQuarterOfDay ? 1.2 : 0.4,
    );
    final cellBorder = Border(
      right: rightBorder,
      top: BorderSide(color: F.h(Colors.grey, 300), width: 0.6),
    );
    final zoneColor = _zoneColor(hour, isWeekend);

    // Feiertag — show indigo background; click does nothing (informational)
    if (feiertagName != null) {
      return Tooltip(
        message: 'Feiertag: $feiertagName',
        child: Container(
          decoration: BoxDecoration(color: F.h(Colors.indigo, 50), border: cellBorder),
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
          decoration: BoxDecoration(color: F.h(Colors.red, 50), border: cellBorder),
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

    // Empty slot — zone color (gray 8-12, green 13-17, orange 18, white else).
    // At 12:00 = Mittagspause marker, at 18:00 = Abendessen marker.
    final cell = Container(
      decoration: BoxDecoration(color: zoneColor, border: cellBorder),
      child: (hour == 12 && minute == 0)
          ? Tooltip(
              message: 'Mittagspause',
              child: Center(child: Icon(Icons.restaurant, size: 14, color: Colors.brown.shade400)),
            )
          : (hour == 18 && minute == 0)
              ? Tooltip(
                  message: 'Abendessen',
                  child: Center(child: Icon(Icons.dinner_dining, size: 14, color: F.h(Colors.orange, 700))),
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
    // Hilfsmittel-Abholung gets its own teal accent so members spot the
    // pickup window at a glance among regular Termine.
    final isHilfsmittel = termin.rezeptId != null || termin.category == 'sanitaetshaus_abholung';
    final color = isHilfsmittel ? Colors.teal : (termin.brauchtMich ? Colors.red : Colors.amber);
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
            weatherHint: _terminWeather.hintFor(termin.id),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 1),
        color: shade,
        padding: const EdgeInsets.all(2),
        child: isStartSlot
            ? Tooltip(
                message: _buildTooltipText(termin),
                child: Stack(
                  children: [
                    // ⚠️ Die Schrift im Raster wird gedeckelt, sonst nirgends
                    // in der App. Eine Viertelstundenzelle ist gut 25 dp
                    // breit; bei Systemschrift 2,0 wird aus 9 pt 18 pt, und
                    // Uhrzeit plus zwei Titelzeilen liefen um 27 px unten
                    // heraus. Der vollständige Text geht dabei nicht
                    // verloren — er steht im Tooltip und im Dialog, die beide
                    // voll mitskalieren. Ein Raster, das bei großer Schrift
                    // gar nichts mehr zeigt, wäre die schlechtere Hilfe.
                    MediaQuery.withClampedTextScaling(
                      maxScaleFactor: 1.3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('HH:mm').format(termin.terminDate),
                            style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: isPast ? F.h(Colors.grey, 700) : F.textStark),
                          ),
                          // Flexible statt Expanded: in einer Column mit
                          // `MainAxisSize.min` verlangt Expanded die volle
                          // Höhe und hebt das `min` wieder auf.
                          Flexible(
                            child: Text(
                              termin.title,
                              style: TextStyle(fontSize: 9, color: isPast ? F.h(Colors.grey, 700) : F.textStark, decoration: isPast ? TextDecoration.lineThrough : null),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // ── Status-Indicator oben rechts (punct colorat) ──
                    if (termin.feedbackStatus == 'wahrgenommen')
                      const Positioned(top: 0, right: 0, child: _StatusDot(color: Colors.green)),
                    if (termin.feedbackStatus == 'nicht_wahrgenommen')
                      const Positioned(top: 0, right: 0, child: _StatusDot(color: Colors.red)),
                    // ── Hilfsmittel-Indicator oben links ──
                    if (isHilfsmittel)
                      Positioned(
                        top: 0, left: 0,
                        child: Container(
                          padding: const EdgeInsets.all(1),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.8), shape: BoxShape.circle),
                          child: Icon(Icons.medical_services, size: 9, color: F.h(Colors.teal, 800)),
                        ),
                      ),
                    // ── Feedback-Indicator unten rechts (Megafon) ──
                    if (termin.feedbackErhalten)
                      const Positioned(
                        bottom: 0, right: 0,
                        child: Icon(Icons.campaign, size: 11, color: Colors.deepOrange),
                      ),
                    // ── Wetter-Forecast unten links (Emoji für JEDEN Termin) ──
                    if (_terminWeather.hintFor(termin.id) != null)
                      Positioned(
                        bottom: 0, left: 0,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: _terminWeather.hintFor(termin.id)!.hasWarning
                                ? Colors.orange.shade100.withValues(alpha: 0.95)
                                : Colors.white.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(3),
                            border: _terminWeather.hintFor(termin.id)!.hasWarning
                                ? Border.all(color: Colors.orange.shade700, width: 0.8)
                                : null,
                          ),
                          child: Text(
                            _terminWeather.hintFor(termin.id)!.emoji,
                            // Per-widget emoji font fallback — avoids the "black
                            // sun" issue without touching theme-wide kerning.
                            style: const TextStyle(
                              fontSize: 11,
                              fontFamilyFallback: [
                                'Segoe UI Emoji',
                                'Apple Color Emoji',
                                'Noto Color Emoji',
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              )
            : null,
      ),
    );
  }

  /// Tooltip-Text inkl. Nachbearbeitungs-Status, wenn gesetzt.
  String _buildTooltipText(Termin t) {
    final base = '${DateFormat('HH:mm').format(t.terminDate)}–${DateFormat('HH:mm').format(t.terminEndTime)}\n${t.title}';
    final parts = <String>[base];
    if (t.rezeptId != null) parts.add('🏥 Hilfsmittel-Abholung · Rezept #${t.rezeptId}');
    if (t.feedbackStatus == 'wahrgenommen') parts.add('✓ Wahrgenommen');
    if (t.feedbackStatus == 'nicht_wahrgenommen') {
      final g = t.nichtWahrgenommenGrund;
      parts.add('✗ Nicht wahrgenommen${g != null ? " ($g)" : ""}');
    }
    if (t.feedbackErhalten) parts.add('📢 Feedback eingegangen');
    final hint = _terminWeather.hintFor(t.id);
    if (hint != null) {
      parts.add('${hint.emoji} ${hint.subtitle}');
      parts.add('💡 ${hint.recommendation}');
    }
    return parts.join('\n');
  }

  /// Compact banner listing Termine with weather advisories in the next 48h.
  /// The full list lives in the tooltip / edit dialog — this is a nudge.
  Widget _buildWeatherHintsSummary() {
    final now = DateTime.now();
    final upcoming = _terminWeather.hints.values.where((h) {
      if (!h.hasWarning) return false;
      final diff = h.forecastFor.difference(now);
      return diff.inHours >= 0 && diff.inHours <= 48;
    }).toList()
      ..sort((a, b) => a.forecastFor.compareTo(b.forecastFor));

    if (upcoming.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: F.h(Colors.orange, 50),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.orange, 300)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber, color: F.h(Colors.orange, 800), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${upcoming.length} Termin${upcoming.length == 1 ? "" : "e"} '
                  'mit Wetter-Hinweis in den nächsten 48 h',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: F.h(Colors.orange, 900),
                  ),
                ),
                const SizedBox(height: 2),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: upcoming
                      .take(6)
                      .map((h) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: F.flaeche,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: F.h(Colors.orange, 200)),
                            ),
                            child: Text(
                              '${h.emoji} ${h.title}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
        ],
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
              Text('Mittlere Tag - bitte gesamte Periode löschen', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 500))),
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
        decoration: BoxDecoration(color: F.h(Colors.grey, 100), borderRadius: BorderRadius.circular(8)),
        child: Row(children: [
          Icon(Icons.info_outline, size: 16, color: F.h(Colors.grey, 600)),
          const SizedBox(width: 8),
          Flexible(child: Text('Keine Termine in dieser Woche', style: TextStyle(fontSize: 12, color: F.h(Colors.grey, 700)), overflow: TextOverflow.ellipsis)),
        ]),
      );
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: F.h(Colors.indigo, 200)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.bar_chart, size: 18, color: F.h(Colors.indigo, 700)),
          const SizedBox(width: 6),
          Text('Diese Woche ($_gesamt Termine)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: F.h(Colors.indigo, 900))),
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
    Text(t, style: TextStyle(fontSize: 10, color: F.h(Colors.indigo, 900))),
  ]);
}

/// Kleiner farbiger Status-Punkt für die Termin-Kachel (Corner-Indicator).
/// Grün = wahrgenommen, Rot = nicht wahrgenommen.
class _StatusDot extends StatelessWidget {
  final Color color;
  const _StatusDot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 1.2),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 2, spreadRadius: 0.5),
        ],
      ),
    );
  }
}
