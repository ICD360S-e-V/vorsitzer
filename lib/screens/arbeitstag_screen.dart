import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
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
  String _view = 'active';

  @override
  void initState() {
    super.initState();
    initializeDateFormatting('de_DE', null);
    final now = DateTime.now();
    _kwYear = _isoYear(now);
    _kwNumber = _isoWeek(now);
    _load();
  }

  static int _isoWeek(DateTime d) {
    final thursday = d.add(Duration(days: 4 - d.weekday));
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
    final data = await _svc.getWoche(kwYear: _kwYear, kwNumber: _kwNumber, view: _view);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  Future<void> _archiveMember(ArbeitstagMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mitglied archivieren?'),
        content: Text('${m.name} wird aus der aktiven Arbeitswochen-Liste entfernt. '
            'Kann jederzeit wiederhergestellt werden.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Abbrechen')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Archivieren')),
        ],
      ),
    );
    if (ok != true) return;
    final success = await _svc.archiveToggle(userId: m.userId, action: 'archive');
    if (success) _load();
  }

  Future<void> _unarchiveMember(ArbeitstagMember m) async {
    final success = await _svc.archiveToggle(userId: m.userId, action: 'unarchive');
    if (success) _load();
  }

  void _shiftKw(int delta) {
    // Calculate from _kwYear/_kwNumber directly, don't rely on _data.monday
    // (which might be null or stale during load).
    final currentMonday = _mondayOfIsoWeek(_kwYear, _kwNumber);
    final next = currentMonday.add(Duration(days: 7 * delta));
    setState(() {
      _kwYear = _isoYear(next);
      _kwNumber = _isoWeek(next);
    });
    _load();
  }

  static DateTime _mondayOfIsoWeek(int year, int week) {
    // ISO week 1 is the week containing Jan 4 (guaranteed to be in week 1).
    final jan4 = DateTime(year, 1, 4);
    final mondayOfWeek1 = jan4.subtract(Duration(days: jan4.weekday - 1));
    return mondayOfWeek1.add(Duration(days: 7 * (week - 1)));
  }

  void _jumpToday() {
    final now = DateTime.now();
    setState(() {
      _kwYear = _isoYear(now);
      _kwNumber = _isoWeek(now);
    });
    _load();
  }

  Future<void> _handleChipTap(ArbeitstagMember m, String typ) async {
    final state = m.stateFor(typ);
    switch (state) {
      case 'offen':
        await _openPicker(m, typ);
        break;
      case 'geplant':
        await _svc.setState(
          kwYear: _kwYear, kwNumber: _kwNumber, userId: m.userId,
          typ: typ, state: 'in_bearbeitung',
        );
        _load();
        break;
      case 'in_bearbeitung':
        await _svc.setState(
          kwYear: _kwYear, kwNumber: _kwNumber, userId: m.userId,
          typ: typ, state: 'erledigt',
        );
        _load();
        break;
      case 'erledigt':
        // Tap on erledigt = open menu with Reset + Zurück-Optionen
        await _handleChipLongPress(m, typ);
        break;
    }
  }

  Future<void> _handleChipLongPress(ArbeitstagMember m, String typ) async {
    final state = m.stateFor(typ);
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('${_typLabel(typ)} für ${m.name}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            const Divider(height: 1),
            if (state != 'offen') ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Auswahl ändern'),
              onTap: () => Navigator.pop(ctx, 'change'),
            ),
            if (state == 'in_bearbeitung' || state == 'erledigt') ListTile(
              leading: const Icon(Icons.hourglass_bottom, color: Colors.orange),
              title: const Text('Zurück zu Geplant'),
              onTap: () => Navigator.pop(ctx, 'geplant'),
            ),
            if (state == 'erledigt') ListTile(
              leading: const Icon(Icons.autorenew, color: Colors.blue),
              title: const Text('Zurück zu In Bearbeitung'),
              onTap: () => Navigator.pop(ctx, 'in_bearbeitung'),
            ),
            if (state != 'offen') ListTile(
              leading: const Icon(Icons.close, color: Colors.red),
              title: const Text('Reset (offen)'),
              onTap: () => Navigator.pop(ctx, 'offen'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (action == null) return;
    if (action == 'change') {
      await _openPicker(m, typ);
    } else {
      await _svc.setState(
        kwYear: _kwYear, kwNumber: _kwNumber, userId: m.userId,
        typ: typ, state: action,
      );
      _load();
    }
  }

  Future<void> _openHistory(ArbeitstagMember m) async {
    final entries = await _svc.getHistory(userId: m.userId, limit: 12);
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _HistoryDialog(member: m, entries: entries),
    );
  }

  Future<void> _openNotiz(ArbeitstagMember m) async {
    final controller = TextEditingController(text: m.notiz ?? '');
    final saved = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Notiz — ${m.name} (KW $_kwNumber)'),
        content: SizedBox(
          width: 480,
          child: TextField(
            controller: controller,
            autofocus: true,
            maxLines: 5,
            maxLength: 2000,
            decoration: const InputDecoration(
              hintText: 'z.B. Fax an Jobcenter — warte auf Bestätigung',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, null), child: const Text('Abbrechen')),
          if ((m.notiz ?? '').isNotEmpty)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              child: const Text('Löschen', style: TextStyle(color: Colors.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Speichern'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    final ok = await _svc.setNotiz(
      kwYear: _kwYear, kwNumber: _kwNumber, userId: m.userId, notiz: saved,
    );
    if (ok) _load();
  }

  Future<void> _openPicker(ArbeitstagMember m, String typ) async {
    int? currentSelectionId;
    switch (typ) {
      case 'ticket':  currentSelectionId = m.ticketId; break;
      case 'termin':  currentSelectionId = m.terminId; break;
      case 'routine': currentSelectionId = m.routineExecutionId; break;
      case 'notfall': currentSelectionId = m.notfallTerminId; break;
    }

    final items = await _svc.getPickerItems(
      userId: m.userId, typ: typ, kwYear: _kwYear, kwNumber: _kwNumber,
    );

    if (!mounted) return;

    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet(
        title: '${_typLabel(typ)} für ${m.name} — KW $_kwNumber',
        emptyLabel: _emptyLabel(typ),
        items: items,
        currentSelectionId: currentSelectionId,
        canReset: currentSelectionId != null,
      ),
    );

    if (result == null) return;

    final ok = await _svc.setState(
      kwYear: _kwYear,
      kwNumber: _kwNumber,
      userId: m.userId,
      typ: typ,
      state: result.reset ? 'offen' : 'geplant',
      refId: result.reset ? null : result.selectedId,
    );
    if (ok) _load();
  }

  String _emptyLabel(String typ) {
    switch (typ) {
      case 'ticket':  return 'Keine offenen Tickets für dieses Mitglied';
      case 'termin':  return 'Keine Termine in dieser KW';
      case 'routine': return 'Keine Routinen in dieser KW';
      case 'notfall': return 'Keine Termine in dieser KW';
      default: return 'Keine Einträge';
    }
  }

  String _typLabel(String typ) {
    switch (typ) {
      case 'ticket': return 'Ticket';
      case 'termin': return 'Termin';
      case 'routine': return 'Routine';
      case 'notfall': return 'Notfall Termin';
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
    final stats = _data?.stats;
    final data = _data;
    final now = DateTime.now();
    final isCurrentKw = _kwYear == _isoYear(now) && _kwNumber == _isoWeek(now);
    final rangeStr = data == null
        ? ''
        : '${DateFormat('dd.MM').format(data.monday)} – ${DateFormat('dd.MM.yyyy').format(data.sunday)}';
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
              Text('Arbeitswochen – KW $_kwNumber / $_kwYear',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              if (rangeStr.isNotEmpty)
                Text(rangeStr + (isCurrentKw ? ' (aktuelle KW)' : ''),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: isCurrentKw ? theme.colorScheme.primary : null,
                      fontWeight: isCurrentKw ? FontWeight.w600 : FontWeight.normal,
                    )),
            ],
          ),
          IconButton(
            onPressed: () => _shiftKw(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Nächste KW',
          ),
          if (!isCurrentKw)
            TextButton.icon(
              onPressed: _jumpToday,
              icon: const Icon(Icons.today, size: 16),
              label: const Text('Heute'),
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
          _buildArchiveToggle(),
        ],
      ),
    );
  }

  Widget _buildArchiveToggle() {
    final archivedCount = _data?.stats.totalArchived ?? 0;
    final showingArchived = _view == 'archived';
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          onPressed: () {
            setState(() => _view = showingArchived ? 'active' : 'archived');
            _load();
          },
          icon: Icon(showingArchived ? Icons.inventory_2 : Icons.inventory_2_outlined),
          tooltip: showingArchived ? 'Aktive anzeigen' : 'Archiv anzeigen',
          color: showingArchived ? Colors.orange : null,
        ),
        if (!showingArchived && archivedCount > 0)
          Positioned(
            right: 4, top: 4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: Colors.orange, borderRadius: BorderRadius.circular(8),
              ),
              child: Text('$archivedCount',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)),
            ),
          ),
      ],
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
      return Center(child: Text(_view == 'archived'
          ? 'Keine archivierten Mitglieder'
          : 'Keine aktiven Mitglieder'));
    }
    // In archive view no split. In active view: not-done first (by prio), done at bottom.
    final active = _view == 'archived'
        ? _data!.members
        : _data!.members.where((m) => !m.allDone).toList();
    final done = _view == 'archived'
        ? <ArbeitstagMember>[]
        : _data!.members.where((m) => m.allDone).toList();
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
                  InkWell(
                    onTap: () => _openHistory(m),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(m.name.isNotEmpty ? m.name : '${m.vorname ?? ''} ${m.nachname ?? ''}'.trim(),
                            style: theme.textTheme.titleMedium),
                        const SizedBox(width: 4),
                        Icon(Icons.history, size: 14, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                  Row(
                    children: [
                      Text(m.mitgliedernummer, style: theme.textTheme.bodySmall),
                      if (m.prioGrund != null && m.prioGrund!.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text('• ${m.prioGrund!}',
                            style: theme.textTheme.bodySmall?.copyWith(color: prioColor)),
                      ],
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () => _openNotiz(m),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (m.notiz ?? '').isNotEmpty ? Icons.sticky_note_2 : Icons.sticky_note_2_outlined,
                                size: 14,
                                color: (m.notiz ?? '').isNotEmpty ? Colors.amber.shade700 : Colors.grey.shade500,
                              ),
                              if ((m.notiz ?? '').isNotEmpty) ...[
                                const SizedBox(width: 4),
                                ConstrainedBox(
                                  constraints: const BoxConstraints(maxWidth: 200),
                                  child: Text(
                                    m.notiz!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: Colors.amber.shade900,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (m.ticketSubject != null || m.terminTitle != null || m.routineTitle != null || m.notfallTerminTitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Wrap(
                        spacing: 8,
                        children: [
                          if (m.ticketSubject != null)
                            Text('🎫 ${m.ticketSubject}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700)),
                          if (m.terminTitle != null)
                            Text('📅 ${m.terminTitle}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700)),
                          if (m.routineTitle != null)
                            Text('🔄 ${m.routineTitle}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.green.shade700)),
                          if (m.notfallTerminTitle != null)
                            Text('🚨 ${m.notfallTerminTitle}',
                                style: theme.textTheme.bodySmall?.copyWith(color: Colors.red.shade700)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (!m.isArchived) ...[
              _stateChip(m, 'Ticket', 'ticket', m.ticketState, m.openTicketsCount),
              const SizedBox(width: 6),
              _stateChip(m, 'Termin', 'termin', m.terminState, m.termineKwCount),
              const SizedBox(width: 6),
              _stateChip(m, 'Routine', 'routine', m.routineState, m.routinesKwCount),
              const SizedBox(width: 6),
              _stateChip(m, 'Notfall', 'notfall', m.notfallState, m.termineKwCount),
              const SizedBox(width: 8),
              IconButton(
                onPressed: () => _archiveMember(m),
                icon: const Icon(Icons.archive_outlined, size: 20),
                tooltip: 'Archivieren',
                color: Colors.grey[600],
              ),
            ] else ...[
              if (m.archivedAt != null)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text('archiviert ${DateFormat('dd.MM.yy').format(m.archivedAt!)}',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                ),
              IconButton(
                onPressed: () => _unarchiveMember(m),
                icon: const Icon(Icons.unarchive, size: 20),
                tooltip: 'Wiederherstellen',
                color: Colors.blue,
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _iconFor(String typ, String state) {
    if (state == 'geplant')        return Icons.hourglass_bottom;
    if (state == 'in_bearbeitung') return Icons.autorenew;
    if (state == 'erledigt')       return Icons.check_circle;
    // offen — icon by typ
    switch (typ) {
      case 'ticket':  return Icons.confirmation_number;
      case 'termin':  return Icons.calendar_month;
      case 'routine': return Icons.repeat;
      case 'notfall': return Icons.emergency;
      default: return Icons.circle_outlined;
    }
  }

  Color _colorFor(String state) {
    switch (state) {
      case 'geplant':        return Colors.orange;
      case 'in_bearbeitung': return Colors.blue;
      case 'erledigt':       return Colors.green;
      default:               return Colors.grey;
    }
  }

  Widget _stateChip(ArbeitstagMember m, String label, String typ, String state, int badgeCount) {
    final color = _colorFor(state);
    final icon = _iconFor(typ, state);
    final isOffen = state == 'offen';
    return InkWell(
      onTap: () => _handleChipTap(m, typ),
      onLongPress: () => _handleChipLongPress(m, typ),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: isOffen ? 0.08 : 0.14),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w600)),
            if (isOffen && badgeCount > 0) ...[
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

class _PickerResult {
  final int? selectedId;
  final bool reset;
  _PickerResult({this.selectedId, this.reset = false});
}

class _PickerSheet extends StatelessWidget {
  final String title;
  final String emptyLabel;
  final List<ArbeitstagPickerItem> items;
  final int? currentSelectionId;
  final bool canReset;

  const _PickerSheet({
    required this.title,
    required this.emptyLabel,
    required this.items,
    required this.currentSelectionId,
    required this.canReset,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(title,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.all(24),
                child: Text(emptyLabel, style: TextStyle(color: Colors.grey[600])),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final it = items[i];
                    final selected = it.id == currentSelectionId;
                    return ListTile(
                      leading: Icon(
                        selected ? Icons.check_circle : Icons.radio_button_unchecked,
                        color: selected ? Colors.green : Colors.grey,
                      ),
                      title: Text(it.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: it.subtitle != null ? Text(it.subtitle!) : null,
                      onTap: () => Navigator.pop(
                        context,
                        _PickerResult(selectedId: it.id, reset: false),
                      ),
                    );
                  },
                ),
              ),
            if (canReset) ...[
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.close, color: Colors.red),
                title: const Text('Bearbeitung zurücksetzen',
                    style: TextStyle(color: Colors.red)),
                onTap: () => Navigator.pop(
                  context,
                  _PickerResult(reset: true),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _HistoryDialog extends StatelessWidget {
  final ArbeitstagMember member;
  final List<ArbeitstagHistoryEntry> entries;
  const _HistoryDialog({required this.member, required this.entries});

  static const _typs = ['ticket', 'termin', 'routine', 'notfall'];
  static const _icons = {
    'ticket': '🎫', 'termin': '📅', 'routine': '🔄', 'notfall': '🚨',
  };

  String _stateSymbol(String s) {
    switch (s) {
      case 'geplant':        return '⏳';
      case 'in_bearbeitung': return '🔵';
      case 'erledigt':       return '✅';
      default:               return '·';
    }
  }

  Color _stateColor(String s) {
    switch (s) {
      case 'geplant':        return Colors.orange;
      case 'in_bearbeitung': return Colors.blue;
      case 'erledigt':       return Colors.green;
      default:               return Colors.grey.shade400;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 600),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Historie — ${member.name}',
                            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
                        Text('${member.mitgliedernummer} · letzte ${entries.length} KW',
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ),
                  IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: entries.isEmpty
                  ? const Padding(padding: EdgeInsets.all(24), child: Text('Noch kein Verlauf'))
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, i) {
                        final e = entries[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: e.allErledigt
                                        ? Colors.green.withValues(alpha: 0.15)
                                        : theme.colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text('KW ${e.kwNumber} / ${e.kwYear}',
                                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                                ),
                                const SizedBox(width: 8),
                                if (e.prioGrund != null && e.prioGrund!.isNotEmpty)
                                  Expanded(
                                    child: Text(e.prioGrund!,
                                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                                        overflow: TextOverflow.ellipsis),
                                  ),
                              ]),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 12,
                                children: _typs.map((t) {
                                  final st = e.stateFor(t);
                                  final title = t == 'ticket' ? e.ticketSubject
                                              : t == 'termin' ? e.terminTitle
                                              : t == 'routine' ? e.routineTitle
                                              : e.notfallTerminTitle;
                                  return Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text(_icons[t] ?? '·', style: const TextStyle(fontSize: 14)),
                                    const SizedBox(width: 2),
                                    Text(_stateSymbol(st), style: TextStyle(color: _stateColor(st), fontSize: 13)),
                                    if (title != null) ...[
                                      const SizedBox(width: 4),
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 140),
                                        child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                                            style: theme.textTheme.bodySmall),
                                      ),
                                    ],
                                  ]);
                                }).toList(),
                              ),
                              if (e.notiz != null && e.notiz!.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                                  ),
                                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                    Icon(Icons.sticky_note_2, size: 14, color: Colors.amber.shade700),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(e.notiz!,
                                          style: theme.textTheme.bodySmall?.copyWith(fontStyle: FontStyle.italic)),
                                    ),
                                  ]),
                                ),
                              ],
                              if (e.bearbeiterName != null) ...[
                                const SizedBox(height: 4),
                                Text('bearbeitet von ${e.bearbeiterName}',
                                    style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey.shade500, fontSize: 11)),
                              ],
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
