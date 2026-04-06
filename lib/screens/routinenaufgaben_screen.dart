import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/routine_service.dart';
import '../models/user.dart';
import '../widgets/eastern.dart';

class RoutinenaufgabenScreen extends StatefulWidget {
  final List<User> users;
  final String currentMitgliedernummer;

  const RoutinenaufgabenScreen({
    super.key,
    required this.users,
    required this.currentMitgliedernummer,
  });

  @override
  State<RoutinenaufgabenScreen> createState() => _RoutinenaufgabenScreenState();
}

class _RoutinenaufgabenScreenState extends State<RoutinenaufgabenScreen> {
  final _routineService = RoutineService();

  late DateTime _currentWeekStart;
  bool _isLoading = true;
  List<RoutineExecution> _executions = [];
  ExecutionStats? _stats;
  List<Routine> _routines = [];
  List<String> _categories = [];

  // Filters
  int? _filterUserId;
  String? _filterCategory;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
    _currentWeekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final startDate = DateFormat('yyyy-MM-dd').format(_currentWeekStart);
    final endDate = DateFormat('yyyy-MM-dd').format(_currentWeekStart.add(const Duration(days: 4)));

    final results = await Future.wait([
      _routineService.getExecutions(startDate: startDate, endDate: endDate, userId: _filterUserId),
      _routineService.getRoutines(userId: _filterUserId, category: _filterCategory),
      _routineService.getCategories(),
    ]);

    final execResult = results[0] as ({List<RoutineExecution> executions, ExecutionStats? stats});
    final routines = results[1] as List<Routine>;
    final categories = results[2] as List<String>;

