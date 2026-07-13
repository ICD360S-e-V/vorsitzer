import 'package:flutter/material.dart';
import '../services/arbeitstag_service.dart';
import 'arbeitsbereich_view.dart';

/// Tab „Arbeitsmonat" — view per lună calendaristică.
/// Wrapper subțire — logica UI e în [ArbeitsbereichView].
class ArbeitsmonatPage extends StatelessWidget {
  final void Function(int menuIndex,
      {int? focusTicketId,
      int? focusTerminId,
      int? focusRoutineExecutionId})? onNavigate;

  const ArbeitsmonatPage({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ArbeitsbereichView(
      granularity: ArbeitsbereichGranularity.monat,
      onNavigate: onNavigate,
    );
  }
}
