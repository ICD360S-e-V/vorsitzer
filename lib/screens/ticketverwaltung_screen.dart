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
  final Function(int, String) onTicketAction;

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
  });

  @override
  State<TicketverwaltungScreen> createState() => _TicketverwaltungScreenState();
}

enum _TicketViewMode { wochenansicht, tagesansicht }

class _TicketverwaltungScreenState extends State<TicketverwaltungScreen> {
  late DateTime _currentWeekStart;
  _TicketViewMode _viewMode = _TicketViewMode.wochenansicht;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    _currentWeekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
  }

  int _getWeekNumber(DateTime date) {
    final dayOfYear = int.parse(DateFormat('D').format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  @override
  Widget build(BuildContext context) {
    final weekNumber = _getWeekNumber(_currentWeekStart);
    final weekEnd = _currentWeekStart.add(const Duration(days: 4)); // Friday
    final weekRange = '${DateFormat('dd.').format(_currentWeekStart)} - ${DateFormat('dd. MMMM yyyy', 'de_DE').format(weekEnd)}';

    return SeasonalBackground(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header with stats
            Row(
              children: [
                Icon(Icons.confirmation_number, size: 32, color: Colors.blue.shade700),
              const SizedBox(width: 12),
              const Text(
                'Ticketverwaltung',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (widget.ticketStats != null) ...[
                _buildStatBadge('Gesamt', widget.ticketStats!.total, Colors.blue),
                const SizedBox(width: 6),
                _buildStatBadge('Offen', widget.ticketStats!.open, Colors.orange),
                const SizedBox(width: 6),
                _buildStatBadge('Erledigt', widget.ticketStats!.done, Colors.green),
              ],
              const SizedBox(width: 16),
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
                label: const Text('Neues Ticket'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
              ),
              const SizedBox(width: 8),
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
          // Week navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
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
              const SizedBox(width: 8),
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
              const SizedBox(width: 16),
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
          Expanded(
            child: widget.isLoading
                ? const Center(child: CircularProgressIndicator())
                : _viewMode == _TicketViewMode.wochenansicht
                    ? _buildWeeklyGrid()
                    : _buildTodayTimeline(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildWeeklyGrid() {
    final dayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];
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
              children: List.generate(5, (dayIndex) {
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
                Text(
                  'Heute — $dayName, $dateStr',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
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
          Expanded(
            child: todayTickets.isEmpty
                ? Center(
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
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
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
                    Row(
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
                        const Spacer(),
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
                        const SizedBox(width: 6),
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
            Row(
              children: [
                if (ticket.scheduledTimeDisplay.isNotEmpty) ...[
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
                  const SizedBox(width: 6),
                ],
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
                const Spacer(),
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
            Row(
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
                if (ticket.totalTimeSeconds > 0) ...[
                  const SizedBox(width: 4),
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
              ],
            ),
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
