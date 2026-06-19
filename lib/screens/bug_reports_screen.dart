import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/bug_report_service.dart';
import '../services/chat_service.dart';
import '../widgets/eastern.dart';

class BugReportsScreen extends StatefulWidget {
  final String currentMitgliedernummer;

  const BugReportsScreen({super.key, required this.currentMitgliedernummer});

  @override
  State<BugReportsScreen> createState() => _BugReportsScreenState();
}

class _BugReportsScreenState extends State<BugReportsScreen> with SingleTickerProviderStateMixin {
  static const _tabs = [
    ('new', 'Neu', Color(0xFFE53935)),
    ('in_progress', 'In Bearbeitung', Color(0xFFFB8C00)),
    ('resolved', 'Erledigt', Color(0xFF43A047)),
    ('dismissed', 'Verworfen', Color(0xFF757575)),
  ];

  final _service = BugReportService();
  late TabController _tab;
  StreamSubscription<int>? _wsSub;

  bool _loading = true;
  List<BugReport> _items = [];
  Map<String, int> _counts = const {'new': 0, 'in_progress': 0, 'resolved': 0, 'dismissed': 0};
  String _search = '';
  String _sort = 'newest';

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tab.indexIsChanging) _load();
      });
    _load();

    final stream = ChatService().bugReportStream;
    _wsSub = stream.listen((_) {
      if (mounted && _tab.index == 0) _load();
      if (mounted) _refreshCounts();
    });
  }

  @override
  void dispose() {
    _wsSub?.cancel();
    _tab.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final status = _tabs[_tab.index].$1;
    final result = await _service.list(
      mitgliedernummer: widget.currentMitgliedernummer,
      status: status,
    );
    if (!mounted) return;
    setState(() {
      _items = result?.items ?? [];
      _counts = result?.counts ?? _counts;
      _loading = false;
    });
  }

  Future<void> _refreshCounts() async {
    final result = await _service.list(
      mitgliedernummer: widget.currentMitgliedernummer,
      status: _tabs[_tab.index].$1,
      limit: 1,
    );
    if (!mounted || result == null) return;
    setState(() => _counts = result.counts);
  }

  List<BugReport> get _filteredSorted {
    final filtered = _search.isEmpty
        ? _items
        : _items.where((r) =>
            r.description.toLowerCase().contains(_search.toLowerCase()) ||
            (r.mitgliedernummer?.toLowerCase().contains(_search.toLowerCase()) ?? false)).toList();
    final sorted = [...filtered];
    switch (_sort) {
      case 'oldest':
        sorted.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        break;
      case 'members_only':
        sorted.sort((a, b) {
          final am = (a.mitgliedernummer ?? '').isNotEmpty ? 0 : 1;
          final bm = (b.mitgliedernummer ?? '').isNotEmpty ? 0 : 1;
          if (am != bm) return am - bm;
          return b.createdAt.compareTo(a.createdAt);
        });
        break;
      default:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    }
    return sorted;
  }

  String _relative(DateTime when) {
    final diff = DateTime.now().difference(when);
    if (diff.inSeconds < 60) return 'gerade eben';
    if (diff.inMinutes < 60) return 'vor ${diff.inMinutes} Min';
    if (diff.inHours < 24) return 'vor ${diff.inHours} Std';
    if (diff.inDays < 7) return 'vor ${diff.inDays} Tag${diff.inDays > 1 ? 'en' : ''}';
    return DateFormat('dd.MM.yyyy HH:mm', 'de_DE').format(when);
  }

  Color _statusColor(String status) {
    final t = _tabs.firstWhere((e) => e.$1 == status, orElse: () => _tabs[0]);
    return t.$3;
  }

  @override
  Widget build(BuildContext context) {
    return SeasonalBackground(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
            child: Row(
              children: [
                Icon(Icons.bug_report_outlined, size: 32, color: Colors.red.shade700),
                const SizedBox(width: 12),
                const Text('Rapoarte de probleme',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  tooltip: 'Aktualisieren',
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Caută în descriere…',
                      prefixIcon: Icon(Icons.search),
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => setState(() => _search = v),
                  ),
                ),
                const SizedBox(width: 12),
                DropdownButton<String>(
                  value: _sort,
                  items: const [
                    DropdownMenuItem(value: 'newest', child: Text('Cele mai noi')),
                    DropdownMenuItem(value: 'oldest', child: Text('Cele mai vechi')),
                    DropdownMenuItem(value: 'members_only', child: Text('Membri logați primii')),
                  ],
                  onChanged: (v) => setState(() => _sort = v ?? 'newest'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          TabBar(
            controller: _tab,
            isScrollable: true,
            labelColor: const Color(0xFF4a90d9),
            unselectedLabelColor: Colors.grey.shade700,
            indicatorColor: const Color(0xFF4a90d9),
            tabs: [
              for (final t in _tabs) _tabWithBadge(t.$2, _counts[t.$1] ?? 0, t.$3),
            ],
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: _filteredSorted.isEmpty
                        ? ListView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: MediaQuery.of(context).size.height * 0.5,
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 64, color: Colors.grey.shade400),
                                      const SizedBox(height: 16),
                                      Text('Keine Einträge',
                                          style: TextStyle(color: Colors.grey.shade600, fontSize: 16)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            itemCount: _filteredSorted.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 8),
                            itemBuilder: (_, i) => _buildCard(_filteredSorted[i]),
                          ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _tabWithBadge(String label, int count, Color color) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label),
          if (count > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count', style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCard(BugReport report) {
    final color = _statusColor(report.status);
    return Card(
      elevation: 1,
      child: InkWell(
        onTap: () => _openDetail(report),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(Icons.bug_report_outlined, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(report.memberDisplay,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(report.statusDisplay,
                              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(report.description,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 12, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(_relative(report.createdAt),
                            style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                        if (report.internalNotes != null && report.internalNotes!.isNotEmpty) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.sticky_note_2_outlined, size: 12, color: Colors.grey.shade600),
                          const SizedBox(width: 4),
                          Text('Notiz',
                              style: TextStyle(color: Colors.grey.shade600, fontSize: 11)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openDetail(BugReport report) async {
    final notesCtrl = TextEditingController(text: report.internalNotes ?? '');
    final updated = await showModalBottomSheet<BugReport>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _DetailSheet(
        report: report,
        notesCtrl: notesCtrl,
        onAction: (action, notes) async {
          final newStatus = switch (action) {
            'in_progress' => 'in_progress',
            'resolved' => 'resolved',
            'dismissed' => 'dismissed',
            'reopen' => 'new',
            _ => null,
          };
          final result = await _service.update(
            mitgliedernummer: widget.currentMitgliedernummer,
            id: report.id,
            status: newStatus,
            internalNotes: notes,
          );
          if (ctx.mounted) Navigator.of(ctx).pop(result);
        },
        statusColor: _statusColor,
        relative: _relative,
      ),
    );

    if (updated != null && mounted) {
      final currentStatus = _tabs[_tab.index].$1;
      setState(() {
        if (updated.status == currentStatus) {
          _items = [for (final r in _items) r.id == updated.id ? updated : r];
        } else {
          _items = _items.where((r) => r.id != updated.id).toList();
        }
      });
      await _refreshCounts();
    }
  }
}

class _DetailSheet extends StatelessWidget {
  final BugReport report;
  final TextEditingController notesCtrl;
  final Future<void> Function(String action, String notes) onAction;
  final Color Function(String) statusColor;
  final String Function(DateTime) relative;

  const _DetailSheet({
    required this.report,
    required this.notesCtrl,
    required this.onAction,
    required this.statusColor,
    required this.relative,
  });

  @override
  Widget build(BuildContext context) {
    final color = statusColor(report.status);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 20 + bottomInset),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(Icons.bug_report_outlined, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(report.memberDisplay,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      Text('#${report.id} · ${relative(report.createdAt)}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(report.statusDisplay,
                      style: TextStyle(color: color, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const Divider(height: 24),
            const Text('Beschreibung', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            SelectableText(report.description, style: const TextStyle(fontSize: 14)),
            const SizedBox(height: 16),
            if (report.resolvedAt != null) ...[
              Text('Bearbeitet ${relative(report.resolvedAt!)}${report.resolvedBy != null ? ' · ${report.resolvedBy}' : ''}',
                  style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
              const SizedBox(height: 12),
            ],
            const Text('Interne Notizen', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            TextField(
              controller: notesCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Nur intern sichtbar…',
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (report.status == 'new')
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow, size: 18),
                    label: const Text('In Bearbeitung'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFB8C00), foregroundColor: Colors.white),
                    onPressed: () => onAction('in_progress', notesCtrl.text),
                  ),
                if (report.status != 'resolved')
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Erledigt'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF43A047), foregroundColor: Colors.white),
                    onPressed: () => onAction('resolved', notesCtrl.text),
                  ),
                if (report.status != 'dismissed')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.close, size: 18),
                    label: const Text('Verwerfen'),
                    onPressed: () => onAction('dismissed', notesCtrl.text),
                  ),
                if (report.status == 'resolved' || report.status == 'dismissed')
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Wiedereröffnen'),
                    onPressed: () => onAction('reopen', notesCtrl.text),
                  ),
                TextButton(
                  onPressed: () => onAction('notes_only', notesCtrl.text),
                  child: const Text('Nur Notizen speichern'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
