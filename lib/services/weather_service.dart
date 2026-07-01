import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:geolocator/geolocator.dart';
import 'package:http/io_client.dart';
import 'notification_service.dart';
import 'logger_service.dart';
import 'http_client_factory.dart';

final _log = LoggerService();

/// WMO Weather Code descriptions (German)
class WeatherCode {
  static const Map<int, String> descriptions = {
    0: 'Klar',
    1: 'Überwiegend klar',
    2: 'Teilweise bewölkt',
    3: 'Bewölkt',
    45: 'Nebel',
    48: 'Nebel mit Reif',
    51: 'Leichter Nieselregen',
    53: 'Nieselregen',
    55: 'Starker Nieselregen',
    56: 'Gefrierender Nieselregen',
    57: 'Starker gefrierender Nieselregen',
    61: 'Leichter Regen',
    63: 'Regen',
    65: 'Starker Regen',
    66: 'Gefrierender Regen',
    67: 'Starker gefrierender Regen',
    71: 'Leichter Schneefall',
    73: 'Schneefall',
    75: 'Starker Schneefall',
    77: 'Schneegriesel',
    80: 'Leichte Regenschauer',
    81: 'Regenschauer',
    82: 'Starke Regenschauer',
    85: 'Leichte Schneeschauer',
    86: 'Starke Schneeschauer',
    95: 'Gewitter',
    96: 'Gewitter mit Hagel',
    99: 'Starkes Gewitter mit Hagel',
  };

  static String describe(int code) => descriptions[code] ?? 'Unbekannt';

  static bool isRain(int code) => (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
  static bool isSnow(int code) => (code >= 71 && code <= 77) || (code >= 85 && code <= 86);
  static bool isThunder(int code) => code >= 95 && code <= 99;
  static bool isSevere(int code) => code >= 65 || isThunder(code);

  static String icon(int code) {
    if (code == 0) return '☀️';
    if (code <= 3) return '⛅';
    if (code <= 48) return '🌫️';
    if (isThunder(code)) return '⛈️';
    if (isSnow(code)) return '🌨️';
    if (isRain(code)) return '🌧️';
    return '☁️';
  }
}

/// Current weather data
class WeatherData {
  final double temperature;
  final double apparentTemperature;
  final int weatherCode;
  final double windSpeed;
  final double windDirection;
  final int humidity;
  final double precipitation;
  final double pressureMsl;
  final double? uvIndex;
  final int? cloudCover;
  final bool isDay;
  final String city;
  final DateTime timestamp;

  WeatherData({
    required this.temperature,
    required this.apparentTemperature,
    required this.weatherCode,
    required this.windSpeed,
    required this.windDirection,
    required this.humidity,
    required this.precipitation,
    required this.pressureMsl,
    this.uvIndex,
    this.cloudCover,
    required this.isDay,
    required this.city,
    required this.timestamp,
  });

  String get description => WeatherCode.describe(weatherCode);
  String get icon => WeatherCode.icon(weatherCode);
  bool get isRain => WeatherCode.isRain(weatherCode);
  bool get isSnow => WeatherCode.isSnow(weatherCode);
  bool get isThunder => WeatherCode.isThunder(weatherCode);

  /// Compass direction from windDirection degrees (0=N, 90=E, 180=S, 270=W)
  String get windCompass {
    const dirs = ['N', 'NO', 'O', 'SO', 'S', 'SW', 'W', 'NW'];
    return dirs[((windDirection % 360) / 45).round() % 8];
  }
}

/// Hourly forecast entry
class HourlyForecast {
  final DateTime time;
  final double temperature;
  final int weatherCode;
  final double windSpeed;
  final int humidity;
  final double precipitation;
  final int? precipitationProbability;

  HourlyForecast({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.windSpeed,
    required this.humidity,
    required this.precipitation,
    this.precipitationProbability,
  });

  String get icon => WeatherCode.icon(weatherCode);
  String get description => WeatherCode.describe(weatherCode);
}

/// 15-minute nowcast entry (Open-Meteo minutely_15) — used for the header timeline bar.
class MinutelyForecast {
  final DateTime time;
  final double temperature;
  final int weatherCode;
  final double precipitation;
  final int? precipitationProbability;
  final double windSpeed;

  MinutelyForecast({
    required this.time,
    required this.temperature,
    required this.weatherCode,
    required this.precipitation,
    this.precipitationProbability,
    required this.windSpeed,
  });

  String get icon => WeatherCode.icon(weatherCode);
  String get description => WeatherCode.describe(weatherCode);
}

/// Daily forecast entry
class DailyForecast {
  final DateTime date;
  final double tempMax;
  final double tempMin;
  final int weatherCode;
  final double precipitationSum;
  final double windSpeedMax;

