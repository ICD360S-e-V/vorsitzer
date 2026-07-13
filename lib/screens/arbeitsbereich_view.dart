import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/arbeitstag_service.dart';
import '../services/logger_service.dart';

final _log = LoggerService();

/// Widget generic pentru un view de perioadă (Tag / Woche / Monat).
///
/// Toată logica UI comună (header cu navigare ±unit, listă membri, 4 chips,
/// picker sheet, notiz dialog, history dialog, archive/unarchive) trăiește aici.
/// Wrappere thin (`arbeitstag.dart` / `arbeitswochen.dart` / `arbeitsmonat.dart`)
/// doar setează [granularity] și pasează [onNavigate].
class ArbeitsbereichView extends StatefulWidget {
  final ArbeitsbereichGranularity granularity;

  /// Deep-link către alt tab principal (2=Ticket, 3=Termin, 10=Routinen).
  final void Function(int menuIndex,
      {int? focusTicketId,
      int? focusTerminId,
      int? focusRoutineExecutionId})? onNavigate;

  const ArbeitsbereichView({
    super.key,
    required this.granularity,
    this.onNavigate,
  });

  @override
  State<ArbeitsbereichView> createState() => _ArbeitsbereichViewState();
}

class _ArbeitsbereichViewState extends State<ArbeitsbereichView>
    with AutomaticKeepAliveClientMixin {
  final _svc = ArbeitstagService();

  late PeriodKey _key;
  ArbeitsbereichPeriod? _data;
  bool _loading = true;
  String _view = 'active';

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _key = _initialKey(widget.granularity);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  // ─── Initial period key ─────────────────────────────────────────────

  static PeriodKey _initialKey(ArbeitsbereichGranularity g) {
    final now = DateTime.now();
    switch (g) {
      case ArbeitsbereichGranularity.tag:
        return PeriodKey.tag(now);
      case ArbeitsbereichGranularity.woche:
        return PeriodKey.woche(_isoYear(now), _isoWeek(now));
      case ArbeitsbereichGranularity.monat:
        return PeriodKey.monat(now.year, now.month);
    }
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

  static DateTime _mondayOfIsoWeek(int year, int week) {
    final jan4 = DateTime(year, 1, 4);
    final mondayOfWeek1 = jan4.subtract(Duration(days: jan4.weekday - 1));
    return mondayOfWeek1.add(Duration(days: 7 * (week - 1)));
  }

  // ─── Load ──────────────────────────────────────────────────────────

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final data = await _svc.getPeriod(key: _key, view: _view);
      if (!mounted) return;
      setState(() {
        _data = data;
        _loading = false;
      });
    } catch (e, st) {
      _log.error('arbeitsbereich _load failed: $e\n$st', tag: 'ARBEITSTAG');
      if (!mounted) return;
      setState(() {
        _data = null;
        _loading = false;
      });
    }
  }

  // ─── Navigation ±unit ───────────────────────────────────────────────

  void _shift(int delta) {
    setState(() => _key = _shiftKey(_key, delta));
    _load();
  }

  static PeriodKey _shiftKey(PeriodKey k, int delta) {
    switch (k.granularity) {
      case ArbeitsbereichGranularity.tag:
        final d = k.date!.add(Duration(days: delta));
        return PeriodKey.tag(d);
      case ArbeitsbereichGranularity.woche:
        final monday = _mondayOfIsoWeek(k.kwYear!, k.kwNumber!);
        final next = monday.add(Duration(days: 7 * delta));
        return PeriodKey.woche(_isoYear(next), _isoWeek(next));
      case ArbeitsbereichGranularity.monat:
        final y = k.year!;
        final m = k.month! + delta;
        // Normalizare wrap-around
        final normY = y + ((m - 1) ~/ 12);
        final normM = ((m - 1) % 12 + 12) % 12 + 1;
        return PeriodKey.monat(normY, normM);
    }
  }

  void _jumpNow() {
    setState(() => _key = _initialKey(widget.granularity));
    _load();
  }

  // ─── Period labels (client-side fallback dacă serverul nu trimite label) ──

  bool _isCurrent() {
    final now = DateTime.now();
    final cur = _initialKey(widget.granularity);
    switch (_key.granularity) {
      case ArbeitsbereichGranularity.tag:
        return _key.date!.year == now.year &&
            _key.date!.month == now.month &&
            _key.date!.day == now.day;
      case ArbeitsbereichGranularity.woche:
        return _key.kwYear == cur.kwYear && _key.kwNumber == cur.kwNumber;
      case ArbeitsbereichGranularity.monat:
        return _key.year == cur.year && _key.month == cur.month;
    }
  }

  String _headerTitle() {
    // Preferă label-ul de la server (locale de_DE); fallback local.
    final serverLabel = _data?.label;
    if (serverLabel != null && serverLabel.isNotEmpty) return serverLabel;
    switch (_key.granularity) {
      case ArbeitsbereichGranularity.tag:
        return DateFormat('EEE, dd.MM.yyyy', 'de_DE').format(_key.date!);
      case ArbeitsbereichGranularity.woche:
        return 'KW ${_key.kwNumber} / ${_key.kwYear}';
      case ArbeitsbereichGranularity.monat:
        final d = DateTime(_key.year!, _key.month!, 1);
        return DateFormat('MMMM yyyy', 'de_DE').format(d);
    }
  }

  String _headerRange() {
    final d = _data;
    if (d == null) return '';
    switch (_key.granularity) {
      case ArbeitsbereichGranularity.tag:
        return ''; // Titlul include deja data
      case ArbeitsbereichGranularity.woche:
        return '${DateFormat('dd.MM').format(d.rangeStart)} – '
            '${DateFormat('dd.MM.yyyy').format(d.rangeEnd)}';
      case ArbeitsbereichGranularity.monat:
        return '${DateFormat('dd.MM').format(d.rangeStart)} – '
            '${DateFormat('dd.MM.yyyy').format(d.rangeEnd)}';
    }
  }

  String _prevTooltip() {
    switch (_key.granularity) {
      case ArbeitsbereichGranularity.tag:   return 'Vorheriger Tag';
      case ArbeitsbereichGranularity.woche: return 'Vorherige KW';
      case ArbeitsbereichGranularity.monat: return 'Vorheriger Monat';
    }
  }

  String _nextTooltip() {
    switch (_key.granularity) {
      case ArbeitsbereichGranularity.tag:   return 'Nächster Tag';
      case ArbeitsbereichGranularity.woche: return 'Nächste KW';
      case ArbeitsbereichGranularity.monat: return 'Nächster Monat';
    }
  }

  String _jumpTooltip() {
    switch (_key.granularity) {
      case ArbeitsbereichGranularity.tag:   return 'Heute';
      case ArbeitsbereichGranularity.woche: return 'Diese Woche';
      case ArbeitsbereichGranularity.monat: return 'Dieser Monat';
    }
  }

  // ─── Actions ────────────────────────────────────────────────────────

  Future<void> _archiveMember(ArbeitstagMember m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Mitglied archivieren?'),
        content: Text('${m.name} wird aus der aktiven Liste entfernt. '
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

  Future<void> _handleChipTap(ArbeitstagMember m, String typ) async {
    final state = m.stateFor(typ);
    switch (state) {
      case 'offen':
        await _openPicker(m, typ);
        break;
      case 'geplant':
        await _svc.setState(key: _key, userId: m.userId, typ: typ, state: 'in_bearbeitung');
        _load();
        break;
      case 'in_bearbeitung':
        await _svc.setState(key: _key, userId: m.userId, typ: typ, state: 'erledigt');
        _load();
        break;
      case 'erledigt':
        await _handleChipLongPress(m, typ);
        break;
    }
  }

  String _verschiebenLabel() {
    switch (widget.granularity) {
      case ArbeitsbereichGranularity.tag:   return 'Auf morgen verschieben';
      case ArbeitsbereichGranularity.woche: return 'Auf nächste KW verschieben';
      case ArbeitsbereichGranularity.monat: return 'Auf nächsten Monat verschieben';
    }
  }

  Future<void> _handleChipLongPress(ArbeitstagMember m, String typ) async {
    final state = m.stateFor(typ);
    if (state == 'offen') {
      await _openPicker(m, typ);
      return;
    }
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
            ListTile(
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Auswahl ändern'),
              onTap: () => Navigator.pop(ctx, 'change'),
            ),
            // Verschieben pe period următor.
            // Ticket + Routine: modifică sursa (scheduled_date).
            // Termin/Notfall: doar reset chip local (data programării = fixat).
            ListTile(
              leading: const Icon(Icons.skip_next, color: Colors.deepPurple),
              title: Text(_verschiebenLabel()),
              subtitle: (typ == 'ticket' || typ == 'routine')
                  ? const Text('Ändert das geplante Datum')
                  : const Text('Nur Chip zurücksetzen (Termin bleibt)'),
              onTap: () => Navigator.pop(ctx, 'verschieben'),
            ),
            if (state == 'in_bearbeitung')
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.orange),
                title: const Text('Rückgängig → Geplant'),
                onTap: () => Navigator.pop(ctx, 'geplant'),
              )
            else if (state == 'erledigt')
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.blue),
                title: const Text('Rückgängig → In Bearbeitung'),
                onTap: () => Navigator.pop(ctx, 'in_bearbeitung'),
              ),
            ListTile(
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
    } else if (action == 'verschieben') {
      await _svc.verschieben(key: _key, userId: m.userId, typ: typ);
      _load();
    } else {
      await _svc.setState(key: _key, userId: m.userId, typ: typ, state: action);
      _load();
    }
  }

  Future<void> _openHistory(ArbeitstagMember m) async {
    final entries = await _svc.getHistory(
      userId: m.userId,
      granularity: widget.granularity,
      limit: 12,
    );
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
        title: Text('Notiz — ${m.name} (${_headerTitle()})'),
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
    final ok = await _svc.setNotiz(key: _key, userId: m.userId, notiz: saved);
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

    final items = await _svc.getPickerItems(userId: m.userId, typ: typ, key: _key);
    if (!mounted) return;

    final result = await showModalBottomSheet<_PickerResult>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _PickerSheet(
        title: '${_typLabel(typ)} für ${m.name} — ${_headerTitle()}',
        emptyLabel: _emptyLabel(typ),
        items: items,
        currentSelectionId: currentSelectionId,
        canReset: currentSelectionId != null,
      ),
    );

    if (result == null) return;

    final ok = await _svc.setState(
      key: _key,
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
      case 'termin':  return 'Keine zukünftigen Termine für dieses Mitglied';
      case 'routine': return 'Keine offenen Routinen für dieses Mitglied';
      case 'notfall': return 'Keine zukünftigen Notfall-Termine für dieses Mitglied';
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

  // ─── Build ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Column(
      children: [
        _buildHeader(theme),
        const Divider(height: 1),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    final stats = _data?.stats;
    final isCurrent = _isCurrent();
    final rangeStr = _headerRange();
    final title = _headerTitle();
    return Material(
      color: theme.colorScheme.surface,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          children: [
            IconButton(
              onPressed: () => _shift(-1),
              icon: const Icon(Icons.chevron_left),
              tooltip: _prevTooltip(),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis),
                  if (rangeStr.isNotEmpty)
                    Text(rangeStr + (isCurrent ? ' (aktuell)' : ''),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isCurrent ? theme.colorScheme.primary : null,
                          fontWeight: isCurrent ? FontWeight.w600 : FontWeight.normal,
                        ),
                        overflow: TextOverflow.ellipsis)
                  else if (isCurrent)
                    Text('(aktuell)',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        )),
                ],
              ),
            ),
            IconButton(
              onPressed: () => _shift(1),
              icon: const Icon(Icons.chevron_right),
              tooltip: _nextTooltip(),
            ),
            if (!isCurrent)
              IconButton(
                onPressed: _jumpNow,
                icon: const Icon(Icons.today, size: 20),
                tooltip: _jumpTooltip(),
              ),
            if (stats != null && MediaQuery.of(context).size.width >= 600) ...[
              Tooltip(
                message: 'Ticket + Termin + Routine erledigt (Notfall optional)',
                child: _statChip(
                  icon: Icons.check_circle,
                  label: '${stats.totalDone} / ${stats.totalMembers} bearbeitet',
                  color: Colors.green,
                ),
              ),
              if (stats.totalUrgent > 0)
                _statChip(
                  icon: Icons.warning,
                  label: '${stats.totalUrgent} dringend',
                  color: Colors.red,
                ),
            ],
            IconButton(
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh),
              tooltip: 'Aktualisieren',
            ),
            _buildArchiveToggle(),
          ],
        ),
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
    final active = _view == 'archived'
        ? _data!.members
        : _data!.members.where((m) => !m.allDone).toList();
    final done = _view == 'archived'
        ? <ArbeitstagMember>[]
        : _data!.members.where((m) => m.allDone).toList();
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
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
    final label = switch (widget.granularity) {
      ArbeitsbereichGranularity.tag   => 'diesen Tag',
      ArbeitsbereichGranularity.woche => 'diese KW',
      ArbeitsbereichGranularity.monat => 'diesen Monat',
    };
    return Container(
      color: Colors.grey.withValues(alpha: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text('✓ Erledigt $label ($n)',
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
    final content = Padding(
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
                if (m.ticketSubject != null || m.terminTitle != null ||
                    m.routineTitle != null || m.notfallTerminTitle != null ||
                    m.bearbeiterName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Wrap(
                      spacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (m.ticketSubject != null)
                          _linkTitle('🎫', m.ticketSubject!, Colors.green.shade700, 2,
                              focusTicketId: m.ticketId),
                        if (m.terminTitle != null)
                          _linkTitle('📅', m.terminTitle!, Colors.green.shade700, 3,
                              focusTerminId: m.terminId),
                        if (m.routineTitle != null)
                          _linkTitle('🔄', m.routineTitle!, Colors.green.shade700, 10,
                              focusRoutineExecutionId: m.routineExecutionId),
                        if (m.notfallTerminTitle != null)
                          _linkTitle('🚨', m.notfallTerminTitle!, Colors.red.shade700, 3,
                              focusTerminId: m.notfallTerminId),
                        if (m.bearbeiterName != null)
                          _bearbeiterBadge(m.bearbeiterName!),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (!m.isArchived) ...[
            // Ticket rămâne mereu vizibil — nu depinde de period (user alege
            // manual din toate ticketele deschise ale membrului).
            _stateChip(m, 'Ticket', 'ticket', m.ticketState, m.openTicketsCount),
            // Termin/Routine/Notfall — ascunse dacă membrul n-are activitate
            // în period-ul curent și chip-ul e încă offen. Dacă e deja bifat
            // (state != offen), chip-ul rămâne ca să poți vedea/reseta.
            if (m.termineKwCount > 0 || m.terminState != 'offen') ...[
              const SizedBox(width: 6),
              _stateChip(m, 'Termin', 'termin', m.terminState, m.termineKwCount),
            ],
            if (m.routinesKwCount > 0 || m.routineState != 'offen') ...[
              const SizedBox(width: 6),
              _stateChip(m, 'Routine', 'routine', m.routineState, m.routinesKwCount),
            ],
            if (m.notfallKwCount > 0 || m.notfallState != 'offen') ...[
              const SizedBox(width: 6),
              _stateChip(m, 'Notfall', 'notfall', m.notfallState, m.notfallKwCount),
            ],
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
    );
    return dimmed ? Opacity(opacity: 0.55, child: content) : content;
  }

  IconData _iconFor(String typ, String state) {
    if (state == 'geplant')        return Icons.hourglass_bottom;
    if (state == 'in_bearbeitung') return Icons.autorenew;
    if (state == 'erledigt')       return Icons.check_circle;
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
    final noAvailable = isOffen && badgeCount == 0;
    final chip = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: () => _handleChipTap(m, typ),
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
        ),
        if (!isOffen)
          InkWell(
            onTap: () => _handleChipLongPress(m, typ),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.more_vert, size: 16, color: color.withValues(alpha: 0.7)),
            ),
          ),
      ],
    );
    return noAvailable ? Opacity(opacity: 0.35, child: chip) : chip;
  }

  Widget _linkTitle(String emoji, String title, Color color, int menuIndex,
      {int? focusTicketId, int? focusTerminId, int? focusRoutineExecutionId}) {
    return InkWell(
      onTap: widget.onNavigate == null
          ? null
          : () => widget.onNavigate!(menuIndex,
              focusTicketId: focusTicketId,
              focusTerminId: focusTerminId,
              focusRoutineExecutionId: focusRoutineExecutionId),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
        child: Text('$emoji $title',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              decoration: widget.onNavigate == null ? null : TextDecoration.underline,
              decorationStyle: TextDecorationStyle.dotted,
            )),
      ),
    );
  }

  Widget _bearbeiterBadge(String name) {
    final parts = name.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    final initials = parts.isEmpty
        ? '?'
        : parts.length == 1 ? parts[0].substring(0, 1).toUpperCase()
        : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.person, size: 11, color: Colors.blueGrey.shade700),
          const SizedBox(width: 3),
          Text(initials,
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.blueGrey.shade800)),
        ],
      ),
    );
  }
}

// ─── Picker sheet ────────────────────────────────────────────────────

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

// ─── History dialog ─────────────────────────────────────────────────

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

  String _periodBadge(ArbeitstagHistoryEntry e) {
    if (e.periodLabel.isNotEmpty) return e.periodLabel;
    switch (e.granularity) {
      case ArbeitsbereichGranularity.tag:
        return e.date != null ? DateFormat('dd.MM.yyyy').format(e.date!) : '—';
      case ArbeitsbereichGranularity.woche:
        return 'KW ${e.kwNumber} / ${e.kwYear}';
      case ArbeitsbereichGranularity.monat:
        return e.year != null && e.month != null
            ? DateFormat('MMMM yyyy', 'de_DE').format(DateTime(e.year!, e.month!, 1))
            : '—';
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
                        Text('${member.mitgliedernummer} · letzte ${entries.length} Einträge',
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
                                  child: Text(_periodBadge(e),
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
