import 'package:flutter/material.dart';
import 'arbeitswochen.dart';

/// „Arbeitsbereich" — container-ul rădăcină.
///
/// Anterior avea 3 tab-uri temporale (Arbeitstag / Arbeitswochen / Arbeitsmonat).
/// Arbeitstag și Arbeitsmonat au fost scoase — nu aveau relevanță practică,
/// planificarea se face pe săptămână. A rămas doar view-ul pe KW, afișat direct
/// (fără TabBar, fiindcă n-are între ce comuta).
class ArbeitsbereichScreen extends StatelessWidget {
  final void Function(int menuIndex,
      {int? focusTicketId,
      int? focusTerminId,
      int? focusRoutineExecutionId})? onNavigate;

  const ArbeitsbereichScreen({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return ArbeitswochenPage(onNavigate: onNavigate);
  }
}