  DailyForecast({
    required this.date,
    required this.tempMax,
    required this.tempMin,
    required this.weatherCode,
    required this.precipitationSum,
    required this.windSpeedMax,
  });

  String get icon => WeatherCode.icon(weatherCode);
  String get description => WeatherCode.describe(weatherCode);
}

/// DWD Weather Alert
class WeatherAlert {
  final String headline;
  final String description;
  final String severity; // minor, moderate, severe, extreme
  final String event;
  final String? instruction;
  final DateTime? onset;
  final DateTime? expires;

  WeatherAlert({
    required this.headline,
    required this.description,
    required this.severity,
    required this.event,
    this.instruction,
    this.onset,
    this.expires,
  });

  /// Show alerts that haven't expired yet (including upcoming ones)
  bool get isRelevant {
    final now = DateTime.now();
    if (expires != null && now.isAfter(expires!)) return false;
    return true;
  }

  String get severityLabel {
    switch (severity) {
      case 'extreme':
        return 'Extrem';
      case 'severe':
        return 'Schwer';
      case 'moderate':
        return 'Mäßig';
      default:
        return 'Leicht';
    }
  }
}

/// Snapshot of air-quality + pollen data (Open-Meteo air-quality API, free, CAMS).
///
/// Levels follow the German UBA / European classification where practical.
class AirQualityData {
  final double? pm25;             // µg/m³
  final double? pm10;             // µg/m³
  final double? ozone;            // µg/m³
  final double? nitrogenDioxide;  // µg/m³
  final double? sulphurDioxide;   // µg/m³
  final double? carbonMonoxide;   // µg/m³
  final double? europeanAqi;      // 0-100 index
  final double? uvIndex;
  // Pollen (grains/m³ average) — null when out of season or not covered by CAMS.
  final double? alderPollen;
  final double? birchPollen;
  final double? grassPollen;
  final double? mugwortPollen;
  final double? olivePollen;
  final double? ragweedPollen;
  final DateTime timestamp;

  AirQualityData({
    this.pm25,
    this.pm10,
    this.ozone,
    this.nitrogenDioxide,
    this.sulphurDioxide,
    this.carbonMonoxide,
    this.europeanAqi,
    this.uvIndex,
    this.alderPollen,
    this.birchPollen,
    this.grassPollen,
    this.mugwortPollen,
    this.olivePollen,
    this.ragweedPollen,
    required this.timestamp,
  });

  /// Coarse label for the European AQI (UBA/EEA scale).
  String get aqiLabel {
    final v = europeanAqi;
    if (v == null) return 'unbekannt';
    if (v <= 20) return 'sehr gut';
    if (v <= 40) return 'gut';
    if (v <= 60) return 'mäßig';
    if (v <= 80) return 'schlecht';
    return 'sehr schlecht';
  }

  /// Any pollen count above ~10 grains/m³ is typically noticeable for allergics.
  bool get pollenActive =>
      (alderPollen ?? 0) > 10 ||
      (birchPollen ?? 0) > 10 ||
      (grassPollen ?? 0) > 10 ||
      (mugwortPollen ?? 0) > 10 ||
      (ragweedPollen ?? 0) > 10;
}

/// Sun times + moon phase for the header. Sunrise/sunset come from Open-Meteo daily;
/// the moon phase is computed locally from a known new-moon epoch (no extra API).
class AstronomyData {
  final DateTime? sunrise;
  final DateTime? sunset;
  final Duration? daylight;
  final double moonAgeDays; // 0..29.53
  final int moonPhaseIndex; // 0=new, 1=waxing crescent, ..., 7=waning crescent
  final String moonPhaseLabel;
  final String moonEmoji;
  final int moonIlluminationPercent;

  AstronomyData({
    this.sunrise,
    this.sunset,
    this.daylight,
    required this.moonAgeDays,
    required this.moonPhaseIndex,
    required this.moonPhaseLabel,
    required this.moonEmoji,
    required this.moonIlluminationPercent,
  });

