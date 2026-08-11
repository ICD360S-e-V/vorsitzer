import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../services/ticket_service.dart';
import '../widgets/ticket_details_dialog.dart';
import '../widgets/ticket_dialogs.dart';
import '../widgets/eastern.dart';

class TicketverwaltungScreen extends StatefulWidget {
  final List<Ticket> tickets;
  final TicketStats? ticketStats;
  final bool isLoading;
  final String ticketFilter;
  final String mitgliedernummer;
  final List<User> users;
  final Function() onRefresh;
  final Function(String) onFilterChanged;
  final Function(int, String, {String? scheduledDate}) onTicketAction;
  /// Ticket id to auto-open in details dialog on first frame (deep-link
  /// din Arbeitswochen). Callback `onFocusConsumed` clears the state
  /// carrier în dashboard, ca să nu se re-declanșeze la switch de tab.
  final int? initialFocusTicketId;
  final VoidCallback? onFocusConsumed;

  const TicketverwaltungScreen({
    super.key,
    required this.tickets,
    required this.ticketStats,
    required this.isLoading,
    required this.ticketFilter,
    required this.mitgliedernummer,
    required this.users,
    required this.onRefresh,
    required this.onFilterChanged,
    required this.onTicketAction,
    this.initialFocusTicketId,
    this.onFocusConsumed,
  });

  @override
  State<TicketverwaltungScreen> createState() => _TicketverwaltungScreenState();
}

enum _TicketViewMode { wochenansicht, tagesansicht }

/// Ab dieser Breite passen sieben Tagesspalten nebeneinander.
///
/// ⚠️ Ausgemessen, nicht geschätzt: unterhalb davon bekommt jede Spalte
/// weniger als 90 dp, und eine Ticketkarte braucht allein für Statusabzeichen
/// und Uhrzeit mehr. Auf dem Pixel 8 Pro (448 dp) waren es 57 dp je Spalte —
/// die Tickets wurden gezeichnet, aber vollständig abgeschnitten. Genau das
/// sah aus wie „die Tickets werden nicht angezeigt", obwohl der Server alle
/// 528 fehlerfrei geliefert hatte.
const double _schmalAb = 700;

