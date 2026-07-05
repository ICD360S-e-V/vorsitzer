import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'transit_service.dart';

/// Snapshot of the last successful "nearby stops + departures" fetch,
/// persisted so the Echtzeit tab can degrade gracefully when the network
/// is down (U-Bahn tunnel, Behörde-hall, roaming cutoff, prepaid credit
/// exhausted — real cases for ICD-Jobcenter target audience).
///
/// TTL is soft: we return older snapshots too, but the UI tags them with
/// a freshness banner so the user knows they're not real-time.
class TransitOfflineSnapshot {
  final List<TransitStop> stops;
  final List<Departure> departures;
  final String city;
  final DateTime capturedAt;

  const TransitOfflineSnapshot({
    required this.stops,
    required this.departures,
    required this.city,
    required this.capturedAt,
  });

  Map<String, dynamic> toJson() => {
        'stops': stops.map((s) => s.toJson()).toList(),
        'departures': departures.map((d) => d.toJson()).toList(),
        'city': city,
        'capturedAt': capturedAt.toIso8601String(),
      };

  factory TransitOfflineSnapshot.fromJson(Map<String, dynamic> j) => TransitOfflineSnapshot(
        stops: (j['stops'] as List? ?? [])
            .map((e) => TransitStop.fromJson(e as Map<String, dynamic>))
            .toList(),
        departures: (j['departures'] as List? ?? [])
            .map((e) => Departure.fromJson(e as Map<String, dynamic>))
            .toList(),
        city: j['city'] as String? ?? '',
        capturedAt: DateTime.tryParse(j['capturedAt'] as String? ?? '') ?? DateTime.fromMillisecondsSinceEpoch(0),
      );

  /// Age from now; used to decide freshness banner color.
  Duration get age => DateTime.now().difference(capturedAt);
  bool get isFresh => age < const Duration(minutes: 15);
  bool get isStale => age > const Duration(hours: 4);
}

class TransitOfflineCache {
  static const _key = 'transit.offline_snapshot.v1';

  /// Save the latest successful fetch. Called after `fetchDepartures()`
  /// yields non-empty data. Errors are swallowed (cache is best-effort).
  static Future<void> save({
    required List<TransitStop> stops,
    required List<Departure> departures,
    required String city,
  }) async {
    if (stops.isEmpty && departures.isEmpty) return;
    try {
      final snap = TransitOfflineSnapshot(
        stops: stops,
        departures: departures,
        city: city,
        capturedAt: DateTime.now(),
      );
      final sp = await SharedPreferences.getInstance();
      await sp.setString(_key, jsonEncode(snap.toJson()));
    } catch (_) {}
  }

  /// Load the last snapshot, or null if none / corrupted.
  static Future<TransitOfflineSnapshot?> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final raw = sp.getString(_key);
      if (raw == null || raw.isEmpty) return null;
      return TransitOfflineSnapshot.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final sp = await SharedPreferences.getInstance();
    await sp.remove(_key);
  }
}
