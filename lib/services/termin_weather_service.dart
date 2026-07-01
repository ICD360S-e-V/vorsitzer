import 'dart:async';
import 'dart:convert';
import 'package:http/io_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';
import 'termin_service.dart';

final _log = LoggerService();

/// Kind of weather condition. `normal` means no threshold crossed —
/// there is still a hint, just without a warning styling.
enum TerminWeatherKind { normal, rain, snow, thunder, cold, hot, wind, storm }

/// Weather info attached to a single Termin. Emitted for _every_ Termin whose
/// location can be geocoded (so the user always sees "how will the appointment
/// be?"). Warnings are just a subset — [hasWarning] flips true only when a
/// threshold is crossed and the concrete recommendation is worth surfacing.
class TerminWeatherHint {
  final int terminId;
  final TerminWeatherKind kind;
  final bool hasWarning;
  final String emoji;
  final String title;      // "Regen morgen 09:00" or "Sonnig · Mo 09:00"
  final String subtitle;   // "15°C · gefühlt 13°C · 20 km/h"
  final String recommendation; // empty for normal weather
  final DateTime forecastFor;  // rounded to the top of the hour
  final DateTime computedAt;
  final int precipitationProbability;
  final double temperature;
  final double apparentTemperature;
  final double windSpeed;
  final int weatherCode;

  TerminWeatherHint({
    required this.terminId,
    required this.kind,
    required this.hasWarning,
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.recommendation,
    required this.forecastFor,
    required this.computedAt,
    required this.precipitationProbability,
    required this.temperature,
    required this.apparentTemperature,
    required this.windSpeed,
    required this.weatherCode,
  });
}

/// Attaches weather-aware advisories to Termine.
///
/// - Geocodes each Termin's `location` text via Open-Meteo geocoding (cached
///   permanently in SharedPreferences — free API, no key).
/// - Fetches hourly Open-Meteo forecast for the target hour (cached in-memory
///   for 1 hour, keyed by ~10 km grid so several Termine at similar locations
///   share one API call).
/// - Evaluates a fixed threshold table; emits a [TerminWeatherHint] only when
///   the weather is worth warning about.
/// - Skips locations that clearly aren't outdoor (Zoom / online / intern /
///   Vereinshaus / eigene Praxis etc.).
/// - Sends a local push exactly once per Termin, roughly 12 h before it starts.
///   Dedup is persisted in SharedPreferences so the notification survives app
///   restarts and calendar re-loads.
class TerminWeatherService {
  final _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  // In-memory forecast cache: key = "$latR,$lonR,$isoHour", value = payload map.
  final Map<String, _CachedForecast> _forecastCache = {};

  // Advisories the UI can render, keyed by termin.id.
  final Map<int, TerminWeatherHint> _hints = {};

  // Per-Termin state so we don't re-notify or re-work Termine that clearly qualify.
  static const _spKeyNotifiedPrefix = 'termin_weather_notified_';
  static const _spKeyGeocodePrefix = 'termin_weather_geocode_';

  /// Heuristics for "not outdoor" locations — skip forecast entirely.
  static final _internKeywords = RegExp(
    r'\b(intern|online|zoom|teams|videokonferenz|telefonat|telefon|homeoffice|'
    r'zuhause|home|vereinshaus|vereinsheim|büro|buero|eigene\s*praxis|remote)\b',
    caseSensitive: false,
  );

  Map<int, TerminWeatherHint> get hints => Map.unmodifiable(_hints);
  TerminWeatherHint? hintFor(int terminId) => _hints[terminId];