    if (mounted) {
      setState(() {
        _executions = execResult.executions;
        _stats = execResult.stats;
        _routines = routines;
        _categories = categories;
        _isLoading = false;
      });
    }
  }

  int _getWeekNumber(DateTime date) {
    final dayOfYear = int.parse(DateFormat('D').format(date));
    return ((dayOfYear - date.weekday + 10) / 7).floor();
  }

  @override
  Widget build(BuildContext context) {
    final weekNumber = _getWeekNumber(_currentWeekStart);
    final weekEnd = _currentWeekStart.add(const Duration(days: 4));
    final weekRange = '${DateFormat('dd.').format(_currentWeekStart)} - ${DateFormat('dd. MMMM yyyy', 'de_DE').format(weekEnd)}';

    return SeasonalBackground(
      child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.repeat, size: 32, color: Colors.teal.shade700),
              const SizedBox(width: 12),
              const Text('Routinenaufgaben',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const Spacer(),
              // Stats
              if (_stats != null) ...[
                _buildStatBadge('Gesamt', '${_stats!.total}', Colors.blue),
                const SizedBox(width: 8),
                _buildStatBadge('Erledigt', '${_stats!.done}', Colors.green),
                const SizedBox(width: 8),
                _buildStatBadge('Offen', '${_stats!.pending}', Colors.orange),
                const SizedBox(width: 16),
                // Progress
                SizedBox(
                  width: 60,
                  height: 60,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _stats != null && _stats!.total > 0
                            ? _stats!.done / _stats!.total
                            : 0,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade600),
                        strokeWidth: 5,
                      ),
                      Text(
                        '${_stats?.progressPercent.toStringAsFixed(0) ?? 0}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
              ],
              // New routine button
              ElevatedButton.icon(
                onPressed: _showCreateRoutineDialog,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Neue Routine'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              // Manage routines
              OutlinedButton.icon(
                onPressed: _showManageRoutinesDialog,
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Verwalten'),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: _loadData,
                icon: const Icon(Icons.refresh),
                tooltip: 'Aktualisieren',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Filters row
          Row(
            children: [
              // Member filter
              SizedBox(
                width: 300,
                child: DropdownButtonFormField<int?>(
                  initialValue: _filterUserId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Mitglied',
                    prefixIcon: const Icon(Icons.person, size: 20),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                  ),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('Alle Mitglieder')),
                    ...widget.users
                        .where((u) => !u.isDeleted && !u.isSuspended && !u.isVerstorben && !u.isAusgeschlossen)
                        .map((u) => DropdownMenuItem<int?>(
                          value: u.id,
                          child: Text('${u.name} (${u.mitgliedernummer})', overflow: TextOverflow.ellipsis),
                        )),
                  ],
                  onChanged: (val) {
                    setState(() => _filterUserId = val);
                    _loadData();
                  },
                ),
              ),
              const SizedBox(width: 12),
              // Category filter
              if (_categories.isNotEmpty)
                SizedBox(
                  width: 200,
                  child: DropdownButtonFormField<String?>(
                    initialValue: _filterCategory,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Kategorie',
                      prefixIcon: const Icon(Icons.category, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Alle')),
                      ..._categories.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                    ],
                    onChanged: (val) {
                      setState(() => _filterCategory = val);
                      _loadData();
                    },
                  ),
                ),
              const Spacer(),
              // Week navigation
              IconButton(
                onPressed: () {
                  setState(() => _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7)));
                  _loadData();
                },
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Vorherige Woche',
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.teal.shade200),
                ),
                child: Text(
                  'KW $weekNumber  •  $weekRange',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.teal.shade800),
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _currentWeekStart = _currentWeekStart.add(const Duration(days: 7)));
                  _loadData();
                },
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Nächste Woche',
              ),
              TextButton(
                onPressed: () {
                  final now = DateTime.now();
                  setState(() {
                    _currentWeekStart = now.subtract(Duration(days: now.weekday - 1));
                    _currentWeekStart = DateTime(_currentWeekStart.year, _currentWeekStart.month, _currentWeekStart.day);
                  });
                  _loadData();
                },
                child: const Text('Heute'),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weekly grid
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _buildWeeklyGrid(),
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildWeeklyGrid() {
    const dayNames = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag'];
    final today = DateTime.now();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: List.generate(5, (dayIndex) {
        final day = _currentWeekStart.add(Duration(days: dayIndex));
        final isToday = day.year == today.year && day.month == today.month && day.day == today.day;
        final dayExecs = _getExecutionsForDay(day);

        return Expanded(
          child: Container(
            margin: EdgeInsets.only(right: dayIndex < 4 ? 8 : 0),
            decoration: BoxDecoration(
              color: isToday ? Colors.teal.shade50 : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isToday ? Colors.teal.shade300 : Colors.grey.shade300,
                width: isToday ? 2 : 1,
              ),
            ),
            child: Column(
              children: [
                // Day header
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.teal.shade600 : Colors.grey.shade200,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        dayNames[dayIndex],
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isToday ? Colors.white : Colors.grey.shade800,
                          fontSize: 13,
                        ),
                      ),
                      Text(
                        DateFormat('dd.MM.').format(day),
                        style: TextStyle(
                          color: isToday ? Colors.white70 : Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Day stats
                if (dayExecs.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '${dayExecs.where((e) => e.isDone).length}/${dayExecs.length}',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: LinearProgressIndicator(
                            value: dayExecs.isNotEmpty
                                ? dayExecs.where((e) => e.isDone).length / dayExecs.length
                                : 0,
                            backgroundColor: Colors.grey.shade200,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade400),
                            minHeight: 3,
                          ),
                        ),
                      ],
                    ),
                  ),
                // Execution cards
                Expanded(
                  child: dayExecs.isEmpty
                      ? Center(
                          child: Text(
                            'Keine Aufgaben',
                            style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(6),
                          itemCount: dayExecs.length,
                          itemBuilder: (context, index) => _buildExecutionCard(dayExecs[index]),
                        ),
                ),
              ],
            ),
          ),
        );
      }),
    );
  }

  Widget _buildExecutionCard(RoutineExecution exec) {
    Color statusColor;
    IconData statusIcon;
    switch (exec.status) {
      case 'done':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'skipped':
        statusColor = Colors.orange;
        statusIcon = Icons.skip_next;
        break;
      default:
        statusColor = Colors.grey;
        statusIcon = Icons.radio_button_unchecked;
    }

    final categoryColor = _getCategoryColor(exec.routineCategory);

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      elevation: exec.isPending ? 2 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: exec.isDone ? Colors.green.shade200 : (exec.isSkipped ? Colors.orange.shade200 : Colors.grey.shade300),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _showExecutionActions(exec),
        child: Opacity(
          opacity: exec.isDone ? 0.7 : 1.0,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Status + title row
                Row(
                  children: [
                    Icon(statusIcon, size: 16, color: statusColor),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        exec.routineTitle ?? '',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                          decoration: exec.isDone ? TextDecoration.lineThrough : null,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Time + Member
                Row(
                  children: [
                    if (exec.preferredTimeShort.isNotEmpty) ...[
                      Icon(Icons.access_time, size: 12, color: Colors.blue.shade400),
                      const SizedBox(width: 3),
                      Text(
                        '${exec.preferredTimeShort} Uhr',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.blue.shade700),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Icon(Icons.person, size: 12, color: Colors.grey.shade500),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        exec.memberName ?? '',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                // Category badge
                if (exec.routineCategory != null && exec.routineCategory!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: categoryColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      exec.routineCategory!,
                      style: TextStyle(fontSize: 10, color: categoryColor, fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
                // Notes
                if (exec.notes != null && exec.notes!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    exec.notes!,
                    style: TextStyle(fontSize: 10, color: Colors.grey.shade600, fontStyle: FontStyle.italic),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<RoutineExecution> _getExecutionsForDay(DateTime day) {
    final dayExecs = _executions.where((e) {
      return e.scheduledDate.year == day.year &&
          e.scheduledDate.month == day.month &&
          e.scheduledDate.day == day.day;
    }).toList();
    dayExecs.sort((a, b) => (a.preferredTime ?? '99:99').compareTo(b.preferredTime ?? '99:99'));
    return dayExecs;
  }

  Color _getCategoryColor(String? category) {
    if (category == null) return Colors.grey;
    switch (category.toLowerCase()) {
      case 'jobcenter': return Colors.blue.shade700;
      case 'bewerbung': return Colors.purple.shade600;
      case 'dokumente': return Colors.amber.shade800;
      case 'behörden': return Colors.red.shade600;
      case 'gesundheit': return Colors.green.shade700;
      case 'finanzen': return Colors.indigo.shade600;
      default: return Colors.teal.shade600;
    }
  }

  Widget _buildStatBadge(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color)),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ],
      ),
    );
  }

  // ─── Execution Actions ──────────────────────────────────────────

  void _showExecutionActions(RoutineExecution exec) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final notesController = TextEditingController(text: exec.notes ?? '');
        return Padding(
          padding: EdgeInsets.only(
            left: 24, right: 24, top: 24,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      exec.routineTitle ?? 'Routine',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      Navigator.pop(ctx);
                      // Find the routine for this execution and open edit dialog
                      final routine = _routines.where((r) => r.id == exec.routineId).firstOrNull;
                      if (routine != null) {
                        _showEditRoutineDialog(routine, (_) => setState(() {}));
                      }
                    },
                    icon: Icon(Icons.edit, color: Colors.teal.shade600),
                    tooltip: 'Routine bearbeiten',
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${exec.memberName ?? ''} • ${DateFormat('dd.MM.yyyy').format(exec.scheduledDate)}',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              if (exec.routineCategory != null) ...[
                const SizedBox(height: 4),
                Text('Kategorie: ${exec.routineCategory}', style: TextStyle(color: Colors.grey.shade600)),
              ],
              // Show description from routine
              Builder(builder: (_) {
                final routine = _routines.where((r) => r.id == exec.routineId).firstOrNull;
                if (routine != null && routine.description != null && routine.description!.isNotEmpty) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.teal.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.teal.shade200),
                      ),
                      child: Text(
                        routine.description!,
                        style: TextStyle(fontSize: 13, color: Colors.teal.shade900),
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              }),
              const SizedBox(height: 16),
              TextField(
                controller: notesController,
                decoration: InputDecoration(
                  labelText: 'Notizen',
                  hintText: 'Optional: Notizen hinzufügen...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _routineService.updateExecution(
                          executionId: exec.id,
                          status: 'done',
                          notes: notesController.text.isNotEmpty ? notesController.text : null,
                        );
                        _loadData();
                      },
                      icon: const Icon(Icons.check_circle, size: 18),
                      label: const Text('Erledigt'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await _routineService.updateExecution(
                          executionId: exec.id,
                          status: 'skipped',
                          notes: notesController.text.isNotEmpty ? notesController.text : null,
                        );
                        _loadData();
                      },
                      icon: const Icon(Icons.skip_next, size: 18),
                      label: const Text('Überspringen'),
                      style: OutlinedButton.styleFrom(foregroundColor: Colors.orange),
                    ),
                  ),
                  if (!exec.isPending) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await _routineService.updateExecution(
                            executionId: exec.id,
                            status: 'pending',
                            notes: notesController.text.isNotEmpty ? notesController.text : null,
                          );
                          _loadData();
                        },
                        icon: const Icon(Icons.undo, size: 18),
                        label: const Text('Zurücksetzen'),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Create Routine Dialog ──────────────────────────────────────

  void _showCreateRoutineDialog() {
    final titleController = TextEditingController();
    final descController = TextEditingController();
    final categoryController = TextEditingController();
    String frequency = 'once';
    int dayOfWeek = 1;
    int dayOfMonth = 1;
    int monthOfYear = 1;
    int? selectedUserId;
    TimeOfDay selectedTime = const TimeOfDay(hour: 9, minute: 0);
    DateTime onceDate = DateTime.now().add(const Duration(days: 1));

    showDialog(
      context: context,
      builder: (ctx) => FocusScope(
        autofocus: true,
        child: StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.add_task, color: Colors.teal.shade600),
              const SizedBox(width: 8),
              const Text('Neue Routine erstellen'),
            ],
          ),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Member selection
                  DropdownButtonFormField<int?>(
                    initialValue: selectedUserId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Mitglied *',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    items: widget.users
                        .where((u) => !u.isDeleted && !u.isSuspended && !u.isVerstorben && !u.isAusgeschlossen)
                        .map((u) => DropdownMenuItem<int?>(
                          value: u.id,
                          child: Text('${u.name} (${u.mitgliedernummer})'),
                        ))
                        .toList(),
                    onChanged: (val) => setDialogState(() => selectedUserId = val),
                  ),
                  const SizedBox(height: 16),

                  // Title
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(
                      labelText: 'Titel *',
                      hintText: 'z.B. Jobcenter Konto prüfen',
                      prefixIcon: Icon(Icons.title),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Description
                  TextField(
                    controller: descController,
                    decoration: const InputDecoration(
                      labelText: 'Beschreibung',
                      hintText: 'Optional: Details zur Routine',
                      prefixIcon: Icon(Icons.description),
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 16),

                  // Category
                  Autocomplete<String>(
                    optionsBuilder: (textEditingValue) {
                      if (textEditingValue.text.isEmpty) return _categories;
                      return _categories.where((c) =>
                          c.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                    },
                    fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                      categoryController.text = controller.text;
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Kategorie',
                          hintText: 'z.B. Jobcenter, Bewerbung',
                          prefixIcon: Icon(Icons.category),
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => categoryController.text = v,
                      );
                    },
                    onSelected: (val) => categoryController.text = val,
                  ),
                  const SizedBox(height: 16),

                  // Time picker
                  InkWell(
                    onTap: () async {
                      final picked = await showTimePicker(
                        context: ctx,
                        initialTime: selectedTime,
                      );
                      if (picked != null) {
                        setDialogState(() => selectedTime = picked);
                      }
                    },
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Uhrzeit',
                        prefixIcon: Icon(Icons.access_time),
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} Uhr',
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Frequency
                  DropdownButtonFormField<String>(
                    initialValue: frequency,
                    decoration: const InputDecoration(
                      labelText: 'Frequenz *',
                      prefixIcon: Icon(Icons.repeat),
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'once', child: Text('Einmal')),
                      DropdownMenuItem(value: 'daily', child: Text('Täglich (Mo-Fr)')),
                      DropdownMenuItem(value: 'weekly', child: Text('Wöchentlich')),
                      DropdownMenuItem(value: 'monthly', child: Text('Monatlich')),
                      DropdownMenuItem(value: 'yearly', child: Text('Jährlich')),
                    ],
                    onChanged: (val) => setDialogState(() => frequency = val!),
                  ),
                  const SizedBox(height: 16),

                  // Frequency-specific fields
                  if (frequency == 'once')
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: onceDate,
                          firstDate: DateTime.now(),
                          lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                          locale: const Locale('de', 'DE'),
                        );
                        if (picked != null) {
                          setDialogState(() => onceDate = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Datum *',
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          DateFormat('dd.MM.yyyy').format(onceDate),
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),

                  if (frequency == 'weekly')
                    DropdownButtonFormField<int>(
                      initialValue: dayOfWeek,
                      decoration: const InputDecoration(
                        labelText: 'Wochentag *',
                        prefixIcon: Icon(Icons.calendar_today),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Montag')),
                        DropdownMenuItem(value: 2, child: Text('Dienstag')),
                        DropdownMenuItem(value: 3, child: Text('Mittwoch')),
                        DropdownMenuItem(value: 4, child: Text('Donnerstag')),
                        DropdownMenuItem(value: 5, child: Text('Freitag')),
                      ],
                      onChanged: (val) => setDialogState(() => dayOfWeek = val!),
                    ),

                  if (frequency == 'monthly' || frequency == 'yearly')
                    DropdownButtonFormField<int>(
                      initialValue: dayOfMonth,
                      decoration: const InputDecoration(
                        labelText: 'Tag des Monats *',
                        prefixIcon: Icon(Icons.calendar_today),
                        border: OutlineInputBorder(),
                      ),
                      items: List.generate(28, (i) => DropdownMenuItem(
                        value: i + 1,
                        child: Text('${i + 1}.'),
                      )),
                      onChanged: (val) => setDialogState(() => dayOfMonth = val!),
                    ),

                  if (frequency == 'yearly') ...[
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int>(
                      initialValue: monthOfYear,
                      decoration: const InputDecoration(
                        labelText: 'Monat *',
                        prefixIcon: Icon(Icons.date_range),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Januar')),
                        DropdownMenuItem(value: 2, child: Text('Februar')),
                        DropdownMenuItem(value: 3, child: Text('März')),
                        DropdownMenuItem(value: 4, child: Text('April')),
                        DropdownMenuItem(value: 5, child: Text('Mai')),
                        DropdownMenuItem(value: 6, child: Text('Juni')),
                        DropdownMenuItem(value: 7, child: Text('Juli')),
                        DropdownMenuItem(value: 8, child: Text('August')),
                        DropdownMenuItem(value: 9, child: Text('September')),
                        DropdownMenuItem(value: 10, child: Text('Oktober')),
                        DropdownMenuItem(value: 11, child: Text('November')),
                        DropdownMenuItem(value: 12, child: Text('Dezember')),
                      ],
                      onChanged: (val) => setDialogState(() => monthOfYear = val!),
                    ),
                  ],
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
                if (selectedUserId == null || titleController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Mitglied und Titel sind erforderlich'), backgroundColor: Colors.red),
                  );
                  return;
                }

                final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
                final result = await _routineService.createRoutine(
                  userId: selectedUserId!,
                  title: titleController.text.trim(),
                  description: descController.text.trim(),
                  frequency: frequency,
                  dayOfWeek: frequency == 'weekly' ? dayOfWeek : null,
                  dayOfMonth: (frequency == 'monthly' || frequency == 'yearly') ? dayOfMonth : null,
                  monthOfYear: frequency == 'yearly' ? monthOfYear : null,
                  category: categoryController.text.trim(),
                  preferredTime: timeStr,
                  onceDate: frequency == 'once' ? DateFormat('yyyy-MM-dd').format(onceDate) : null,
                );

                if (ctx.mounted) Navigator.pop(ctx);

                if (result != null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Routine "${result.title}" erstellt'), backgroundColor: Colors.green),
                    );
                  }
                  _loadData();
                } else {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Fehler beim Erstellen der Routine'), backgroundColor: Colors.red),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('Erstellen'),
            ),
          ],
        ),
      ),
      ),
    );
  }

  // ─── Edit Routine Dialog ───────────────────────────────────────

  void _showEditRoutineDialog(Routine routine, void Function(void Function()) parentSetState) {
    final titleController = TextEditingController(text: routine.title);
    final descController = TextEditingController(text: routine.description ?? '');
    final categoryController = TextEditingController(text: routine.category ?? '');
    String frequency = routine.frequency;
    int dayOfWeek = routine.dayOfWeek ?? 1;
    int dayOfMonth = routine.dayOfMonth ?? 1;
    int monthOfYear = routine.monthOfYear ?? 1;
    int selectedUserId = routine.userId;
    DateTime onceDate = DateTime.now().add(const Duration(days: 1));
    final timeParts = routine.preferredTime.split(':');
    TimeOfDay selectedTime = TimeOfDay(
      hour: int.tryParse(timeParts.isNotEmpty ? timeParts[0] : '9') ?? 9,
      minute: int.tryParse(timeParts.length > 1 ? timeParts[1] : '0') ?? 0,
    );

    showDialog(
      context: context,
      builder: (ctx) => FocusScope(
        autofocus: true,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: Row(
              children: [
                Icon(Icons.edit, color: Colors.teal.shade600),
                const SizedBox(width: 8),
                const Text('Routine bearbeiten'),
              ],
            ),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Member selection
                    DropdownButtonFormField<int>(
                      initialValue: selectedUserId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Mitglied *',
                        prefixIcon: Icon(Icons.person),
                        border: OutlineInputBorder(),
                      ),
                      items: widget.users
                          .where((u) => !u.isDeleted && !u.isSuspended && !u.isVerstorben && !u.isAusgeschlossen)
                          .map((u) => DropdownMenuItem<int>(
                            value: u.id,
                            child: Text('${u.name} (${u.mitgliedernummer})'),
                          ))
                          .toList(),
                      onChanged: (val) => setDialogState(() => selectedUserId = val!),
                    ),
                    const SizedBox(height: 16),

                    // Title
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Titel *',
                        prefixIcon: Icon(Icons.title),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    TextField(
                      controller: descController,
                      decoration: const InputDecoration(
                        labelText: 'Beschreibung',
                        prefixIcon: Icon(Icons.description),
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 16),

                    // Category
                    Autocomplete<String>(
                      initialValue: TextEditingValue(text: routine.category ?? ''),
                      optionsBuilder: (textEditingValue) {
                        if (textEditingValue.text.isEmpty) return _categories;
                        return _categories.where((c) =>
                            c.toLowerCase().contains(textEditingValue.text.toLowerCase()));
                      },
                      fieldViewBuilder: (ctx, controller, focusNode, onSubmitted) {
                        categoryController.text = controller.text;
                        return TextField(
                          controller: controller,
                          focusNode: focusNode,
                          decoration: const InputDecoration(
                            labelText: 'Kategorie',
                            prefixIcon: Icon(Icons.category),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => categoryController.text = v,
                        );
                      },
                      onSelected: (val) => categoryController.text = val,
                    ),
                    const SizedBox(height: 16),

                    // Time picker
                    InkWell(
                      onTap: () async {
                        final picked = await showTimePicker(
                          context: ctx,
                          initialTime: selectedTime,
                        );
                        if (picked != null) {
                          setDialogState(() => selectedTime = picked);
                        }
                      },
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: 'Uhrzeit',
                          prefixIcon: Icon(Icons.access_time),
                          border: OutlineInputBorder(),
                        ),
                        child: Text(
                          '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')} Uhr',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Frequency
                    DropdownButtonFormField<String>(
                      initialValue: frequency,
                      decoration: const InputDecoration(
                        labelText: 'Frequenz *',
                        prefixIcon: Icon(Icons.repeat),
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'once', child: Text('Einmal')),
                        DropdownMenuItem(value: 'daily', child: Text('Täglich (Mo-Fr)')),
                        DropdownMenuItem(value: 'weekly', child: Text('Wöchentlich')),
                        DropdownMenuItem(value: 'monthly', child: Text('Monatlich')),
                        DropdownMenuItem(value: 'yearly', child: Text('Jährlich')),
                      ],
                      onChanged: (val) => setDialogState(() => frequency = val!),
                    ),
                    const SizedBox(height: 16),

                    // Frequency-specific fields
                    if (frequency == 'once')
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: ctx,
                            initialDate: onceDate,
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(const Duration(days: 365 * 3)),
                            locale: const Locale('de', 'DE'),
                          );
                          if (picked != null) {
                            setDialogState(() => onceDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Datum *',
                            prefixIcon: Icon(Icons.calendar_today),
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            DateFormat('dd.MM.yyyy').format(onceDate),
                            style: const TextStyle(fontSize: 16),
                          ),
                        ),
                      ),

                    if (frequency == 'weekly')
                      DropdownButtonFormField<int>(
                        initialValue: dayOfWeek,
                        decoration: const InputDecoration(
                          labelText: 'Wochentag *',
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Montag')),
                          DropdownMenuItem(value: 2, child: Text('Dienstag')),
                          DropdownMenuItem(value: 3, child: Text('Mittwoch')),
                          DropdownMenuItem(value: 4, child: Text('Donnerstag')),
                          DropdownMenuItem(value: 5, child: Text('Freitag')),
                        ],
                        onChanged: (val) => setDialogState(() => dayOfWeek = val!),
                      ),

                    if (frequency == 'monthly' || frequency == 'yearly')
                      DropdownButtonFormField<int>(
                        initialValue: dayOfMonth,
                        decoration: const InputDecoration(
                          labelText: 'Tag des Monats *',
                          prefixIcon: Icon(Icons.calendar_today),
                          border: OutlineInputBorder(),
                        ),
                        items: List.generate(28, (i) => DropdownMenuItem(
                          value: i + 1,
                          child: Text('${i + 1}.'),
                        )),
                        onChanged: (val) => setDialogState(() => dayOfMonth = val!),
                      ),

                    if (frequency == 'yearly') ...[
                      const SizedBox(height: 16),
                      DropdownButtonFormField<int>(
                        initialValue: monthOfYear,
                        decoration: const InputDecoration(
                          labelText: 'Monat *',
                          prefixIcon: Icon(Icons.date_range),
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('Januar')),
                          DropdownMenuItem(value: 2, child: Text('Februar')),
                          DropdownMenuItem(value: 3, child: Text('März')),
                          DropdownMenuItem(value: 4, child: Text('April')),
                          DropdownMenuItem(value: 5, child: Text('Mai')),
                          DropdownMenuItem(value: 6, child: Text('Juni')),
                          DropdownMenuItem(value: 7, child: Text('Juli')),
                          DropdownMenuItem(value: 8, child: Text('August')),
                          DropdownMenuItem(value: 9, child: Text('September')),
                          DropdownMenuItem(value: 10, child: Text('Oktober')),
                          DropdownMenuItem(value: 11, child: Text('November')),
                          DropdownMenuItem(value: 12, child: Text('Dezember')),
                        ],
                        onChanged: (val) => setDialogState(() => monthOfYear = val!),
                      ),
                    ],
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
                  if (titleController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Titel ist erforderlich'), backgroundColor: Colors.red),
                    );
                    return;
                  }

                  final timeStr = '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}:00';
                  final fields = <String, dynamic>{
                    'user_id': selectedUserId,
                    'title': titleController.text.trim(),
                    'description': descController.text.trim(),
                    'frequency': frequency,
                    'day_of_week': frequency == 'weekly' ? dayOfWeek : null,
                    'day_of_month': (frequency == 'monthly' || frequency == 'yearly') ? dayOfMonth : null,
                    'month_of_year': frequency == 'yearly' ? monthOfYear : null,
                    'category': categoryController.text.trim(),
                    'preferred_time': timeStr,
                    if (frequency == 'once') 'once_date': DateFormat('yyyy-MM-dd').format(onceDate),
                  };

                  final result = await _routineService.updateRoutine(routine.id, fields);
                  if (ctx.mounted) Navigator.pop(ctx);

                  if (result != null) {
                    // Refresh parent dialog
                    final updated = await _routineService.getRoutines();
                    parentSetState(() {
                      _routines.clear();
                      _routines.addAll(updated);
                    });
                    _loadData();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Routine "${result.title}" aktualisiert'), backgroundColor: Colors.green),
                      );
                    }
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Fehler beim Aktualisieren der Routine'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal.shade600,
                  foregroundColor: Colors.white,
                ),
                child: const Text('Speichern'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Manage Routines Dialog ─────────────────────────────────────

  void _showManageRoutinesDialog() {
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.settings, color: Colors.teal.shade600),
                const SizedBox(width: 8),
                const Text('Routinen verwalten'),
                const Spacer(),
                Text('${_routines.length} Routinen',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600, fontWeight: FontWeight.normal)),
              ],
            ),
            content: SizedBox(
              width: 700,
              height: 500,
              child: _routines.isEmpty
                  ? const Center(child: Text('Keine Routinen vorhanden'))
                  : ListView.separated(
                      itemCount: _routines.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final r = _routines[index];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _getCategoryColor(r.category).withValues(alpha: 0.15),
                            child: Icon(
                              r.frequency == 'once' ? Icons.looks_one :
                              r.frequency == 'daily' ? Icons.today :
                              r.frequency == 'weekly' ? Icons.view_week :
                              r.frequency == 'monthly' ? Icons.calendar_month :
                              Icons.calendar_today,
                              color: _getCategoryColor(r.category),
                              size: 20,
                            ),
                          ),
                          title: Text(r.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            '${r.memberName ?? ''} • ${r.frequencyLabel}'
                            '${r.frequency == "weekly" ? " (${r.dayOfWeekLabel})" : ""}'
                            '${r.category != null ? " • ${r.category}" : ""}',
                          ),
                          onTap: () => _showEditRoutineDialog(r, setDialogState),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Edit
                              IconButton(
                                onPressed: () => _showEditRoutineDialog(r, setDialogState),
                                icon: Icon(Icons.edit_outlined, color: Colors.teal.shade600),
                                tooltip: 'Bearbeiten',
                              ),
                              // Active toggle
                              Switch(
                                value: r.isActive,
                                activeThumbColor: Colors.teal,
                                onChanged: (val) async {
                                  await _routineService.updateRoutine(r.id, {'is_active': val});
                                  // Refresh routines list
                                  final updated = await _routineService.getRoutines();
                                  setDialogState(() {
                                    _routines.clear();
                                    _routines.addAll(updated);
                                  });
                                  _loadData();
                                },
                              ),
                              // Delete
                              IconButton(
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: ctx,
                                    builder: (c) => AlertDialog(
                                      title: const Text('Routine löschen?'),
                                      content: Text('Routine "${r.title}" und alle Ausführungen werden gelöscht.'),
                                      actions: [
                                        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Abbrechen')),
                                        ElevatedButton(
                                          onPressed: () => Navigator.pop(c, true),
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                          child: const Text('Löschen'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm == true) {
                                    await _routineService.deleteRoutine(r.id);
                                    final updated = await _routineService.getRoutines();
                                    setDialogState(() {
                                      _routines.clear();
                                      _routines.addAll(updated);
                                    });
                                    _loadData();
                                  }
                                },
                                icon: const Icon(Icons.delete_outline, color: Colors.red),
                                tooltip: 'Löschen',
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Schließen'),
              ),
            ],
          );
        },
      ),
    );
  }
}
