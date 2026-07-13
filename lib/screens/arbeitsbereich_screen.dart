import 'package:flutter/material.dart';
import 'arbeitstag.dart';
import 'arbeitswochen.dart';
import 'arbeitsmonat.dart';

/// „Arbeitsbereich" — container-ul rădăcină pentru cele 3 tab-uri temporale:
/// Arbeitstag (per zi) / Arbeitswochen (per KW) / Arbeitsmonat (per lună).
///
/// Fiecare tab afișează aceeași structură (membri × 4 chip-uri: Ticket / Termin /
/// Routine / Notfall) filtrată pe granularitatea aleasă.
///
/// [initialIndex] = 1 → tab-ul „Arbeitswochen" e activ la deschidere (view-ul
/// de bază pe care echipa deja îl folosește).
class ArbeitsbereichScreen extends StatefulWidget {
  final void Function(int menuIndex,
      {int? focusTicketId,
      int? focusTerminId,
      int? focusRoutineExecutionId})? onNavigate;

  final int initialIndex;

  const ArbeitsbereichScreen({
    super.key,
    this.onNavigate,
    this.initialIndex = 1,
  });

  @override
  State<ArbeitsbereichScreen> createState() => _ArbeitsbereichScreenState();
}

class _ArbeitsbereichScreenState extends State<ArbeitsbereichScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialIndex.clamp(0, 2),
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Material(
          color: theme.colorScheme.surface,
          elevation: 1,
          child: TabBar(
            controller: _tabController,
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            indicatorColor: theme.colorScheme.primary,
            tabs: const [
              Tab(icon: Icon(Icons.today), text: 'Arbeitstag'),
              Tab(icon: Icon(Icons.date_range), text: 'Arbeitswochen'),
              Tab(icon: Icon(Icons.calendar_view_month), text: 'Arbeitsmonat'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              ArbeitstagPage(onNavigate: widget.onNavigate),
              ArbeitswochenPage(onNavigate: widget.onNavigate),
              ArbeitsmonatPage(onNavigate: widget.onNavigate),
            ],
          ),
        ),
      ],
    );
  }
}