  /// Evaluate a batch of Termine. Runs geocoding/forecast in parallel per
  /// unique location, then produces hints for those crossing thresholds and
  /// fires notifications for anything within the next ~12 h that hasn't
  /// already been notified this cycle.
  Future<void> refreshForTermine(List<Termin> termine) async {
    final now = DateTime.now();
    _hints.clear();

    // Consider Termine from now up to 7 days out. Anything past is skipped;
    // anything further out has enough time to re-refresh closer to the day.
    final horizon = now.add(const Duration(days: 7));
    final candidates = termine.where((t) {
      if (t.terminDate.isBefore(now.subtract(const Duration(minutes: 30)))) return false;
      if (t.terminDate.isAfter(horizon)) return false;
      if (t.status == 'cancelled') return false;
      if (_looksIndoor(t.location)) return false;
      return true;
    }).toList();

    if (candidates.isEmpty) return;

    // Group by location so we geocode + forecast once per unique address.
    final byLocation = <String, List<Termin>>{};
    for (final t in candidates) {
      byLocation.putIfAbsent(t.location.trim(), () => []).add(t);
    }

    for (final entry in byLocation.entries) {
      final loc = entry.key;
      final ts = entry.value;
      try {
        final coords = await _geocode(loc);
        if (coords == null) continue;
        for (final termin in ts) {
          final hint = await _hintForTermin(termin, coords.$1, coords.$2);
          if (hint != null) {
            _hints[termin.id] = hint;
            await _maybeNotify(termin, hint);
          }
        }
      } catch (e) {
        _log.debug('TerminWeather: skipped "$loc" — $e', tag: 'TERMIN_WEATHER');
      }
    }

    _log.info(
      'TerminWeather: evaluated ${candidates.length} Termine, '
      '${_hints.length} with weather hint',
      tag: 'TERMIN_WEATHER',
    );
  }

  bool _looksIndoor(String location) {
    if (location.trim().isEmpty) return true;
    return _internKeywords.hasMatch(location);
  }

  /// Round coordinates to ~10 km grid so nearby Termine share one forecast call.
  String _gridKey(double lat, double lon, DateTime hourUtc) {
    final latR = (lat * 10).round() / 10;
    final lonR = (lon * 10).round() / 10;
    return '$latR,$lonR,${hourUtc.toIso8601String()}';
  }

