import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// One journey the user actually took (or tried to take). Persisted across
/// sessions so the ÖPNV dialog can show a "Historie" section with the last
/// 20 trips + status.
///
/// Status semantics:
///   - `boarded`   — user opened trip-sequence dialog for this departure,
///                   auto-recorded when they picked a target stop.
///   - `arrived`   — Ausstieg-Alarm fired at their chosen target within 150 m.
///   - `missed`    — user set a target but never got within 150 m before
///                   dialog was closed AND scheduled dep time is >5 min old.
///   - `cancelled` — user closed the dialog before setting a target.
///
/// Time-based inferences run once when the trip dialog closes.
enum TransitTripStatus { boarded, arrived, missed, cancelled }

class TransitHistoryEntry {
  final String line;
  final String direction;
  final String? fromStop;
  final String? toStop;
  final DateTime plannedDep;
  final DateTime recordedAt;
  final TransitTripStatus status;

  const TransitHistoryEntry({
    required this.line,
    required this.direction,
    this.fromStop,
    this.toStop,
    required this.plannedDep,
    required this.recordedAt,
    required this.status,
  });

  Map<String, dynamic> toJson() => {
        'line': line,
        'direction': direction,
        'fromStop': fromStop,
        'toStop': toStop,
        'plannedDep': plannedDep.toIso8601String(),
        'recordedAt': recordedAt.toIso8601String(),
        'status': status.name,
      };

  factory TransitHistoryEntry.fromJson(Map<String, dynamic> j) => TransitHistoryEntry(
        line: j['line'] as String? ?? '',
        direction: j['direction'] as String? ?? '',
        fromStop: j['fromStop'] as String?,
        toStop: j['toStop'] as String?,
        plannedDep: DateTime.tryParse(j['plannedDep'] as String? ?? '') ?? DateTime.now(),
        recordedAt: DateTime.tryParse(j['recordedAt'] as String? ?? '') ?? DateTime.now(),
        status: TransitTripStatus.values.firstWhere(
          (s) => s.name == (j['status'] as String? ?? 'cancelled'),
          orElse: () => TransitTripStatus.cancelled,
        ),
      );

  TransitHistoryEntry copyWith({
    String? toStop,
    TransitTripStatus? status,
  }) =>
      TransitHistoryEntry(
        line: line,
        direction: direction,
        fromStop: fromStop,
        toStop: toStop ?? this.toStop,
        plannedDep: plannedDep,
        recordedAt: recordedAt,
        status: status ?? this.status,
      );
}

class TransitHistoryService {
  static const _key = 'transit.history.v1';
  static const _maxEntries = 20;

  /// Load all persisted history, most-recent first.
  static Future<List<TransitHistoryEntry>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw);
      final all = list
          .map((e) => TransitHistoryEntry.fromJson(e as Map<String, dynamic>))
          .toList();
      all.sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
      return all;
    } catch (_) {
      return [];
    }
  }

  /// Insert or update an entry keyed by `(line + plannedDep + direction)`.
  /// Same trip re-opened → status can be upgraded (cancelled → boarded → arrived).
  static Future<void> record(TransitHistoryEntry entry) async {
    final all = await load();
    final key = _key3(entry.line, entry.plannedDep, entry.direction);
    final idx = all.indexWhere((e) => _key3(e.line, e.plannedDep, e.direction) == key);
    if (idx >= 0) {
      // Never DOWNGRADE — arrived stays arrived even if user re-opens later.
      final existing = all[idx];
      if (_rank(entry.status) > _rank(existing.status)) {
        all[idx] = existing.copyWith(status: entry.status, toStop: entry.toStop);
      } else if (entry.toStop != null && existing.toStop == null) {
        all[idx] = existing.copyWith(toStop: entry.toStop);
      }
    } else {
      all.insert(0, entry);
    }
    if (all.length > _maxEntries) all.removeRange(_maxEntries, all.length);
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(all.map((e) => e.toJson()).toList()));
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }

  static String _key3(String line, DateTime dep, String dir) =>
      '$line|${dep.toIso8601String()}|$dir';

  static int _rank(TransitTripStatus s) {
    switch (s) {
      case TransitTripStatus.cancelled: return 0;
      case TransitTripStatus.boarded:   return 1;
      case TransitTripStatus.missed:    return 2;
      case TransitTripStatus.arrived:   return 3;
    }
  }
}
