import 'transit_history_service.dart';

/// Detectează pattern-uri recurente în TransitHistoryService.
///
/// Motivație: mulți membri ICD au rute repetitive Lun-Vin dimineața (spre
/// Jobcenter, KH, Schule). Când vedem >=3 călătorii în același interval-orar
/// pe zile de weekday similare cu aceeași direcție → considerăm "Morgen-Route".
///
/// Nu are storage propriu — trage direct din TransitHistoryService.
class TransitPatternService {
  /// Minimum de călătorii identice necesare ca să considerăm pattern valid.
  static const _minOccurrences = 3;
  /// Fereastra orară în care intrările sunt considerate "aceeași oră".
  static const _timeWindowMinutes = 45;

  /// Detectat pattern (poate fi null când history-ul e prea sărac).
  static Future<TransitRoutinePattern?> detectMorningPattern() async {
    final all = await TransitHistoryService.load();
    if (all.length < _minOccurrences) return null;

    // Grupăm după (line, direction, weekday, hour-window).
    final Map<String, List<TransitHistoryEntry>> buckets = {};
    for (final e in all) {
      // Doar boarded/arrived (nu cancelled) — cele completate.
      if (e.status == TransitTripStatus.cancelled) continue;
      final wd = e.plannedDep.weekday; // 1..7 (mo..su)
      if (wd > 5) continue; // doar workdays pentru Morgen-Route
      // Bucket-key: line + direction + weekday-of-week + hour-of-day.
      final hour = e.plannedDep.hour;
      // Doar dimineață = 5-11.
      if (hour < 5 || hour > 11) continue;
      final key = '${e.line}|${e.direction}|$hour';
      (buckets[key] ??= []).add(e);
    }
    if (buckets.isEmpty) return null;
    // Găsim bucket-ul cel mai mare care are minimum entries.
    List<TransitHistoryEntry>? best;
    for (final b in buckets.values) {
      if (b.length < _minOccurrences) continue;
      if (best == null || b.length > best.length) best = b;
    }
    if (best == null) return null;

    // Mediana timp-of-departure pentru afișare.
    final times = best.map((e) => e.plannedDep.hour * 60 + e.plannedDep.minute).toList()
      ..sort();
    final medianMinutes = times[times.length ~/ 2];
    final medianHour = medianMinutes ~/ 60;
    final medianMin = medianMinutes % 60;

    return TransitRoutinePattern(
      line: best.first.line,
      direction: best.first.direction,
      fromStop: best.first.fromStop,
      toStop: best.first.toStop,
      medianHour: medianHour,
      medianMinute: medianMin,
      occurrences: best.length,
      // Windowul e ±(_timeWindowMinutes / 2) în jurul medianei.
      windowMinutes: _timeWindowMinutes,
    );
  }
}

class TransitRoutinePattern {
  final String line;
  final String direction;
  final String? fromStop;
  final String? toStop;
  final int medianHour;   // 0..23
  final int medianMinute; // 0..59
  final int occurrences;
  final int windowMinutes;

  const TransitRoutinePattern({
    required this.line,
    required this.direction,
    this.fromStop,
    this.toStop,
    required this.medianHour,
    required this.medianMinute,
    required this.occurrences,
    required this.windowMinutes,
  });

  /// Formatare pentru chip: "🌅 07:15 Linie X" (Muster).
  String get chipLabel {
    final hh = medianHour.toString().padLeft(2, '0');
    final mm = medianMinute.toString().padLeft(2, '0');
    return '🌅 $hh:$mm • $line';
  }

  /// Descriere pentru tooltip / detaliu.
  String get detailLabel {
    final hh = medianHour.toString().padLeft(2, '0');
    final mm = medianMinute.toString().padLeft(2, '0');
    return 'Deine Morgen-Route: Linie $line nach $direction — '
        'meist gg. $hh:$mm ($occurrences× gefahren).';
  }
}