  Future<(double, double)?> _geocode(String location) async {
    final sp = await SharedPreferences.getInstance();
    final cached = sp.getString('$_spKeyGeocodePrefix$location');
    if (cached != null) {
      final parts = cached.split(',');
      if (parts.length == 2) {
        return (double.parse(parts[0]), double.parse(parts[1]));
      }
    }
    // Query the Open-Meteo geocoder; strip the house number / trailing details
    // and try just the first token if the full string returns nothing.
    for (final q in [location, location.split(',').first, location.split(' ').first]) {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search'
        '?name=${Uri.encodeComponent(q)}&count=1&language=de&format=json',
      );
      final r = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) continue;
      final data = jsonDecode(r.body);
      final results = data['results'] as List?;
      if (results == null || results.isEmpty) continue;
      final lat = (results[0]['latitude'] as num).toDouble();
      final lon = (results[0]['longitude'] as num).toDouble();
      await sp.setString('$_spKeyGeocodePrefix$location', '$lat,$lon');
      return (lat, lon);
    }
    return null;
  }

  Future<TerminWeatherHint?> _hintForTermin(Termin termin, double lat, double lon) async {
    // Snap to the top of the Termin's hour — that's what Open-Meteo hourly returns.
    final hour = DateTime(
      termin.terminDate.year,
      termin.terminDate.month,
      termin.terminDate.day,
      termin.terminDate.hour,
    );
    final forecast = await _forecastFor(lat, lon, hour);
    if (forecast == null) return null;

    final code = (forecast['weather_code'] as num).toInt();
    final temp = (forecast['temperature_2m'] as num).toDouble();
    final apparent = (forecast['apparent_temperature'] as num?)?.toDouble() ?? temp;
    final wind = (forecast['wind_speed_10m'] as num?)?.toDouble() ?? 0;
    final precip = (forecast['precipitation'] as num?)?.toDouble() ?? 0;
    final precipProb = (forecast['precipitation_probability'] as num?)?.toInt() ?? 0;

    final kind = _classify(code, temp, apparent, wind, precip, precipProb);
    final hasWarning = kind != null;
    // Even without a warning, we still produce a hint so every Termin shows
    // its forecast — that's what the calendar badge represents.
    final rendered = hasWarning
        ? _renderKind(kind, temp, apparent, wind, precipProb)
        : _renderNormal(code, temp);

    return TerminWeatherHint(
      terminId: termin.id,
      kind: kind ?? TerminWeatherKind.normal,
      hasWarning: hasWarning,
      emoji: rendered.$1,
      title: '${rendered.$2} · ${_formatDayHour(termin.terminDate)}',
      subtitle: '${temp.toStringAsFixed(0)}°C · '
          'gefühlt ${apparent.toStringAsFixed(0)}°C · '
          '${wind.toStringAsFixed(0)} km/h Wind'
          '${precipProb > 0 ? " · $precipProb%" : ""}',
      recommendation: rendered.$3,
      forecastFor: hour,
      computedAt: DateTime.now(),
      precipitationProbability: precipProb,
      temperature: temp,
      apparentTemperature: apparent,
      windSpeed: wind,
      weatherCode: code,
    );
  }

  /// Non-warning renderer — pick the plain WMO emoji + a short descriptor.
  /// Returns (emoji, headline, "") so calendar badges always have something
  /// friendly to show even when the weather is fine.
  (String, String, String) _renderNormal(int code, double temp) {
    String emoji;
    String label;
    if (code == 0) { emoji = '☀️'; label = 'Sonnig'; }
    else if (code <= 3) { emoji = '⛅'; label = 'Teils bewölkt'; }
    else if (code <= 48) { emoji = '🌫️'; label = 'Nebel'; }
    else if (code >= 95) { emoji = '⛈️'; label = 'Gewitter'; }
    else if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) {
      emoji = '🌨️'; label = 'Schnee';
    }
    else if ((code >= 51 && code <= 67) || (code >= 80 && code <= 82)) {
      emoji = '🌧️'; label = 'Regen';
    }
    else { emoji = '☁️'; label = 'Bewölkt'; }
    return (emoji, '$label · ${temp.toStringAsFixed(0)}°C', '');
  }

  TerminWeatherKind? _classify(int code, double temp, double apparent, double wind,
      double precip, int precipProb) {
    // Order matters — thunder outranks generic rain, storm outranks generic wind.
    if (code >= 95 && code <= 99) return TerminWeatherKind.thunder;
    if (wind >= 60) return TerminWeatherKind.storm;
    if ((code >= 71 && code <= 77) || (code >= 85 && code <= 86)) return TerminWeatherKind.snow;
    if (precipProb >= 70 || precip >= 2) return TerminWeatherKind.rain;
    if (temp <= 0) return TerminWeatherKind.cold;
    if (apparent >= 32) return TerminWeatherKind.hot;
    if (wind >= 40) return TerminWeatherKind.wind;
    return null;
  }

  /// Returns (emoji, headline, recommendation) for the classified kind.
  (String, String, String) _renderKind(
      TerminWeatherKind kind, double temp, double apparent, double wind, int precipProb) {
    switch (kind) {
      case TerminWeatherKind.normal:
        return _renderNormal(0, temp); // shouldn't happen — normal goes through _renderNormal
      case TerminWeatherKind.thunder:
        return ('⛈️', 'Gewitter', 'Möglichst nicht draußen bleiben. '
            'DWD-Warnungen beachten, ggf. Termin verschieben.');
      case TerminWeatherKind.storm:
        return ('💨', 'Sturm (${wind.toStringAsFixed(0)} km/h)',
            'Achtung bei Regenschirmen, herabfallenden Ästen. '
            'Extra Zeit einplanen.');
      case TerminWeatherKind.snow:
        return ('🌨️', 'Schneefall', 'Winterschuhe mit Profil, extra Zeit für '
            'Anreise. Auf Glätte achten — besonders auf Wegen zu Behörden.');
      case TerminWeatherKind.rain:
        final prob = precipProb > 0 ? ' ($precipProb %)' : '';
        return ('☔', 'Regen$prob',
            'Regenschirm + wasserdichte Schuhe mitnehmen. '
            '10–15 Min früher losfahren.');
      case TerminWeatherKind.cold:
        return ('🥶', 'Kalt (${temp.toStringAsFixed(0)}°C)',
            'Warm anziehen (Schichten), Kopf/Hände schützen. '
            'Rutschgefahr bei Frost.');
      case TerminWeatherKind.hot:
        return ('🥵', 'Hitze (gefühlt ${apparent.toStringAsFixed(0)}°C)',
            'Wasser mitnehmen, leichte Kleidung, ggf. Sonnenschutz. '
            'Wartezeiten im Schatten oder drinnen verbringen.');
      case TerminWeatherKind.wind:
        return ('💨', 'Windig (${wind.toStringAsFixed(0)} km/h)',
            'Leichtes Gepäck sichern, Regenschirm sturmfest.');
    }
  }

  Future<Map<String, dynamic>?> _forecastFor(double lat, double lon, DateTime hour) async {
    final utc = hour.toUtc();
    final key = _gridKey(lat, lon, utc);
    final cached = _forecastCache[key];
    if (cached != null && DateTime.now().difference(cached.at) < const Duration(hours: 1)) {
      return cached.data;
    }
    // Ask Open-Meteo for exactly the day of the hour we care about, then
    // pick out the matching timestamp from the returned array.
    final day = DateTime(hour.year, hour.month, hour.day);
    final dayStr = '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    final uri = Uri.parse(
      'https://api.open-meteo.com/v1/forecast'
      '?latitude=$lat&longitude=$lon'
      '&hourly=temperature_2m,apparent_temperature,weather_code,'
      'wind_speed_10m,precipitation,precipitation_probability'
      '&timezone=Europe/Berlin'
      '&start_date=$dayStr&end_date=$dayStr',
    );
    final r = await _client.get(uri).timeout(const Duration(seconds: 12));
    if (r.statusCode != 200) return null;
    final data = jsonDecode(r.body);
    final hourly = data['hourly'];
    if (hourly == null) return null;
    final times = (hourly['time'] as List).cast<String>();

    // Open-Meteo returns hourly times in "Europe/Berlin" — build a matching key.
    final wanted = '${hour.year}-${hour.month.toString().padLeft(2, '0')}-'
        '${hour.day.toString().padLeft(2, '0')}T${hour.hour.toString().padLeft(2, '0')}:00';
    final idx = times.indexOf(wanted);
    if (idx < 0) return null;

    final payload = <String, dynamic>{
      'weather_code': hourly['weather_code'][idx],
      'temperature_2m': hourly['temperature_2m'][idx],
      'apparent_temperature': hourly['apparent_temperature'][idx],
      'wind_speed_10m': hourly['wind_speed_10m'][idx],
      'precipitation': hourly['precipitation'][idx],
      'precipitation_probability': hourly['precipitation_probability']?[idx],
    };
    _forecastCache[key] = _CachedForecast(payload, DateTime.now());
    return payload;
  }

  /// Fire a local push if the Termin is within the next ~12 h and we haven't
  /// already fired one. Dedup key includes the day so the same Termin id can
  /// be notified again if it's rescheduled to a different day.
  Future<void> _maybeNotify(Termin termin, TerminWeatherHint hint) async {
    if (!hint.hasWarning) return; // don't spam pushes for fine weather
    final until = termin.terminDate.difference(DateTime.now());
    if (until.isNegative || until > const Duration(hours: 12)) return;

    final sp = await SharedPreferences.getInstance();
    final ymd = '${termin.terminDate.year}-${termin.terminDate.month}-${termin.terminDate.day}';
    final dedupKey = '$_spKeyNotifiedPrefix${termin.id}_$ymd';
    if (sp.getBool(dedupKey) == true) return;

    await NotificationService().show(
      title: '${hint.emoji} ${hint.title.split(" · ").first} · ${_formatTime(termin.terminDate)} '
          '${termin.title}',
      body: '${hint.subtitle}\n${hint.recommendation}',
      payload: 'termin:${termin.id}',
    );
    await sp.setBool(dedupKey, true);
    _log.info(
      'TerminWeather: notified termin ${termin.id} (${termin.title}) — ${hint.kind.name}',
      tag: 'TERMIN_WEATHER',
    );
  }

  String _formatDayHour(DateTime d) {
    const days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    return '${days[(d.weekday - 1) % 7]} ${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')} '
        '${_formatTime(d)}';
  }

  String _formatTime(DateTime d) =>
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

class _CachedForecast {
  final Map<String, dynamic> data;
  final DateTime at;
  _CachedForecast(this.data, this.at);
}
