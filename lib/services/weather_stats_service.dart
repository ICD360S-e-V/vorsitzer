import 'dart:async';
import 'dart:convert';

import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'http_client_factory.dart';
import 'logger_service.dart';
import 'termin_service.dart';

final _log = LoggerService();

/// One classified past termin — what kind of weather it happened in and
/// whether the member showed up. Used to compute the summary buckets.
class TerminOutcome {
  final int terminId;
  final DateTime terminDate;
  final String feedbackStatus; // 'wahrgenommen' | 'nicht_wahrgenommen' | 'offen'
  final WeatherCategory category;

  const TerminOutcome({
    required this.terminId,
    required this.terminDate,
    required this.feedbackStatus,
    required this.category,
  });

  bool get wasNoShow => feedbackStatus == 'nicht_wahrgenommen';
  bool get wasAttended => feedbackStatus == 'wahrgenommen';
}

enum WeatherCategory { angenehm, regen, schnee, gewitter, kalt, hitze, wind, unbekannt }

extension WeatherCategoryX on WeatherCategory {
  String get label {
    switch (this) {
      case WeatherCategory.angenehm: return 'Angenehm';
      case WeatherCategory.regen:    return 'Regen';
      case WeatherCategory.schnee:   return 'Schnee';
      case WeatherCategory.gewitter: return 'Gewitter';
      case WeatherCategory.kalt:     return 'Kalt';
      case WeatherCategory.hitze:    return 'Hitze';
      case WeatherCategory.wind:     return 'Starker Wind';
      case WeatherCategory.unbekannt:return 'Unbekannt';
    }
  }

  String get emoji {
    switch (this) {
      case WeatherCategory.angenehm: return '☀️';
      case WeatherCategory.regen:    return '🌧️';
      case WeatherCategory.schnee:   return '🌨️';
      case WeatherCategory.gewitter: return '⛈️';
      case WeatherCategory.kalt:     return '🥶';
      case WeatherCategory.hitze:    return '🥵';
      case WeatherCategory.wind:     return '💨';
      case WeatherCategory.unbekannt:return '❓';
    }
  }
}

/// Aggregated statistics used by the UI card.
class WeatherStatsSummary {
  final int totalTermine;
  final int totalAttended;
  final int totalNoShow;
  final int totalOffen;
  final Map<WeatherCategory, int> countByCategory;
  final Map<WeatherCategory, int> noShowByCategory;
  final DateTime rangeStart;
  final DateTime rangeEnd;

  const WeatherStatsSummary({
    required this.totalTermine,
    required this.totalAttended,
    required this.totalNoShow,
    required this.totalOffen,
    required this.countByCategory,
    required this.noShowByCategory,
    required this.rangeStart,
    required this.rangeEnd,
  });

  bool get isEmpty => totalTermine == 0;

  int get noShowInBadWeather =>
      (noShowByCategory[WeatherCategory.regen] ?? 0) +
      (noShowByCategory[WeatherCategory.schnee] ?? 0) +
      (noShowByCategory[WeatherCategory.gewitter] ?? 0) +
      (noShowByCategory[WeatherCategory.kalt] ?? 0) +
      (noShowByCategory[WeatherCategory.hitze] ?? 0);

  int get badWeatherTermine =>
      (countByCategory[WeatherCategory.regen] ?? 0) +
      (countByCategory[WeatherCategory.schnee] ?? 0) +
      (countByCategory[WeatherCategory.gewitter] ?? 0) +
      (countByCategory[WeatherCategory.kalt] ?? 0) +
      (countByCategory[WeatherCategory.hitze] ?? 0);

  int? get badWeatherNoShowPct => badWeatherTermine == 0
      ? null
      : (noShowInBadWeather * 100 / badWeatherTermine).round();

  int? get goodWeatherNoShowPct {
    final good = countByCategory[WeatherCategory.angenehm] ?? 0;
    final goodNoShow = noShowByCategory[WeatherCategory.angenehm] ?? 0;
    if (good == 0) return null;
    return (goodNoShow * 100 / good).round();
  }
}

/// Correlates a member's past Termine with the actual weather that day
/// (Open-Meteo Archive API — free, no key). Everything is cached forever
/// because archive data doesn't change once it's out. Called from the
/// Mitglieder-Details-Dialog with `computeForUser(userId)`.
class WeatherStatsService {
  final _client = IOClient(HttpClientFactory.createDefaultHttpClient());
  final TerminService _terminService;

