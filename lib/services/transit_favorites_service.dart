import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'transit_service.dart';

/// Persistent auto-tracked history of Verbindung-searches.
///
/// Every successful search records `(from, to)` and increments a hit counter.
/// Ranked by weighted recency + frequency so the routes the user actually
/// takes every morning bubble to the top of the quick-pick chip row.
///
/// Storage: SharedPreferences, JSON blob under key `transit.favorites.v1`.
class TransitFavoritesService {
  static const _key = 'transit.favorites.v1';
  static const _maxEntries = 20;
  static const _quickPickCount = 5;

  static Future<List<TransitFavorite>> load() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final List<dynamic> list = jsonDecode(raw);
      return list.map((e) => TransitFavorite.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Persist a search. Increments the hit counter if `(from.name, to.name)`
  /// already exists (case-insensitive), else inserts. Trims to [_maxEntries].
  static Future<void> record(TransitLocation from, TransitLocation to) async {
    final entries = await load();
    final fromKey = from.name.trim().toLowerCase();
    final toKey = to.name.trim().toLowerCase();
    if (fromKey.isEmpty || toKey.isEmpty) return;

    final now = DateTime.now();
    final idx = entries.indexWhere(
      (e) => e.fromName.trim().toLowerCase() == fromKey && e.toName.trim().toLowerCase() == toKey,
    );
    if (idx >= 0) {
      final old = entries[idx];
      entries[idx] = old.copyWith(
        hits: old.hits + 1,
        lastUsed: now,
        // Refresh coordinate fields — they may have improved since the first record.
        fromLat: from.lat ?? old.fromLat,
        fromLon: from.lon ?? old.fromLon,
        toLat: to.lat ?? old.toLat,
        toLon: to.lon ?? old.toLon,
      );
    } else {
      entries.add(TransitFavorite(
        fromId: from.id,
        fromName: from.name,
        fromLat: from.lat,
        fromLon: from.lon,
        toId: to.id,
        toName: to.name,
        toLat: to.lat,
        toLon: to.lon,
        hits: 1,
        lastUsed: now,
        firstUsed: now,
      ));
    }

    entries.sort((a, b) => _score(b, now).compareTo(_score(a, now)));
    if (entries.length > _maxEntries) entries.removeRange(_maxEntries, entries.length);
    await _write(entries);
  }

  /// Top N by weighted rank for chip display. Empty until user has searched.
  static Future<List<TransitFavorite>> topPicks({int limit = _quickPickCount}) async {
    final all = await load();
    if (all.isEmpty) return [];
    final now = DateTime.now();
    all.sort((a, b) => _score(b, now).compareTo(_score(a, now)));
    return all.take(limit).toList();
  }

  static Future<void> remove(TransitFavorite fav) async {
    final entries = await load();
    entries.removeWhere((e) =>
        e.fromName.toLowerCase() == fav.fromName.toLowerCase() &&
        e.toName.toLowerCase() == fav.toName.toLowerCase());
    await _write(entries);
  }

  static Future<void> _write(List<TransitFavorite> entries) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(_key, jsonEncode(entries.map((e) => e.toJson()).toList()));
  }

  /// Rank = hits × log(1 + hits) × recency-decay.
  /// Frequency wins for daily commutes; single one-off searches decay in ~10 days.
  static double _score(TransitFavorite e, DateTime now) {
    final ageDays = now.difference(e.lastUsed).inMinutes / (60 * 24);
    final freq = e.hits.toDouble();
    final freqBoost = freq * (1 + freq * 0.15);
    final decay = 1 / (1 + ageDays * 0.1);
    return freqBoost * decay;
  }
}

class TransitFavorite {
  final String fromId;
  final String fromName;
  final double? fromLat;
  final double? fromLon;
  final String toId;
  final String toName;
  final double? toLat;
  final double? toLon;
  final int hits;
  final DateTime lastUsed;
  final DateTime firstUsed;

  const TransitFavorite({
    required this.fromId,
    required this.fromName,
    this.fromLat,
    this.fromLon,
    required this.toId,
    required this.toName,
    this.toLat,
    this.toLon,
    required this.hits,
    required this.lastUsed,
    required this.firstUsed,
  });

  TransitLocation get fromLocation => TransitLocation(
        id: fromId, name: fromName, lat: fromLat, lon: fromLon,
      );
  TransitLocation get toLocation => TransitLocation(
        id: toId, name: toName, lat: toLat, lon: toLon,
      );

  /// Compact chip label — trims to the last meaningful token so
  /// "Ulm, Rathaus" and "Neu-Ulm, Bahnhof" fit in a chip row.
  String get chipLabel {
    String _short(String s) {
      final trimmed = s.trim();
      if (trimmed.length <= 22) return trimmed;
      final comma = trimmed.indexOf(',');
      if (comma > 0 && comma < 20) return trimmed.substring(0, comma);
      return '${trimmed.substring(0, 20)}…';
    }
    return '${_short(fromName)} → ${_short(toName)}';
  }

  TransitFavorite copyWith({
    int? hits,
    DateTime? lastUsed,
    double? fromLat,
    double? fromLon,
    double? toLat,
    double? toLon,
  }) =>
      TransitFavorite(
        fromId: fromId,
        fromName: fromName,
        fromLat: fromLat ?? this.fromLat,
        fromLon: fromLon ?? this.fromLon,
        toId: toId,
        toName: toName,
        toLat: toLat ?? this.toLat,
        toLon: toLon ?? this.toLon,
        hits: hits ?? this.hits,
        lastUsed: lastUsed ?? this.lastUsed,
        firstUsed: firstUsed,
      );

  Map<String, dynamic> toJson() => {
        'fromId': fromId,
        'fromName': fromName,
        'fromLat': fromLat,
        'fromLon': fromLon,
        'toId': toId,
        'toName': toName,
        'toLat': toLat,
        'toLon': toLon,
        'hits': hits,
        'lastUsed': lastUsed.toIso8601String(),
        'firstUsed': firstUsed.toIso8601String(),
      };

  factory TransitFavorite.fromJson(Map<String, dynamic> j) => TransitFavorite(
        fromId: j['fromId'] as String? ?? '',
        fromName: j['fromName'] as String? ?? '',
        fromLat: (j['fromLat'] as num?)?.toDouble(),
        fromLon: (j['fromLon'] as num?)?.toDouble(),
        toId: j['toId'] as String? ?? '',
        toName: j['toName'] as String? ?? '',
        toLat: (j['toLat'] as num?)?.toDouble(),
        toLon: (j['toLon'] as num?)?.toDouble(),
        hits: j['hits'] as int? ?? 1,
        lastUsed: DateTime.tryParse(j['lastUsed'] as String? ?? '') ?? DateTime.now(),
        firstUsed: DateTime.tryParse(j['firstUsed'] as String? ?? '') ?? DateTime.now(),
      );
}
