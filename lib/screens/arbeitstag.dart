import 'package:flutter/material.dart';
import '../services/arbeitstag_service.dart';
import 'arbeitsbereich_view.dart';

/// Tab „Arbeitstag" — view per zi calendaristică.
///
/// Wrapper foarte subțire — toată logica UI trăiește în [ArbeitsbereichView].
class ArbeitstagPage extends StatelessWidget {
  final void Function(int menuIndex,
      {int? focusTicketId,
      int? focusTerminId,
      int? focusRoutineExecutionId})? onNavigate;

  const ArbeitstagPage({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ArbeitsbereichView(
      granularity: ArbeitsbereichGranularity.tag,
      onNavigate: onNavigate,
    );
  }
}