  static const _spKeyArchivePrefix = 'weather_stats_archive_v1_';
  static const _spKeyGeoPrefix = 'weather_stats_geo_v1_';

  WeatherStatsService(this._terminService);

  /// Load termini for [userId] over the last [days] days, geocode each unique
  /// location, hit the Archive API for the exact termin hour, and bucket the
  /// results into [WeatherStatsSummary]. Returns null when the underlying
  /// termine fetch fails (network / auth), so the UI can show a subtle error.
  Future<WeatherStatsSummary?> computeForUser(int userId, {int days = 90}) async {
    final now = DateTime.now();
    final rangeStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: days));
    final rangeEnd = DateTime(now.year, now.month, now.day, 23, 59);

    Map<String, dynamic> result;
    try {
      result = await _terminService.getAllTermine(
        from: rangeStart,
        to: rangeEnd,
        participantId: userId,
      );
    } catch (e) {
      _log.debug('WeatherStats: termini fetch failed: $e', tag: 'WEATHER_STATS');
      return null;
    }
    if (result['success'] != true) return null;
    final list = (result['termine'] as List?)?.cast<Map<String, dynamic>>() ?? const [];

    // Only care about past termini (not future) — the correlation is with
    // observed weather, not forecasted.
    final past = list.where((t) {
      final d = DateTime.tryParse(t['termin_date'] as String? ?? '');
      return d != null && d.isBefore(now) && d.isAfter(rangeStart);
    }).toList();

    final byCat = <WeatherCategory, int>{};
    final noShowByCat = <WeatherCategory, int>{};
    int attended = 0, noShow = 0, offen = 0;

    for (final t in past) {
      final terminDate = DateTime.parse(t['termin_date'] as String);
      final location = (t['location'] as String? ?? '').trim();
      final feedback = (t['feedback_status'] as String? ?? 'offen');

      WeatherCategory cat = WeatherCategory.unbekannt;
      if (location.isNotEmpty) {
        final coords = await _geocode(location);
        if (coords != null) {
          cat = await _fetchWeatherCategory(coords.$1, coords.$2, terminDate);
        }
      }

      byCat.update(cat, (v) => v + 1, ifAbsent: () => 1);
      if (feedback == 'wahrgenommen') attended++;
      if (feedback == 'nicht_wahrgenommen') {
        noShow++;
        noShowByCat.update(cat, (v) => v + 1, ifAbsent: () => 1);
      }
      if (feedback == 'offen') offen++;
    }

    return WeatherStatsSummary(
      totalTermine: past.length,
      totalAttended: attended,
      totalNoShow: noShow,
      totalOffen: offen,
      countByCategory: byCat,
      noShowByCategory: noShowByCat,
      rangeStart: rangeStart,
      rangeEnd: rangeEnd,
    );
  }

  /// Same 3-tier geocoding chain we use in TerminWeatherService, kept private
  /// here so we don't cross-couple caches — this service's SP-key namespace
  /// is separate so an ad-hoc cache-wipe of one doesn't nuke the other.
  Future<(double, double)?> _geocode(String location) async {
    final sp = await SharedPreferences.getInstance();
    final key = '$_spKeyGeoPrefix$location';
    final cached = sp.getString(key);
    if (cached != null) {
      final parts = cached.split(',');
      if (parts.length == 2) {
        final lat = double.tryParse(parts[0]);
        final lon = double.tryParse(parts[1]);
        if (lat != null && lon != null) return (lat, lon);
      }
    }
    // Try Nominatim first — best hit rate for German street addresses.
    try {
      final r = await _client
          .get(
            Uri.parse('https://nominatim.openstreetmap.org/search'
                '?q=${Uri.encodeComponent(location)}&format=json&limit=1'
                '&accept-language=de&countrycodes=de,at,ch'),
            headers: {'User-Agent': 'ICD360S-Vorsitzer-App/1.0 (contact@icd360s.de)'},
          )
          .timeout(const Duration(seconds: 10));
      if (r.statusCode == 200) {
        final list = jsonDecode(r.body) as List;
        if (list.isNotEmpty) {
          final lat = double.tryParse(list[0]['lat'].toString());
          final lon = double.tryParse(list[0]['lon'].toString());
          if (lat != null && lon != null) {
            await sp.setString(key, '$lat,$lon');
            return (lat, lon);
          }
        }
      }
    } catch (_) { /* fall through */ }
    // Fallback: extract PLZ + Stadt.
    final m = RegExp(r'\b(\d{5})\s+([A-Za-zÄÖÜäöüß][\wÄÖÜäöüß.\-]*(?:\s+[A-Za-zÄÖÜäöüß][\wÄÖÜäöüß.\-]*){0,2})')
        .firstMatch(location);
    if (m != null) {
      final query = '${m.group(1)} ${m.group(2)}';
      try {
        final r = await _client
            .get(Uri.parse('https://geocoding-api.open-meteo.com/v1/search'
                '?name=${Uri.encodeComponent(query)}&count=1&language=de&format=json'))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final data = jsonDecode(r.body);
          final results = data['results'] as List?;
          if (results != null && results.isNotEmpty) {
            final lat = (results[0]['latitude'] as num).toDouble();
            final lon = (results[0]['longitude'] as num).toDouble();
            await sp.setString(key, '$lat,$lon');
            return (lat, lon);
          }
        }
      } catch (_) { /* give up */ }
    }
    return null;
  }

  Future<WeatherCategory> _fetchWeatherCategory(
      double lat, double lon, DateTime terminDate) async {
    final sp = await SharedPreferences.getInstance();
    // Round lat/lon to ~10 km grid so nearby termini share cache entries.
    final latR = (lat * 10).round() / 10;
    final lonR = (lon * 10).round() / 10;
    final day = DateTime(terminDate.year, terminDate.month, terminDate.day);
    final ymd = '${day.year}-${day.month.toString().padLeft(2, '0')}-'
        '${day.day.toString().padLeft(2, '0')}';
    final key = '$_spKeyArchivePrefix${latR}_${lonR}_${ymd}_${terminDate.hour}';
    final cached = sp.getString(key);
    if (cached != null) {
      return WeatherCategory.values.firstWhere(
        (c) => c.name == cached,
        orElse: () => WeatherCategory.unbekannt,
      );
    }

    try {
      final r = await _client
          .get(Uri.parse('https://archive-api.open-meteo.com/v1/archive'
              '?latitude=$lat&longitude=$lon&start_date=$ymd&end_date=$ymd'
              '&hourly=weather_code,temperature_2m,precipitation,wind_speed_10m'
              '&timezone=Europe/Berlin'))
          .timeout(const Duration(seconds: 12));
      if (r.statusCode != 200) return WeatherCategory.unbekannt;
      final data = jsonDecode(r.body);
      final hourly = data['hourly'];
      if (hourly == null) return WeatherCategory.unbekannt;
      final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
      final wanted = '$ymd'
          'T${terminDate.hour.toString().padLeft(2, '0')}:00';
      final idx = times.indexOf(wanted);
      if (idx < 0) return WeatherCategory.unbekannt;

      final code = (hourly['weather_code']?[idx] as num?)?.toInt() ?? -1;
      final temp = (hourly['temperature_2m']?[idx] as num?)?.toDouble() ?? 0;
      final precip = (hourly['precipitation']?[idx] as num?)?.toDouble() ?? 0;
      final wind = (hourly['wind_speed_10m']?[idx] as num?)?.toDouble() ?? 0;

      final cat = _classify(code, temp, precip, wind);
      await sp.setString(key, cat.name);
      return cat;
    } catch (e) {
      _log.debug('WeatherStats: archive fetch failed for $ymd: $e', tag: 'WEATHER_STATS');
      return WeatherCategory.unbekannt;
    }
  }

  /// Bucketing: severe weather wins over generic categories so the numbers
  /// mean something (a stormy 4 °C day is Gewitter, not Kalt).
  WeatherCategory _classify(int code, double temp, double precip, double wind) {
    if (code >= 95 && code <= 99) return WeatherCategory.gewitter;
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return WeatherCategory.schnee;
    if (wind >= 50) return WeatherCategory.wind;
    if (temp <= 0) return WeatherCategory.kalt;
    if (temp >= 28) return WeatherCategory.hitze;
    if (precip >= 1 || (code >= 51 && code <= 82)) return WeatherCategory.regen;
    return WeatherCategory.angenehm;
  }
}