class _TicketverwaltungScreenState extends State<TicketverwaltungScreen> {
  late DateTime _currentWeekStart;
  _TicketViewMode _viewMode = _TicketViewMode.wochenansicht;
  bool _schmal = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    _currentWeekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
    if (widget.initialFocusTicketId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoOpenFocusTicket());
    }
  }

  void _autoOpenFocusTicket() {
    final id = widget.initialFocusTicketId;
    if (id == null || !mounted) return;
    Ticket? found;
    for (final t in widget.tickets) {
      if (t.id == id) { found = t; break; }
    }
    if (found != null) {
      _showTicketDetailsDialog(context, found);
    }
    widget.onFocusConsumed?.call();
  }

  int _getWeekNumber(DateTime date) {
    final dayOfYear = int.parse(DateFormat('D').format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _schmal = constraints.maxWidth < _schmalAb;
      return _buildInhalt(context);
    });
  }

  Widget _buildInhalt(BuildContext context) {
    final weekNumber = _getWeekNumber(_currentWeekStart);
    final weekEnd = _currentWeekStart.add(const Duration(days: 4)); // Friday
    final weekRange = _schmal
        ? '${DateFormat('dd.MM.').format(_currentWeekStart)} - ${DateFormat('dd.MM.yyyy').format(weekEnd)}'
        : '${DateFormat('dd.').format(_currentWeekStart)} - ${DateFormat('dd. MMMM yyyy', 'de_DE').format(weekEnd)}';

    return SeasonalBackground(
      child: Padding(
        padding: EdgeInsets.all(_schmal ? 10 : 24),
        child: _seite(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with stats — auf schmalen Geräten umgebrochen statt
            // um 794 px über den Rand hinausgeschoben.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.confirmation_number,
                        size: _schmal ? 24 : 32, color: Colors.blue.shade700),
                    const SizedBox(width: 12),
                    // Flexible, weil bei Schriftskalierung 2,0 allein der
                    // Titel breiter wird als das ganze Telefon.
                    Flexible(
                      child: Text(
                        'Ticketverwaltung',
                        style: TextStyle(
                            fontSize: _schmal ? 19 : 24,
                            fontWeight: FontWeight.bold),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                if (widget.ticketStats != null) ...[
                  _buildStatBadge('Gesamt', widget.ticketStats!.total, Colors.blue),
                  _buildStatBadge('Offen', widget.ticketStats!.open, Colors.orange),
                  _buildStatBadge('Erledigt', widget.ticketStats!.done, Colors.green),
                ],
                ElevatedButton.icon(
                  onPressed: () async {
                    final created = await showAdminCreateTicketDialog(
                      context,
                      widget.mitgliedernummer,
                      widget.users,
                    );
                    if (created) widget.onRefresh();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(_schmal ? 'Neu' : 'Neues Ticket'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(
                        horizontal: _schmal ? 10 : 16, vertical: 10),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: widget.onRefresh,
                  tooltip: 'Aktualisieren',
                ),
              ],
            ),
          const SizedBox(height: 16),
          // Filter chips
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildTicketFilterChip('Alle', 'all'),
              _buildTicketFilterChip('Offen', 'open'),
              _buildTicketFilterChip('In Bearbeitung', 'in_progress'),
              _buildTicketFilterChip('Warten Benutzer', 'waiting_member'),
              _buildTicketFilterChip('Warten Mitarbeiter', 'waiting_staff'),
              _buildTicketFilterChip('Warten Behörde', 'waiting_authority'),
              _buildTicketFilterChip('Warten Unterlagen', 'waiting_documents'),
              _buildTicketFilterChip('Erledigt', 'done'),
            ],
          ),
          const SizedBox(height: 16),
          // Week navigation — Wrap statt Row: auf 448 dp lief die Zeile
          // um 558 px über, wodurch die Ansichtsumschaltung unerreichbar war.
          Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () {
                  setState(() {
                    _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
                  });
                },
                tooltip: 'Vorherige Woche',
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Text(
                  'KW $weekNumber  •  $weekRange',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue.shade900),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  setState(() {
                    _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
                  });
                },
                tooltip: 'Nächste Woche',
              ),
              TextButton.icon(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _currentWeekStart = DateTime(now.year, now.month, now.day)
                        .subtract(Duration(days: now.weekday - 1));
                  });
                },
                icon: const Icon(Icons.today, size: 18),
                label: const Text('Heute'),
              ),
              // View mode toggle
              ToggleButtons(
                isSelected: [
                  _viewMode == _TicketViewMode.wochenansicht,
                  _viewMode == _TicketViewMode.tagesansicht,
                ],
                onPressed: (index) {
                  setState(() {
                    _viewMode = index == 0
                        ? _TicketViewMode.wochenansicht
                        : _TicketViewMode.tagesansicht;
                  });
                },
                borderRadius: BorderRadius.circular(8),
                constraints: const BoxConstraints(minHeight: 36),
                children: const [
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Icon(Icons.view_week, size: 16),
                      SizedBox(width: 6),
                      Text('Woche'),
                    ]),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 12),
                    child: Row(children: [
                      Icon(Icons.today, size: 16),
                      SizedBox(width: 6),
                      Text('Heute'),
                    ]),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Content: Weekly grid OR Today timeline
          //
          // ⚠️ Auf schmalen Geräten NICHT in `Expanded`: Kopfzeile, Filter
          // und Wochennavigation wachsen mit der Schriftskalierung, und bei
          // 2,0 belegen sie allein mehr als die Bildschirmhöhe. Ein Expanded
          // darunter bekommt dann eine negative Resthöhe — der Inhalt läuft
          // unten heraus, statt scrollbar zu werden. Deshalb dort die ganze
          // Seite als ein Scrollbereich (siehe `_seite`).
          if (_schmal)
            widget.isLoading
                ? const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _viewMode == _TicketViewMode.wochenansicht
                    ? _buildWeeklyList()
                    : _buildTodayTimeline()
          else
            Expanded(
              child: widget.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _viewMode == _TicketViewMode.wochenansicht
                      ? _buildWeeklyGrid()
                      : _buildTodayTimeline(),
            ),
        ],
      )),
      ),
    );
  }

  /// Umhüllt den Seiteninhalt: schmal scrollbar, breit fest.
  Widget _seite(Widget inhalt) =>
      _schmal ? SingleChildScrollView(child: inhalt) : inhalt;

  /// Die Zeitleiste füllt breit den Rest der Karte, schmal nur ihre Höhe.
  Widget _timelineHuelle(Widget inhalt) =>
      _schmal ? inhalt : Expanded(child: inhalt);

  static const _dayNames = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];

  /// Die Woche als **senkrechte** Liste — ein Tag pro Abschnitt.
  ///
  /// ⚠️ Sieben Spalten nebeneinander sind auf einem Telefon keine Ansicht,
  /// sondern nur sieben abgeschnittene Streifen: bei 448 dp bleiben je 57 dp,
  /// und die Ticketkarte beginnt bereits mit Statuspunkt, Nummer und
  /// Prioritätsabzeichen in einer Zeile. Deshalb hier dieselben Karten,
  /// nur untereinander und in voller Breite.
  Widget _buildWeeklyList() {
    final heute = DateTime.now();
    return Card(
      elevation: 2,
      child: ListView.builder(
        // Liegt innerhalb des Seiten-Scrollbereichs — eigenes Scrollen wäre
        // eine zweite, konkurrierende Scrollachse.
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: 7,
        itemBuilder: (context, dayIndex) {
          final currentDay = _currentWeekStart.add(Duration(days: dayIndex));
          final dayTickets = _getTicketsForDay(currentDay);
          final isToday = _isSameDay(currentDay, heute);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                color: isToday ? Colors.blue.shade100 : Colors.grey.shade100,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_dayNames[dayIndex]}, ${DateFormat('dd.MM.').format(currentDay)}',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: isToday ? Colors.blue.shade900 : Colors.grey.shade800,
                        ),
                      ),
                    ),
                    Text(
                      dayTickets.isEmpty ? '–' : '${dayTickets.length}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                        color: isToday ? Colors.blue.shade900 : Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              if (dayTickets.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
                  child: Text(
                    'Keine Tickets',
                    style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
                  child: Column(
                    children: dayTickets
                        .map((ticket) => _buildTicketCard(context, ticket))
                        .toList(),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWeeklyGrid() {
    const dayNames = _dayNames;
    return Card(
      elevation: 2,
      child: Column(
        children: [
          // Day headers
          Container(
            color: Colors.grey.shade100,
            child: Row(
              children: dayNames
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
          // Day columns
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (dayIndex) {
                final currentDay = _currentWeekStart.add(Duration(days: dayIndex));
                final dayTickets = _getTicketsForDay(currentDay);
                final isToday = _isSameDay(currentDay, DateTime.now());

                return Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: isToday ? Colors.blue.shade50 : Colors.white,
                      border: Border(
                        right: BorderSide(color: Colors.grey.shade300),
                        top: BorderSide(color: Colors.grey.shade300),
                      ),
                    ),
                    child: Column(
                      children: [
                        // Date number
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: isToday ? Colors.blue.shade100 : null,
                            border: isToday ? Border.all(color: Colors.blue.shade300) : null,
                          ),
                          child: Text(
                            DateFormat('dd.MM.').format(currentDay),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontWeight: isToday ? FontWeight.bold : FontWeight.w500,
                              color: isToday ? Colors.blue.shade900 : Colors.grey.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        // Ticket cards
                        Expanded(
                          child: dayTickets.isEmpty
                              ? Center(
                                  child: Text(
                                    'Keine Tickets',
                                    style: TextStyle(color: Colors.grey.shade400, fontSize: 11),
                                  ),
                                )
                              : ListView(
                                  padding: const EdgeInsets.all(4),
                                  children: dayTickets
                                      .map((ticket) => _buildTicketCard(context, ticket))
                                      .toList(),
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
    );
  }

  Widget _buildTodayTimeline() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final todayTickets = _getTicketsForDay(today);
    final dayName = DateFormat('EEEE', 'de_DE').format(today);
    final dateStr = DateFormat('dd. MMMM yyyy', 'de_DE').format(today);

    return Card(
      elevation: 2,
      child: Column(
        children: [
          // Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.blue.shade700,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Row(
              children: [
                const Icon(Icons.today, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Heute — $dayName, $dateStr',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: _schmal ? 14 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withAlpha(40),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${todayTickets.length} ${todayTickets.length == 1 ? 'Ticket' : 'Tickets'}',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          // Timeline
          _timelineHuelle(
            todayTickets.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.check_circle_outline, size: 48, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'Keine Tickets für heute',
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: _schmal,
                    physics: _schmal ? const NeverScrollableScrollPhysics() : null,
                    padding: EdgeInsets.symmetric(
                        vertical: 12, horizontal: _schmal ? 8 : 16),
                    itemCount: todayTickets.length,
                    itemBuilder: (context, index) {
                      final ticket = todayTickets[index];
                      final scheduledTime = ticket.scheduledDate ?? ticket.createdAt;
                      final isPast = scheduledTime.isBefore(now);
                      // isNext = first non-past ticket
                      bool isNext = false;
                      if (!isPast) {
                        if (index == 0) {
                          isNext = true;
                        } else {
                          final prevTime = todayTickets[index - 1].scheduledDate ?? todayTickets[index - 1].createdAt;
                          isNext = prevTime.isBefore(now);
                        }
                      }
                      return _buildTimelineItem(ticket, index, todayTickets.length, isPast, isNext);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(Ticket ticket, int index, int total, bool isPast, bool isNext) {
    final scheduledTime = ticket.scheduledDate ?? ticket.createdAt;
    final statusColor = _getTicketStatusColor(ticket.status);
    final priorityColor = _getTicketPriorityColor(ticket.priority);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Left: Time badge + vertical line
          SizedBox(
            width: 80,
            child: Column(
              children: [
                // Time badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isNext
                        ? Colors.blue.shade700
                        : isPast
                            ? Colors.grey.shade300
                            : Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    ticket.scheduledTimeDisplay.isNotEmpty
                        ? ticket.scheduledTimeDisplay
                        : DateFormat('HH:mm').format(scheduledTime),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: isNext
                          ? Colors.white
                          : isPast
                              ? Colors.grey.shade600
                              : Colors.blue.shade900,
                    ),
                  ),
                ),
                // Vertical line
                if (index < total - 1)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: isPast ? Colors.grey.shade300 : Colors.blue.shade200,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // Right: Ticket card
          Expanded(
            child: GestureDetector(
              onTap: () => _showTicketDetailsDialog(context, ticket),
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isPast ? Colors.grey.shade50 : Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isNext ? Colors.blue.shade400 : statusColor.withAlpha(80),
                    width: isNext ? 2 : 1,
                  ),
                  boxShadow: isNext
                      ? [
                          BoxShadow(
                            color: Colors.blue.withAlpha(30),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : [
                          BoxShadow(
                            color: Colors.black.withAlpha(10),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header row: ID + Status + Priority
                    // Wrap, damit „Warten auf Behörde" neben Nummer und
                    // Priorität nicht aus der Karte läuft.
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: isPast ? Colors.grey : statusColor,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '#${ticket.id}',
                              style: TextStyle(
                                color: isPast ? Colors.grey.shade400 : Colors.grey.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isPast ? Colors.grey : statusColor).withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ticket.statusDisplay,
                            style: TextStyle(
                              color: isPast ? Colors.grey : statusColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isPast ? Colors.grey : priorityColor).withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            ticket.priorityDisplay,
                            style: TextStyle(
                              color: isPast ? Colors.grey : priorityColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    // Subject
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ticket.subject,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 14,
                              color: isPast ? Colors.grey.shade500 : Colors.black87,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (ticket.subjectIsTranslated)
                          Padding(
                            padding: const EdgeInsets.only(left: 4),
                            child: Tooltip(
                              message: ticket.originalSubject ?? '',
                              child: Icon(Icons.translate, size: 12, color: Colors.blue.shade300),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Member name + Time badge
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            ticket.memberName ?? 'Unbekannt',
                            style: TextStyle(
                              color: isPast ? Colors.grey.shade400 : Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (ticket.totalTimeSeconds > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: (isPast ? Colors.grey : Colors.deepOrange).withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.timer_outlined, size: 11, color: isPast ? Colors.grey : Colors.deepOrange.shade700),
                                const SizedBox(width: 3),
                                Text(
                                  ticket.totalTimeDisplay,
                                  style: TextStyle(
                                    color: isPast ? Colors.grey : Colors.deepOrange.shade700,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (ticket.status != 'done') ...[
                      const SizedBox(height: 8),
                      _buildQuickActionRow(ticket, compact: false),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Ticket> _getTicketsForDay(DateTime day) {
    final dayTickets = widget.tickets.where((t) {
      final ticketDate = t.scheduledDate ?? t.createdAt;
      return _isSameDay(ticketDate, day);
    }).toList();
    // Sort chronologically by scheduled time
    dayTickets.sort((a, b) {
      final aDate = a.scheduledDate ?? a.createdAt;
      final bDate = b.scheduledDate ?? b.createdAt;
      return aDate.compareTo(bDate);
    });
    return dayTickets;
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  Widget _buildStatBadge(String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _buildTicketFilterChip(String label, String filter) {
    final isSelected = widget.ticketFilter == filter;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        widget.onFilterChanged(filter);
      },
      selectedColor: Colors.blue.shade100,
      checkmarkColor: Colors.blue.shade700,
    );
  }

  Widget _buildTicketCard(BuildContext context, Ticket ticket) {
    final statusColor = _getTicketStatusColor(ticket.status);
    final priorityColor = _getTicketPriorityColor(ticket.priority);

    return GestureDetector(
      onTap: () => _showTicketDetailsDialog(context, ticket),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: statusColor.withAlpha(100)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withAlpha(15),
              blurRadius: 3,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: Time + ID + Priority
            //
            // ⚠️ Wrap, nicht Row: in einer 57-dp-Spalte lief schon diese
            // Zeile über, und ein Überlauf schneidet ab — er schrumpft nicht.
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              runSpacing: 2,
              children: [
                if (ticket.scheduledTimeDisplay.isNotEmpty)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.access_time, size: 11, color: Colors.blue.shade700),
                      const SizedBox(width: 2),
                      Text(
                        ticket.scheduledTimeDisplay,
                        style: TextStyle(
                          color: Colors.blue.shade700,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: statusColor,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '#${ticket.id}',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: priorityColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    ticket.priorityDisplay,
                    style: TextStyle(color: priorityColor, fontSize: 9, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            // Subject (already translated from server, cached)
            Row(
              children: [
                Expanded(
                  child: Text(
                    ticket.subject,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (ticket.subjectIsTranslated)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Tooltip(
                      message: ticket.originalSubject ?? '',
                      child: Icon(Icons.translate, size: 10, color: Colors.blue.shade300),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            // Member name
            Text(
              ticket.memberName ?? 'Unbekannt',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            // Status badge + Time badge
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(30),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    ticket.statusDisplay,
                    style: TextStyle(
                      color: statusColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (ticket.totalTimeSeconds > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.deepOrange.withAlpha(25),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.timer_outlined, size: 9, color: Colors.deepOrange.shade700),
                        const SizedBox(width: 2),
                        Text(
                          ticket.totalTimeDisplay,
                          style: TextStyle(
                            color: Colors.deepOrange.shade700,
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            if (ticket.status != 'done') ...[
              const SizedBox(height: 6),
              _buildQuickActionRow(ticket, compact: true),
            ],
          ],
        ),
      ),
    );
  }

  Color _getTicketStatusColor(String status) {
    switch (status) {
      case 'open':
        return Colors.orange;
      case 'in_progress':
        return Colors.purple;
      case 'waiting_member':
        return Colors.blue;
      case 'waiting_staff':
        return Colors.teal;
      case 'waiting_authority':
        return Colors.indigo;
      case 'waiting_documents':
        return Colors.brown;
      case 'done':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Color _getTicketPriorityColor(String priority) {
    switch (priority) {
      case 'high':
        return Colors.red;
      case 'medium':
        return Colors.orange;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  String _calcSnoozeDate(Ticket ticket) {
    // Snooze relative to the ticket's existing scheduled date — NOT to today.
    // A ticket scheduled for 05.07.2026 must shift to 12.07.2026 when the
    // user taps "+1 Woche"; previously the base was DateTime.now(), so a
    // ticket already in the future would jump back to today+7 instead of
    // moving forward by a week.
    final base = ticket.scheduledDate ?? DateTime.now();
    final target = DateTime(base.year, base.month, base.day).add(const Duration(days: 7));
    final dt = DateTime(target.year, target.month, target.day, base.hour, base.minute);
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(dt);
  }

  Widget _buildQuickActionRow(Ticket ticket, {required bool compact}) {
    if (ticket.status == 'done') return const SizedBox.shrink();
    final iconSize = compact ? 14.0 : 16.0;
    final btnPadding = compact
        ? const EdgeInsets.symmetric(horizontal: 6, vertical: 2)
        : const EdgeInsets.symmetric(horizontal: 8, vertical: 4);
    final btnFontSize = compact ? 10.0 : 12.0;

    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 6,
      runSpacing: 4,
      children: [
        Tooltip(
          message: 'Erledigt',
          child: InkWell(
            onTap: () => widget.onTicketAction(ticket.id, 'done'),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: btnPadding,
              decoration: BoxDecoration(
                color: Colors.green.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.green.withAlpha(120)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: iconSize, color: Colors.green.shade700),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text('Erledigt',
                        style: TextStyle(
                            color: Colors.green.shade700, fontSize: btnFontSize, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ),
        Tooltip(
          message: '+1 Woche verschieben',
          child: InkWell(
            onTap: () => widget.onTicketAction(
              ticket.id,
              'set_scheduled_date',
              scheduledDate: _calcSnoozeDate(ticket),
            ),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: btnPadding,
              decoration: BoxDecoration(
                color: Colors.blue.withAlpha(30),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.blue.withAlpha(120)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.east, size: iconSize, color: Colors.blue.shade700),
                  if (!compact) ...[
                    const SizedBox(width: 4),
                    Text('+1 Woche',
                        style: TextStyle(
                            color: Colors.blue.shade700, fontSize: btnFontSize, fontWeight: FontWeight.w600)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _showTicketDetailsDialog(BuildContext context, Ticket ticket) {
    showDialog(
      context: context,
      builder: (context) => TicketDetailsDialog(
        ticket: ticket,
        mitgliedernummer: widget.mitgliedernummer,
        onTicketAction: widget.onTicketAction,
      ),
    ).then((_) => widget.onRefresh());
  }
}
