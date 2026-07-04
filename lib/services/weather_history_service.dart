import 'dart:async';
import 'dart:convert';

import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_client_factory.dart';
import 'logger_service.dart';

final _log = LoggerService();

/// Aggregate daily numbers for one 7-day slice from the Open-Meteo Archive.
///
/// A "slice" is the same calendar dates as the current week but N years back —
/// e.g. if today is Sat 04.07.2026 the 1-year-ago slice covers 04.07.2025 to
/// 10.07.2025. That way "vs last year" compares apples with apples.
class HistoricalWeekSummary {
  final int yearsAgo;             // 1, 2, 3
  final DateTime start;
  final DateTime end;
  final double? avgTempMax;       // Ø max temp of the week (°C)
  final double? avgTempMin;       // Ø min temp of the week (°C)
  final double? totalPrecipitation; // sum of precipitation over the week (mm)
  final double? maxWindSpeed;     // strongest wind gust of the week (km/h)

  const HistoricalWeekSummary({
    required this.yearsAgo,
    required this.start,
    required this.end,
    required this.avgTempMax,
    required this.avgTempMin,
    required this.totalPrecipitation,
    required this.maxWindSpeed,
  });

  Map<String, dynamic> toJson() => {
        'yearsAgo': yearsAgo,
        'start': start.toIso8601String(),
        'end': end.toIso8601String(),
        'avgTempMax': avgTempMax,
        'avgTempMin': avgTempMin,
        'totalPrecipitation': totalPrecipitation,
        'maxWindSpeed': maxWindSpeed,
      };

  factory HistoricalWeekSummary.fromJson(Map<String, dynamic> j) => HistoricalWeekSummary(
        yearsAgo: j['yearsAgo'] as int,
        start: DateTime.parse(j['start'] as String),
        end: DateTime.parse(j['end'] as String),
        avgTempMax: (j['avgTempMax'] as num?)?.toDouble(),
        avgTempMin: (j['avgTempMin'] as num?)?.toDouble(),
        totalPrecipitation: (j['totalPrecipitation'] as num?)?.toDouble(),
        maxWindSpeed: (j['maxWindSpeed'] as num?)?.toDouble(),
      );
}

/// Fetches the same-week weather from the last N years so the UI can show
/// "diese Woche vs. das letzte Jahr". Data comes from the free Open-Meteo
/// Archive API (no key, no rate-limit for our tiny load) and is cached in
/// SharedPreferences — historical daily numbers never change, so a one-off
/// fetch per (location, week, year) is enough.
class WeatherHistoryService {
  final _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  static const _spKeyPrefix = 'weather_history_v1_';

  /// Fetch [yearsBack] slices, one per calendar year, for the week starting at
  /// [weekStart]. Slices are returned in ascending years-ago (1 first).
  Future<List<HistoricalWeekSummary>> fetchWeekComparison({
    required double lat,
    required double lon,
    required DateTime weekStart,
    int yearsBack = 3,
  }) async {
    final start = DateTime(weekStart.year, weekStart.month, weekStart.day);
    final futures = <Future<HistoricalWeekSummary?>>[];
    for (int i = 1; i <= yearsBack; i++) {
      futures.add(_fetchOneYear(lat: lat, lon: lon, weekStart: start, yearsAgo: i));
    }
    final results = await Future.wait(futures);
    return results.whereType<HistoricalWeekSummary>().toList();
  }

  Future<HistoricalWeekSummary?> _fetchOneYear({
    required double lat,
    required double lon,
    required DateTime weekStart,
    required int yearsAgo,
  }) async {
    final start = DateTime(weekStart.year - yearsAgo, weekStart.month, weekStart.day);
    final end = start.add(const Duration(days: 6));
    // Round the coordinates so nearby users share the same cache entry.
    final latR = (lat * 10).round() / 10;
    final lonR = (lon * 10).round() / 10;
    final key = '$_spKeyPrefix${latR}_${lonR}_${_ymd(start)}';

    // Fast path: cached value.
    try {
      final sp = await SharedPreferences.getInstance();
      final cached = sp.getString(key);
      if (cached != null) {
        final map = jsonDecode(cached) as Map<String, dynamic>;
        return HistoricalWeekSummary.fromJson(map);
      }
    } catch (_) { /* ignore, refetch */ }

    // Open-Meteo Archive rejects future dates. If the requested slice is
    // still in the future (early January-vs-year edge case) skip it.
    if (start.isAfter(DateTime.now())) return null;

    try {
      final uri = Uri.parse(
        'https://archive-api.open-meteo.com/v1/archive'
        '?latitude=$lat&longitude=$lon'
        '&start_date=${_ymd(start)}&end_date=${_ymd(end)}'
        '&daily=temperature_2m_max,temperature_2m_min,precipitation_sum,wind_speed_10m_max'
        '&timezone=Europe/Berlin',
      );
      final r = await _client.get(uri).timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) {
        _log.debug('History fetch $yearsAgo years ago: HTTP ${r.statusCode}',
            tag: 'WEATHER_HISTORY');
        return null;
      }
      final data = jsonDecode(r.body);
      final daily = data['daily'] as Map<String, dynamic>?;
      if (daily == null) return null;

      final maxT = (daily['temperature_2m_max'] as List?)?.cast<num?>() ?? const [];
      final minT = (daily['temperature_2m_min'] as List?)?.cast<num?>() ?? const [];
      final prec = (daily['precipitation_sum'] as List?)?.cast<num?>() ?? const [];
      final wind = (daily['wind_speed_10m_max'] as List?)?.cast<num?>() ?? const [];

      final summary = HistoricalWeekSummary(
        yearsAgo: yearsAgo,
        start: start,
        end: end,
        avgTempMax: _avg(maxT),
        avgTempMin: _avg(minT),
        totalPrecipitation: _sum(prec),
        maxWindSpeed: _max(wind),
      );

      // Cache — data won't change, keep forever.
      try {
        final sp = await SharedPreferences.getInstance();
        await sp.setString(key, jsonEncode(summary.toJson()));
      } catch (_) { /* not fatal */ }

      return summary;
    } catch (e) {
      _log.debug('History fetch $yearsAgo years ago failed: $e', tag: 'WEATHER_HISTORY');
      return null;
    }
  }

  static String _ymd(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static double? _avg(List<num?> xs) {
    final vs = xs.whereType<num>().map((n) => n.toDouble()).toList();
    if (vs.isEmpty) return null;
    return vs.reduce((a, b) => a + b) / vs.length;
  }

  static double? _sum(List<num?> xs) {
    final vs = xs.whereType<num>().map((n) => n.toDouble()).toList();
    if (vs.isEmpty) return null;
    return vs.reduce((a, b) => a + b);
  }

  static double? _max(List<num?> xs) {
    final vs = xs.whereType<num>().map((n) => n.toDouble()).toList();
    if (vs.isEmpty) return null;
    return vs.reduce((a, b) => a > b ? a : b);
  }
}
