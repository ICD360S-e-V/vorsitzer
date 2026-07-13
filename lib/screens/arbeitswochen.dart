import 'package:flutter/material.dart';
import '../services/arbeitstag_service.dart';
import 'arbeitsbereich_view.dart';

/// Tab „Arbeitswochen" — view per KW (ISO-week).
/// Wrapper subțire — logica UI e în [ArbeitsbereichView].
class ArbeitswochenPage extends StatelessWidget {
  final void Function(int menuIndex,
      {int? focusTicketId,
      int? focusTerminId,
      int? focusRoutineExecutionId})? onNavigate;

  const ArbeitswochenPage({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ArbeitsbereichView(
      granularity: ArbeitsbereichGranularity.woche,
      onNavigate: onNavigate,
    );
  }
}