  /// Compute lunar phase from a UTC date.
  ///
  /// Uses a well-known reference new moon (2000-01-06 18:14 UT, "Meeus / synodic
  /// month" approximation). Precision is ±a few hours over a decade — more than
  /// enough for a UI label.
  static AstronomyData forDate(DateTime day, {DateTime? sunrise, DateTime? sunset}) {
    final reference = DateTime.utc(2000, 1, 6, 18, 14);
    const synodic = 29.530588853;
    final diffDays = day.toUtc().difference(reference).inSeconds / 86400.0;
    double age = diffDays % synodic;
    if (age < 0) age += synodic;

    // 8-phase classification — matches the icons every German weather app uses.
    const labels = [
      ('Neumond', '🌑'),
      ('zunehmender Sichel', '🌒'),
      ('erstes Viertel', '🌓'),
      ('zunehmender Mond', '🌔'),
      ('Vollmond', '🌕'),
      ('abnehmender Mond', '🌖'),
      ('letztes Viertel', '🌗'),
      ('abnehmende Sichel', '🌘'),
    ];
    // Phase 0 is centred on age=0 (new moon), phase 4 on age=synodic/2 (full moon).
    final rawIndex = (age / synodic * 8).round() % 8;

    // Illumination (%): cosine of the phase angle mapped to 0..100.
    final phaseAngle = 2 * math.pi * age / synodic;
    final illum = ((1 - math.cos(phaseAngle)) / 2 * 100).round();

    Duration? daylight;
    if (sunrise != null && sunset != null && sunset.isAfter(sunrise)) {
      daylight = sunset.difference(sunrise);
    }

    return AstronomyData(
      sunrise: sunrise,
      sunset: sunset,
      daylight: daylight,
      moonAgeDays: age,
      moonPhaseIndex: rawIndex,
      moonPhaseLabel: labels[rawIndex].$1,
      moonEmoji: labels[rawIndex].$2,
      moonIlluminationPercent: illum,
    );
  }
}

/// Weather service using Open-Meteo (free, no API key) + Bright Sky (DWD alerts)
class WeatherService {
  Timer? _weatherTimer;
  Timer? _alertTimer;
  StreamSubscription<Position>? _gpsSubscription;
  DateTime? _lastGpsRefreshAt;
  double? _latitude;
  double? _longitude;
  double? _lastGeocodedLat;
  double? _lastGeocodedLon;
  String _city = '';
  bool _gpsRefreshEnabled = false;

  WeatherData? currentWeather;
  AirQualityData? currentAirQuality;
  AstronomyData? currentAstronomy;
  List<WeatherAlert> currentAlerts = [];
  List<MinutelyForecast> minutelyForecast = [];
  List<HourlyForecast> hourlyForecast = [];
  List<DailyForecast> dailyForecast = [];

  Timer? _airQualityTimer;

  // Track last notified conditions to avoid spam
  int? _lastNotifiedWeatherCode;
  bool _lastNotifiedStrongWind = false;
  Set<String> _lastNotifiedAlertHeadlines = {};

  // Callbacks
  void Function(WeatherData)? onWeatherUpdate;
  void Function(List<WeatherAlert>)? onAlertsUpdate;
  void Function(AirQualityData)? onAirQualityUpdate;

  final _client = IOClient(HttpClientFactory.createDefaultHttpClient());

  /// Start weather monitoring — accepts optional GPS coordinates.
  /// When [followGps] is true, the service re-reads the device GPS every 15 minutes
  /// and updates the location (with reverse-geocoded city name) if the user moved.
  Future<void> start(String city, {double? lat, double? lon, bool followGps = false}) async {
    _city = city;
    _gpsRefreshEnabled = followGps;

    if (lat != null && lon != null) {
      _latitude = lat;
      _longitude = lon;
      _lastGeocodedLat = lat;
      _lastGeocodedLon = lon;
      _log.info('Weather: Starting with GPS ($_latitude, $_longitude)', tag: 'WEATHER');
    } else if (city.isNotEmpty) {
      _log.info('Weather: Starting for city "$city"', tag: 'WEATHER');
      final success = await _geocodeCity(city);
      if (!success) {
        _log.error('Weather: Could not geocode "$city"', tag: 'WEATHER');
        return;
      }
      _lastGeocodedLat = _latitude;
      _lastGeocodedLon = _longitude;
    } else {
      _log.info('Weather: No location provided, skipping', tag: 'WEATHER');
      return;
    }

    // Initial fetch
    await _fetchWeather();
    await _fetchAlerts();
    await _fetchAirQuality();

    // Weather every 5 minutes: Bright Sky DWD observations refresh ~10 min server-side,
    // Open-Meteo current ~15 min; 5-min polling picks up updates as soon as they land.
    _weatherTimer = Timer.periodic(const Duration(minutes: 5), (_) => _fetchWeather());

    // Alerts every 15 minutes
    _alertTimer = Timer.periodic(const Duration(minutes: 15), (_) => _fetchAlerts());

    // Air quality every 30 minutes — CAMS updates hourly, no need to poll faster.
    _airQualityTimer = Timer.periodic(const Duration(minutes: 30), (_) => _fetchAirQuality());

    // Optional GPS follow: event-driven (only fires when device actually moves ≥1m).
    // Battery-friendly: idle phones never trigger the callback.
    if (followGps) {
      _startGpsStream();
    }
  }

  void stop() {
    _weatherTimer?.cancel();
    _alertTimer?.cancel();
    _airQualityTimer?.cancel();
    _gpsSubscription?.cancel();
    _weatherTimer = null;
    _alertTimer = null;
    _airQualityTimer = null;
    _gpsSubscription = null;
    _lastNotifiedWeatherCode = null;
    _lastNotifiedStrongWind = false;
    _lastNotifiedAlertHeadlines = {};
    _log.info('Weather: Stopped', tag: 'WEATHER');
  }

  /// Enable/disable GPS follow after start().
  void setFollowGps(bool enabled) {
    if (_gpsRefreshEnabled == enabled) return;
    _gpsRefreshEnabled = enabled;
    if (enabled && _gpsSubscription == null) {
      _startGpsStream();
    } else if (!enabled) {
      _gpsSubscription?.cancel();
      _gpsSubscription = null;
      _log.info('Weather: GPS follow disabled', tag: 'WEATHER');
    }
  }

  /// Start the platform location stream. distanceFilter=1 means we only get callbacks
  /// when the device moves ≥1m — so a phone sitting on a desk produces zero events
  /// (no polling, no battery drain). When it moves, we throttle to at most one weather
  /// refresh per 15 min to respect API limits.
  void _startGpsStream() {
    try {
      _gpsSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          distanceFilter: 1, // meters
        ),
      ).listen(
        _onGpsMoved,
        onError: (e) => _log.debug('Weather: GPS stream error: $e', tag: 'WEATHER'),
      );
      _log.info('Weather: GPS follow enabled (event-driven, distanceFilter=1m)', tag: 'WEATHER');
    } catch (e) {
      _log.error('Weather: could not start GPS stream: $e', tag: 'WEATHER');
    }
  }

  /// Called by the platform whenever the device moves at least 1m.
  /// Throttles weather refresh so we don't spam APIs during a walk/drive.
  Future<void> _onGpsMoved(Position pos) async {
    if (!_gpsRefreshEnabled) return;

    // Throttle: at most one refresh per 15 min unless we jump ≥5km (big move → refresh immediately).
    final now = DateTime.now();
    final since = _lastGpsRefreshAt == null
        ? const Duration(days: 365)
        : now.difference(_lastGpsRefreshAt!);

    double moved = 0;
    if (_latitude != null && _longitude != null) {
      moved = _distanceMeters(_latitude!, _longitude!, pos.latitude, pos.longitude);
    }
    final bigJump = moved >= 5000;
    if (!bigJump && since < const Duration(minutes: 15)) {
      return; // still hot — skip
    }

    _lastGpsRefreshAt = now;
    _latitude = pos.latitude;
    _longitude = pos.longitude;

    // Reverse-geocode only on significant relocation (>5km from last geocoded pos).
    final geoMoved = _lastGeocodedLat != null && _lastGeocodedLon != null
        ? _distanceMeters(_lastGeocodedLat!, _lastGeocodedLon!, pos.latitude, pos.longitude)
        : double.infinity;
    if (geoMoved >= 5000) {
      final newCity = await _reverseGeocodeCity(pos.latitude, pos.longitude);
      if (newCity != null && newCity.isNotEmpty) _city = newCity;
      _lastGeocodedLat = pos.latitude;
      _lastGeocodedLon = pos.longitude;
      _log.info('Weather: GPS moved ${(geoMoved / 1000).toStringAsFixed(1)}km → $_city', tag: 'WEATHER');
    } else {
      _log.info(
        'Weather: GPS event — ${moved.toStringAsFixed(0)}m since last refresh, updating',
        tag: 'WEATHER',
      );
    }

    await _fetchWeather();
    await _fetchAlerts();
    await _fetchAirQuality();
  }

  /// Compute great-circle distance between two coordinates in meters (Haversine).
  double _distanceMeters(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * math.pi / 180;
    final dLon = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180) *
            math.cos(lat2 * math.pi / 180) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Reverse-geocode via Nominatim (OpenStreetMap, free, no API key).
  /// Nominatim ToS: keep to <=1 req/sec, provide a User-Agent — we call at most every 15 min.
  Future<String?> _reverseGeocodeCity(double lat, double lon) async {
    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?lat=$lat&lon=$lon&format=json&accept-language=de&zoom=10',
      );
      final response = await _client
          .get(uri, headers: {'User-Agent': 'ICD360S-Vorsitzer-App/1.0 (contact@icd360s.de)'})
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      final addr = data['address'] as Map<String, dynamic>?;
      if (addr == null) return null;
      return (addr['city'] ?? addr['town'] ?? addr['village'] ?? addr['municipality']
          ?? addr['county'] ?? addr['state']) as String?;
    } catch (e) {
      _log.debug('Weather: reverse geocode failed: $e', tag: 'WEATHER');
      return null;
    }
  }

  /// Geocode city name to lat/lon using Open-Meteo Geocoding API
  Future<bool> _geocodeCity(String city) async {
    try {
      final uri = Uri.parse(
        'https://geocoding-api.open-meteo.com/v1/search?name=${Uri.encodeComponent(city)}&count=1&language=de&format=json',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = data['results'] as List?;
        if (results != null && results.isNotEmpty) {
          _latitude = (results[0]['latitude'] as num).toDouble();
          _longitude = (results[0]['longitude'] as num).toDouble();
          _log.info('Weather: Geocoded "$city" → $_latitude, $_longitude', tag: 'WEATHER');
          return true;
        }
      }
      return false;
    } catch (e) {
      _log.error('Weather: Geocoding failed: $e', tag: 'WEATHER');
      return false;
    }
  }

  /// Map Bright Sky `condition` string + `icon` to a WMO weather code
  int _brightSkyToWmoCode(String? condition, String? icon) {
    // Bright Sky conditions: dry, fog, rain, sleet, snow, hail, thunderstorm
    // Prefer thunderstorm/hail from icon if present
    if (icon == 'thunderstorm') return 95;
    if (condition == 'thunderstorm') return 95;
    if (condition == 'hail') return 96;
    if (condition == 'snow') return 73;
    if (condition == 'sleet') return 68;
    if (condition == 'rain') return 63;
    if (condition == 'fog') return 45;
    // dry → distinguish by cloud cover via icon
    if (icon == 'clear-day' || icon == 'clear-night') return 0;
    if (icon == 'partly-cloudy-day' || icon == 'partly-cloudy-night') return 2;
    if (icon == 'cloudy') return 3;
    return 1; // mostly clear fallback
  }

  /// Fetch REAL current observation from Bright Sky (DWD stations, ~10 min refresh).
  /// Returns true if a WeatherData was produced from Bright Sky data.
  Future<bool> _fetchCurrentBrightSky() async {
    if (_latitude == null || _longitude == null) return false;
    try {
      final uri = Uri.parse(
        'https://api.brightsky.dev/current_weather?lat=$_latitude&lon=$_longitude&units=dwd',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final w = data['weather'];
      if (w == null) return false;

      final temp = (w['temperature'] as num?)?.toDouble();
      if (temp == null) return false; // station may be missing this reading

      final code = _brightSkyToWmoCode(w['condition'] as String?, w['icon'] as String?);
      final ts = w['timestamp'] != null ? DateTime.tryParse(w['timestamp']) : null;

      // Bright Sky returns wind as km/h when units=dwd
      final windSpeed = (w['wind_speed_10'] as num?)?.toDouble()
          ?? (w['wind_speed'] as num?)?.toDouble() ?? 0;
      final windDir = (w['wind_direction_10'] as num?)?.toDouble()
          ?? (w['wind_direction'] as num?)?.toDouble() ?? 0;
      final precip = (w['precipitation_10'] as num?)?.toDouble()
          ?? (w['precipitation'] as num?)?.toDouble() ?? 0;

      final weather = WeatherData(
        temperature: temp,
        apparentTemperature: temp, // Bright Sky doesn't provide feels-like; Open-Meteo fills it later
        weatherCode: code,
        windSpeed: windSpeed,
        windDirection: windDir,
        humidity: (w['relative_humidity'] as num?)?.toInt() ?? 0,
        precipitation: precip,
        pressureMsl: (w['pressure_msl'] as num?)?.toDouble() ?? 0,
        uvIndex: null,
        cloudCover: (w['cloud_cover'] as num?)?.toInt(),
        isDay: ts != null ? (ts.hour >= 6 && ts.hour < 20) : true,
        city: _city,
        timestamp: ts ?? DateTime.now(),
      );

      currentWeather = weather;
      onWeatherUpdate?.call(weather);
      _checkWeatherNotification(weather);

      _log.debug(
        'Weather[BrightSky]: ${weather.icon} ${weather.temperature}°C '
        '${weather.description}, ${weather.windSpeed} km/h, obs=${ts?.toIso8601String() ?? "?"}',
        tag: 'WEATHER',
      );
      return true;
    } catch (e) {
      _log.debug('Weather: Bright Sky current failed (falling back): $e', tag: 'WEATHER');
      return false;
    }
  }

  /// Fetch current weather + hourly + daily forecast.
  /// Tries Bright Sky (real DWD observation) first, then Open-Meteo for forecast + fallback.
  Future<void> _fetchWeather() async {
    if (_latitude == null || _longitude == null) return;

    // 1) Real observation from DWD via Bright Sky (best for Germany)
    final gotBrightSky = await _fetchCurrentBrightSky();

    try {
      final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast'
        '?latitude=$_latitude&longitude=$_longitude'
        '&current=temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,'
        'wind_speed_10m,wind_direction_10m,precipitation,pressure_msl,cloud_cover,is_day,uv_index'
        '&minutely_15=temperature_2m,precipitation,precipitation_probability,weather_code,wind_speed_10m'
        '&hourly=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m,precipitation,precipitation_probability'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum,'
        'wind_speed_10m_max,sunrise,sunset,daylight_duration'
        '&timezone=Europe/Berlin'
        '&forecast_days=7'
        '&forecast_minutely_15=96', // 96 * 15min = 24h of 15-min nowcast
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        // Current weather — used if Bright Sky was unavailable, otherwise just enriches feels-like/UV
        final current = data['current'];
        if (current != null) {
          if (!gotBrightSky) {
            final weather = WeatherData(
              temperature: (current['temperature_2m'] as num).toDouble(),
              apparentTemperature: (current['apparent_temperature'] as num?)?.toDouble()
                  ?? (current['temperature_2m'] as num).toDouble(),
              weatherCode: (current['weather_code'] as num).toInt(),
              windSpeed: (current['wind_speed_10m'] as num).toDouble(),
              windDirection: (current['wind_direction_10m'] as num?)?.toDouble() ?? 0,
              humidity: (current['relative_humidity_2m'] as num).toInt(),
              precipitation: (current['precipitation'] as num?)?.toDouble() ?? 0,
              pressureMsl: (current['pressure_msl'] as num?)?.toDouble() ?? 0,
              uvIndex: (current['uv_index'] as num?)?.toDouble(),
              cloudCover: (current['cloud_cover'] as num?)?.toInt(),
              isDay: (current['is_day'] as num?)?.toInt() == 1,
              city: _city,
              timestamp: DateTime.now(),
            );

            currentWeather = weather;
            onWeatherUpdate?.call(weather);
            _checkWeatherNotification(weather);

            _log.debug(
              'Weather[Open-Meteo]: ${weather.icon} ${weather.temperature}°C, '
              '${weather.description}, Wind: ${weather.windSpeed} km/h',
              tag: 'WEATHER',
            );
          } else if (currentWeather != null) {
            // Enrich Bright Sky observation with values it doesn't provide
            final base = currentWeather!;
            currentWeather = WeatherData(
              temperature: base.temperature,
              apparentTemperature: (current['apparent_temperature'] as num?)?.toDouble()
                  ?? base.apparentTemperature,
              weatherCode: base.weatherCode,
              windSpeed: base.windSpeed,
              windDirection: base.windDirection,
              humidity: base.humidity,
              precipitation: base.precipitation,
              pressureMsl: base.pressureMsl,
              uvIndex: (current['uv_index'] as num?)?.toDouble() ?? base.uvIndex,
              cloudCover: base.cloudCover,
              isDay: (current['is_day'] as num?)?.toInt() == 1,
              city: base.city,
              timestamp: base.timestamp,
            );
            onWeatherUpdate?.call(currentWeather!);
          }
        }

        // 15-minute nowcast (next 24h) — used for the wetter.com-style timeline bar
        final minutely = data['minutely_15'];
        if (minutely != null) {
          final times = (minutely['time'] as List?)?.cast<String>() ?? const [];
          final temps = (minutely['temperature_2m'] as List?) ?? const [];
          final codes = (minutely['weather_code'] as List?) ?? const [];
          final precips = (minutely['precipitation'] as List?) ?? const [];
          final precipProbs = (minutely['precipitation_probability'] as List?) ?? const [];
          final winds = (minutely['wind_speed_10m'] as List?) ?? const [];

          minutelyForecast = [];
          for (int i = 0; i < times.length; i++) {
            final t = DateTime.tryParse(times[i]);
            if (t == null) continue;
            // Skip null entries — Open-Meteo occasionally returns null for future 15-min slots
            final temp = (i < temps.length ? temps[i] : null) as num?;
            final code = (i < codes.length ? codes[i] : null) as num?;
            if (temp == null || code == null) continue;
            minutelyForecast.add(MinutelyForecast(
              time: t,
              temperature: temp.toDouble(),
              weatherCode: code.toInt(),
              precipitation: ((i < precips.length ? precips[i] : 0) as num?)?.toDouble() ?? 0,
              precipitationProbability: ((i < precipProbs.length ? precipProbs[i] : null) as num?)?.toInt(),
              windSpeed: ((i < winds.length ? winds[i] : 0) as num?)?.toDouble() ?? 0,
            ));
          }
        }

        // Hourly forecast
        final hourly = data['hourly'];
        if (hourly != null) {
          final times = (hourly['time'] as List).cast<String>();
          final temps = (hourly['temperature_2m'] as List);
          final codes = (hourly['weather_code'] as List);
          final winds = (hourly['wind_speed_10m'] as List);
          final humids = (hourly['relative_humidity_2m'] as List);
          final precips = (hourly['precipitation'] as List);
          final precipProbs = (hourly['precipitation_probability'] as List?) ?? const [];

          hourlyForecast = [];
          for (int i = 0; i < times.length; i++) {
            final t = DateTime.tryParse(times[i]);
            if (t != null) {
              hourlyForecast.add(HourlyForecast(
                time: t,
                temperature: (temps[i] as num).toDouble(),
                weatherCode: (codes[i] as num).toInt(),
                windSpeed: (winds[i] as num).toDouble(),
                humidity: (humids[i] as num).toInt(),
                precipitation: (precips[i] as num).toDouble(),
                precipitationProbability: ((i < precipProbs.length ? precipProbs[i] : null) as num?)?.toInt(),
              ));
            }
          }
        }

        // Daily forecast (+ sunrise/sunset → drive currentAstronomy for today)
        final daily = data['daily'];
        if (daily != null) {
          final dates = (daily['time'] as List).cast<String>();
          final maxTemps = (daily['temperature_2m_max'] as List);
          final minTemps = (daily['temperature_2m_min'] as List);
          final codes = (daily['weather_code'] as List);
          final precips = (daily['precipitation_sum'] as List);
          final winds = (daily['wind_speed_10m_max'] as List);
          final sunrises = (daily['sunrise'] as List?)?.cast<String?>() ?? const [];
          final sunsets = (daily['sunset'] as List?)?.cast<String?>() ?? const [];

          dailyForecast = [];
          DateTime? todaySunrise;
          DateTime? todaySunset;
          for (int i = 0; i < dates.length; i++) {
            final d = DateTime.tryParse(dates[i]);
            if (d != null) {
              dailyForecast.add(DailyForecast(
                date: d,
                tempMax: (maxTemps[i] as num).toDouble(),
                tempMin: (minTemps[i] as num).toDouble(),
                weatherCode: (codes[i] as num).toInt(),
                precipitationSum: (precips[i] as num).toDouble(),
                windSpeedMax: (winds[i] as num).toDouble(),
              ));
              if (i == 0) {
                todaySunrise = i < sunrises.length && sunrises[i] != null
                    ? DateTime.tryParse(sunrises[i]!) : null;
                todaySunset = i < sunsets.length && sunsets[i] != null
                    ? DateTime.tryParse(sunsets[i]!) : null;
              }
            }
          }
          currentAstronomy = AstronomyData.forDate(
            DateTime.now(),
            sunrise: todaySunrise,
            sunset: todaySunset,
          );
        }
      }
    } catch (e) {
      _log.error('Weather: Fetch failed: $e', tag: 'WEATHER');
    }
  }

  /// Fetch Open-Meteo Air Quality API — free, CAMS-driven. PM2.5/PM10, ozone,
  /// NO2, SO2, CO, European AQI, plus pollen counts (grass/birch/alder/mugwort/
  /// olive/ragweed) when available for the region.
  Future<void> _fetchAirQuality() async {
    if (_latitude == null || _longitude == null) return;
    try {
      final uri = Uri.parse(
        'https://air-quality-api.open-meteo.com/v1/air-quality'
        '?latitude=$_latitude&longitude=$_longitude'
        '&current=pm10,pm2_5,carbon_monoxide,nitrogen_dioxide,sulphur_dioxide,ozone,'
        'uv_index,european_aqi,alder_pollen,birch_pollen,grass_pollen,mugwort_pollen,'
        'olive_pollen,ragweed_pollen'
        '&timezone=Europe/Berlin',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return;

      final data = jsonDecode(response.body);
      final c = data['current'];
      if (c == null) return;

      double? d(String k) => (c[k] as num?)?.toDouble();

      final aq = AirQualityData(
        pm25: d('pm2_5'),
        pm10: d('pm10'),
        ozone: d('ozone'),
        nitrogenDioxide: d('nitrogen_dioxide'),
        sulphurDioxide: d('sulphur_dioxide'),
        carbonMonoxide: d('carbon_monoxide'),
        europeanAqi: d('european_aqi'),
        uvIndex: d('uv_index'),
        alderPollen: d('alder_pollen'),
        birchPollen: d('birch_pollen'),
        grassPollen: d('grass_pollen'),
        mugwortPollen: d('mugwort_pollen'),
        olivePollen: d('olive_pollen'),
        ragweedPollen: d('ragweed_pollen'),
        timestamp: DateTime.now(),
      );

      currentAirQuality = aq;
      onAirQualityUpdate?.call(aq);
      _log.info(
        'AirQuality: AQI=${aq.europeanAqi?.toStringAsFixed(0) ?? "?"} (${aq.aqiLabel}), '
        'PM2.5=${aq.pm25?.toStringAsFixed(1) ?? "?"} µg/m³, pollen=${aq.pollenActive ? "yes" : "no"}',
        tag: 'WEATHER',
      );
    } catch (e) {
      _log.debug('AirQuality: fetch failed: $e', tag: 'WEATHER');
    }
  }

  /// Fetch DWD alerts from Bright Sky API
  Future<void> _fetchAlerts() async {
    if (_latitude == null || _longitude == null) return;

    try {
      final uri = Uri.parse(
        'https://api.brightsky.dev/alerts?lat=$_latitude&lon=$_longitude',
      );
      final response = await _client.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final alertsJson = data['alerts'] as List? ?? [];

        final alerts = alertsJson.map<WeatherAlert>((a) {
          return WeatherAlert(
            headline: a['headline_de'] ?? a['headline'] ?? '',
            description: a['description_de'] ?? a['description'] ?? '',
            severity: a['severity'] ?? 'minor',
            event: a['event_de'] ?? a['event'] ?? '',
            instruction: a['instruction_de'] ?? a['instruction'],
            onset: a['onset'] != null ? DateTime.tryParse(a['onset']) : null,
            expires: a['expires'] != null ? DateTime.tryParse(a['expires']) : null,
          );
        }).where((a) => a.isRelevant).toList();

        currentAlerts = alerts;
        onAlertsUpdate?.call(alerts);

        // Notify new alerts
        _checkAlertNotifications(alerts);

        _log.info('Weather: ${alerts.length} DWD warning(s) for $_city', tag: 'WEATHER');
      }
    } catch (e) {
      _log.error('Weather: Alerts fetch failed: $e', tag: 'WEATHER');
    }
  }

  /// Send notification when weather changes to rain/snow/thunder
  void _checkWeatherNotification(WeatherData weather) {
    // Only notify on change (not same code repeatedly)
    if (_lastNotifiedWeatherCode == weather.weatherCode) return;

    String? title;
    String? body;

    if (weather.isThunder) {
      title = '⛈️ Gewitter in $_city';
      body = '${weather.description} • ${weather.temperature.toStringAsFixed(0)}°C';
    } else if (weather.isSnow) {
      title = '🌨️ Schneefall in $_city';
      body = '${weather.description} • ${weather.temperature.toStringAsFixed(0)}°C';
    } else if (weather.isRain) {
      title = '🌧️ Regen in $_city';
      body = '${weather.description} • ${weather.temperature.toStringAsFixed(0)}°C';
    }

    if (title != null && body != null) {
      _lastNotifiedWeatherCode = weather.weatherCode;
      NotificationService().show(
        title: title,
        body: body,
      );
      _log.info('Weather: Notification sent - $title', tag: 'WEATHER');
    } else {
      // Reset when weather clears
      _lastNotifiedWeatherCode = weather.weatherCode;
    }

    // Wind notification (separate from weather code)
    final isStrongWind = weather.windSpeed >= 50;
    if (isStrongWind && !_lastNotifiedStrongWind) {
      _lastNotifiedStrongWind = true;
      NotificationService().show(
        title: '💨 Starker Wind in $_city',
        body: 'Windgeschwindigkeit: ${weather.windSpeed.toStringAsFixed(0)} km/h',
      );
      _log.info('Weather: Wind notification sent - ${weather.windSpeed} km/h', tag: 'WEATHER');
    } else if (!isStrongWind) {
      _lastNotifiedStrongWind = false;
    }
  }

  /// Send notification for new DWD weather alerts
  void _checkAlertNotifications(List<WeatherAlert> alerts) {
    for (final alert in alerts) {
      if (!_lastNotifiedAlertHeadlines.contains(alert.headline)) {
        _lastNotifiedAlertHeadlines.add(alert.headline);

        String severityIcon;
        switch (alert.severity) {
          case 'extreme':
            severityIcon = '🔴';
            break;
          case 'severe':
            severityIcon = '🟠';
            break;
          case 'moderate':
            severityIcon = '🟡';
            break;
          default:
            severityIcon = '🟢';
        }

        NotificationService().show(
          title: '$severityIcon DWD Warnung: ${alert.event}',
          body: alert.headline,
        );
        _log.info('Weather: DWD alert notification - ${alert.headline}', tag: 'WEATHER');
      }
    }
  }

  /// Update location (e.g. when GPS detects a new city) and re-fetch
  Future<void> updateLocation(String city, {required double lat, required double lon}) async {
    _city = city;
    _latitude = lat;
    _longitude = lon;
    _log.info('Weather: Location updated → $city ($lat, $lon)', tag: 'WEATHER');
    await _fetchWeather();
    await _fetchAlerts();
    await _fetchAirQuality();
  }

  /// Force refresh weather + alerts + air quality
  Future<void> refresh() async {
    await _fetchWeather();
    await _fetchAlerts();
    await _fetchAirQuality();
  }
}
