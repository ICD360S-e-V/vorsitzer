import 'dart:async';
import 'dart:convert';
// dart:ui is aliased so the CustomPainter can spell out `ui.Path` and
// `ui.TextDirection.ltr` — flutter_map exports a generic `Path<T>` and its
// own `TextDirection` that leak through via generic type parameters and
// shadow the canvas types even when we `show`-restrict the import.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart'
    show FlutterMap, MapController, MapOptions, TileLayer, MarkerLayer, Marker;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:latlong2/latlong.dart';
import '../services/clothing_advice.dart';
import '../services/weather_history_service.dart';
import '../services/weather_profile_service.dart';
import '../services/weather_service.dart';
import '../utils/weather_pdf_generator.dart';
import 'weather_profile_dialog.dart';

/// Emoji font fallback list — applied per-Text ONLY on widgets that render
/// emoji characters. Avoids setting this on the ThemeData level (which would
/// affect kerning/letter-spacing of every text in the app).
///
/// Windows: Segoe UI has no color glyphs for U+2600 (☀) / U+2601 (☁) etc.
/// Linux / Android need Noto Color Emoji as fallback.
/// macOS / iOS need Apple Color Emoji.
const List<String> _kEmojiFonts = [
  'Segoe UI Emoji',
  'Apple Color Emoji',
  'Noto Color Emoji',
];

TextStyle _emojiStyle({double fontSize = 14, Color? color}) => TextStyle(
      fontSize: fontSize,
      color: color,
      fontFamilyFallback: _kEmojiFonts,
    );

/// Compact/full weather pill for the AppBar and the detailed weather dialog.
///
/// Split out of `dashboard_screen.dart` — the AppBar widget is one call:
///   WeatherPill(weather: _weatherData!, alertsCount: _weatherAlerts.length,
///               compact: width < 600, onTap: () => showWeatherDialog(...));

/// Small pill shown in the AppBar. Tap → opens [WeatherDialog].
///
/// - `compact: true` → emoji + temperature only (fits narrow phone AppBar).
/// - `compact: false` → emoji + temp + city + description + optional feels-like.
class WeatherPill extends StatelessWidget {
  final WeatherData weather;
  final int alertsCount;
  final bool compact;
  final VoidCallback onTap;

  /// "↑" (warming), "↓" (cooling) or null for stable. Compared over ~3h.
  final String? trendArrow;
  /// True when a 15-min forecast slot in the next 45 min has ≥60 % rain
  /// probability — pill shows a small 💧 hint even if it's clear right now.
  final bool imminentPrecipitation;
  /// True when the last successful fetch is >30 min old — pill dims and
  /// shows a ⏱ badge so the reader knows the number may be stale.
  final bool isStale;
  /// True when the location is coming from the device GPS, not a fixed city —
  /// shows a small 📍 next to the city name.
  final bool gpsFollowing;

  const WeatherPill({
    super.key,
    required this.weather,
    required this.alertsCount,
    required this.compact,
    required this.onTap,
    this.trendArrow,
    this.imminentPrecipitation = false,
    this.isStale = false,
    this.gpsFollowing = false,
  });

  @override
  Widget build(BuildContext context) {
    // Dim everything when stale so users don't act on old data by accident.
    final baseColor = isStale
        ? Colors.white.withValues(alpha: 0.55)
        : Colors.white;
    final subColor = isStale
        ? Colors.white.withValues(alpha: 0.4)
        : Colors.white.withValues(alpha: 0.7);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 6 : 10,
          vertical: 4,
        ),
        margin: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(weather.icon, style: _emojiStyle(fontSize: compact ? 16 : 18)),
            // Imminent-rain dot: small light-blue 💧 tucked between icon and
            // temperature so it doesn't compete with the main condition emoji.
            if (imminentPrecipitation) ...[
              const SizedBox(width: 2),
              Text('💧', style: _emojiStyle(fontSize: compact ? 11 : 13)),
            ],
            SizedBox(width: compact ? 3 : 4),
            if (compact)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${weather.temperature.toStringAsFixed(0)}°',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: baseColor,
                    ),
                  ),
                  if (trendArrow != null)
                    Text(
                      trendArrow!,
                      style: TextStyle(
                        fontSize: 11,
                        color: trendArrow == '↑'
                            ? Colors.orange.shade200
                            : Colors.lightBlue.shade200,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                ],
              )
            else
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${weather.temperature.toStringAsFixed(0)}°C',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: baseColor,
                        ),
                      ),
                      if (trendArrow != null) ...[
                        const SizedBox(width: 2),
                        Text(
                          trendArrow!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: trendArrow == '↑'
                                ? Colors.orange.shade200
                                : Colors.lightBlue.shade200,
                          ),
                        ),
                      ],
                      if ((weather.apparentTemperature - weather.temperature).abs() >= 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(gefühlt ${weather.apparentTemperature.toStringAsFixed(0)}°)',
                          style: TextStyle(
                            fontSize: 9,
                            color: subColor,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (gpsFollowing) ...[
                        Icon(Icons.my_location, size: 9, color: subColor),
                        const SizedBox(width: 2),
                      ],
                      Flexible(
                        child: Text(
                          weather.city.isEmpty ? weather.description : weather.city,
                          style: TextStyle(fontSize: 9, color: subColor),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isStale) ...[
                        const SizedBox(width: 4),
                        Icon(Icons.access_time, size: 9, color: subColor),
                      ],
                    ],
                  ),
                ],
              ),
            // Combined alert badge: DWD warnings + local health advisories.
            if (alertsCount > 0) ...[
              SizedBox(width: compact ? 3 : 4),
              Container(
                padding: const EdgeInsets.all(2),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '$alertsCount',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Convenience: open the detailed weather dialog for the given service.
void showWeatherDialog(BuildContext context, WeatherService service) {
  if (service.currentWeather == null) return;
  showDialog(
    context: context,
    builder: (_) => WeatherDialog(service: service),
  );
}

/// Full 4-tab weather dialog: Aktuell / Stündlich / 3 Tage / Woche.
///
/// Stateful because the "Aktualisieren" button re-fetches and rebuilds inline
/// (no close+reopen), and because we listen to service callbacks for live pushes.
class WeatherDialog extends StatefulWidget {
  final WeatherService service;

  const WeatherDialog({super.key, required this.service});

  @override
  State<WeatherDialog> createState() => _WeatherDialogState();
}

class _WeatherDialogState extends State<WeatherDialog> {
  void Function(WeatherData)? _prevWeatherCb;
  void Function(List<WeatherAlert>)? _prevAlertsCb;
  void Function(AirQualityData)? _prevAirQualityCb;

  // Historical comparison — lazy-loaded when the user hits the Woche tab.
  final _historyService = WeatherHistoryService();
  List<HistoricalWeekSummary>? _history;
  bool _historyLoading = false;

  @override
  void initState() {
    super.initState();
    // Chain existing callbacks so we don't clobber dashboard listeners.
    _prevWeatherCb = widget.service.onWeatherUpdate;
    _prevAlertsCb = widget.service.onAlertsUpdate;
    _prevAirQualityCb = widget.service.onAirQualityUpdate;
    widget.service.onWeatherUpdate = (w) {
      _prevWeatherCb?.call(w);
      if (mounted) setState(() {});
    };
    widget.service.onAlertsUpdate = (a) {
      _prevAlertsCb?.call(a);
      if (mounted) setState(() {});
    };
    widget.service.onAirQualityUpdate = (a) {
      _prevAirQualityCb?.call(a);
      if (mounted) setState(() {});
    };
    _maybeLoadHistory();
  }

  void _maybeLoadHistory() {
    final lat = widget.service.latitude;
    final lon = widget.service.longitude;
    if (lat == null || lon == null) return;
    if (_historyLoading || _history != null) return;
    _historyLoading = true;
    final weekStart = _weekStartMonday(DateTime.now());
    _historyService
        .fetchWeekComparison(lat: lat, lon: lon, weekStart: weekStart)
        .then((rows) {
      if (!mounted) return;
      setState(() {
        _history = rows;
        _historyLoading = false;
      });
    }).catchError((_) {
      if (!mounted) return;
      setState(() {
        _historyLoading = false;
      });
    });
  }

  static DateTime _weekStartMonday(DateTime d) {
    final base = DateTime(d.year, d.month, d.day);
    return base.subtract(Duration(days: base.weekday - 1));
  }

  // ── Text-to-speech ──
  FlutterTts? _tts;
  bool _ttsSpeaking = false;

  Future<void> _toggleTts(WeatherData w) async {
    // Toggle: second tap stops. Prevents lock-out if the user changes their mind.
    if (_ttsSpeaking) {
      await _tts?.stop();
      if (mounted) setState(() => _ttsSpeaking = false);
      return;
    }
    _tts ??= FlutterTts();
    try {
      await _tts!.setLanguage('de-DE');
      await _tts!.setSpeechRate(0.5); // slower — clearer for elderly listeners
      await _tts!.setVolume(1.0);
      await _tts!.setPitch(1.0);
    } catch (_) { /* platform without TTS — silently skip */ }

    final aq = widget.service.currentAirQuality;
    final astro = widget.service.currentAstronomy;
    final parts = <String>[
      'Aktuelles Wetter in ${w.city.isEmpty ? "deiner Region" : w.city}.',
      '${w.temperature.toStringAsFixed(0)} Grad, ${w.description}.',
      if ((w.apparentTemperature - w.temperature).abs() >= 1)
        'Gefühlt ${w.apparentTemperature.toStringAsFixed(0)} Grad.',
      'Wind ${w.windSpeed.toStringAsFixed(0)} Kilometer pro Stunde aus ${_windDirLong(w.windCompass)}.',
      'Luftfeuchtigkeit ${w.humidity} Prozent.',
      if (aq?.europeanAqi != null)
        'Luftqualität: ${aq!.aqiLabel}.',
      if (aq?.pollenActive == true)
        'Pollenflug aktiv.',
      if (astro?.sunset != null)
        'Sonnenuntergang um '
        '${astro!.sunset!.hour}:${astro.sunset!.minute.toString().padLeft(2, "0")}.',
      if (widget.service.hasImminentPrecipitation())
        'Achtung: in den nächsten Minuten wird Regen erwartet.',
    ];
    final text = parts.join(' ');

    _tts!.setCompletionHandler(() {
      if (mounted) setState(() => _ttsSpeaking = false);
    });
    _tts!.setCancelHandler(() {
      if (mounted) setState(() => _ttsSpeaking = false);
    });

    setState(() => _ttsSpeaking = true);
    await _tts!.speak(text);
  }

  String _windDirLong(String compass) {
    const map = {
      'N': 'Norden', 'NO': 'Nordosten', 'O': 'Osten', 'SO': 'Südosten',
      'S': 'Süden', 'SW': 'Südwesten', 'W': 'Westen', 'NW': 'Nordwesten',
    };
    return map[compass] ?? compass;
  }

  /// Bottom-sheet with full forecast detail for one 15-min or hourly slot.
  /// Reused by the sticky-bar timeline and the Stündlich list.
  void showForecastDetailSheet({
    required BuildContext context,
    required DateTime time,
    required int weatherCode,
    required String emoji,
    required String description,
    required double temperature,
    double? apparentTemperature,
    required double windSpeed,
    String? windCompass,
    int? humidity,
    double? precipitation,
    int? precipitationProbability,
  }) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: _emojiStyle(fontSize: 40)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(description,
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        DateFormat("EEEE, dd.MM. HH:mm 'Uhr'", 'de_DE').format(time),
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _detailKV('Temperatur', '${temperature.toStringAsFixed(1)}°C',
                Icons.thermostat, Colors.orange.shade700),
            if (apparentTemperature != null &&
                (apparentTemperature - temperature).abs() >= 0.5)
              _detailKV('Gefühlt', '${apparentTemperature.toStringAsFixed(1)}°C',
                  Icons.device_thermostat, Colors.deepOrange.shade700),
            _detailKV(
              'Wind',
              '${windSpeed.toStringAsFixed(0)} km/h '
                  '${windCompass ?? ""} · ${BeaufortScale.labelForKmh(windSpeed)} '
                  '(${BeaufortScale.forKmh(windSpeed)} Bft)',
              Icons.air,
              Colors.blueGrey.shade700,
            ),
            if (humidity != null)
              _detailKV('Feuchtigkeit', '$humidity %',
                  Icons.water_drop, Colors.blue.shade700),
            if (precipitation != null && precipitation > 0)
              _detailKV('Niederschlag', '${precipitation.toStringAsFixed(1)} mm/h',
                  Icons.grain, Colors.blue.shade900),
            if (precipitationProbability != null && precipitationProbability > 0)
              _detailKV('Regenwahrscheinlichkeit', '$precipitationProbability %',
                  Icons.umbrella, Colors.blue.shade500),
            const SizedBox(height: 8),
            Text(
              'WMO-Code $weatherCode',
              style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailKV(String key, String value, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          SizedBox(
            width: 170,
            child: Text(key, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(value,
                style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.bold, color: color)),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    widget.service.onWeatherUpdate = _prevWeatherCb;
    widget.service.onAlertsUpdate = _prevAlertsCb;
    widget.service.onAirQualityUpdate = _prevAirQualityCb;
    _tts?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = widget.service.currentWeather;
    if (weather == null) {
      return const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Keine Wetterdaten verfügbar'),
        ),
      );
    }

    final alerts = widget.service.currentAlerts;
    final df = DateFormat('HH:mm', 'de_DE');
    final dfDay = DateFormat('E dd.MM.', 'de_DE');
    final dfDayShort = DateFormat('E', 'de_DE');
    final now = DateTime.now();

    final next24h = widget.service.hourlyForecast
        .where((h) => h.time.isAfter(now) && h.time.isBefore(now.add(const Duration(hours: 25))))
        .toList();
    final next3Days = widget.service.dailyForecast.take(3).toList();
    final weekForecast = widget.service.dailyForecast.toList();

    // Adapt dialog size to the screen: on phone-sized viewports we go full
    // screen; on tablets/desktop we cap at 900×800 so it doesn't stretch
    // uncomfortably wide on ultra-wide monitors.
    final screen = MediaQuery.of(context).size;
    final isPhone = screen.width < 600;
    final dialogWidth = isPhone ? screen.width : (screen.width * 0.9).clamp(600.0, 1100.0);
    final dialogHeight = isPhone ? screen.height : (screen.height * 0.9).clamp(600.0, 900.0);

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isPhone ? 0 : 24,
        vertical: isPhone ? 0 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(isPhone ? 0 : 12),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: DefaultTabController(
          length: 6,
          child: Column(
            children: [
              _buildHeader(context, weather),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildAktuellTab(weather, alerts),
                    _buildStuendlichTab(next24h, df),
                    _buildUmweltTab(),
                    _buildRadarTab(),
                    _buildDreiTageTab(next3Days, dfDay),
                    _buildWocheTab(weekForecast, dfDayShort, now),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, WeatherData weather) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text(weather.icon, style: _emojiStyle(fontSize: 32)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Wetter in ${weather.city}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '${weather.description} • ${weather.temperature.toStringAsFixed(1)}°C'
                      '${(weather.apparentTemperature - weather.temperature).abs() >= 1 ? " (gefühlt ${weather.apparentTemperature.toStringAsFixed(1)}°C)" : ""}',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                    Text(
                      'Stand: ${DateFormat('HH:mm', 'de_DE').format(weather.timestamp)}',
                      style: TextStyle(fontSize: 10, color: Colors.grey.shade500),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(
                  _ttsSpeaking ? Icons.stop_circle : Icons.volume_up,
                  size: 20,
                  color: _ttsSpeaking ? Colors.red.shade600 : null,
                ),
                tooltip: _ttsSpeaking ? 'Vorlesen stoppen' : 'Wetterbericht vorlesen',
                onPressed: () => _toggleTts(weather),
              ),
              IconButton(
                icon: const Icon(Icons.picture_as_pdf, size: 20),
                tooltip: 'Wochenübersicht als PDF',
                onPressed: () async {
                  await generateAndShareWeatherPdf(service: widget.service);
                },
              ),
              ValueListenableBuilder<WeatherProfile>(
                valueListenable: WeatherProfileService.instance.notifier,
                builder: (_, p, __) => IconButton(
                  icon: Icon(
                    Icons.tune,
                    size: 20,
                    color: (p.coldSensitive || p.heatSensitive || p.asthma ||
                            p.photoSensitive || p.anyAllergy)
                        ? Colors.teal.shade400
                        : null,
                  ),
                  tooltip: 'Mein Wetter-Profil',
                  onPressed: () async {
                    await showDialog(
                      context: context,
                      builder: (_) => const WeatherProfileDialog(),
                    );
                    if (mounted) setState(() {}); // refresh in case allergies changed pollen highlight
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: 'Aktualisieren',
                onPressed: () async {
                  await widget.service.refresh();
                  if (mounted) setState(() {});
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const TabBar(
            isScrollable: true,
            labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            unselectedLabelStyle: TextStyle(fontSize: 12),
            tabAlignment: TabAlignment.center,
            tabs: [
              Tab(text: 'Aktuell'),
              Tab(text: 'Stündlich'),
              Tab(text: 'Umwelt'),
              Tab(text: 'Radar'),
              Tab(text: '3 Tage'),
              Tab(text: 'Woche'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAktuellTab(WeatherData weather, List<WeatherAlert> alerts) {
    final minutely = widget.service.minutelyForecast;
    return RefreshIndicator(
      onRefresh: () async {
        await widget.service.refresh();
        if (mounted) setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // wetter.com-style 15-min timeline (next ~6h). Scrollable horizontally.
          if (minutely.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.timeline, size: 16, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text('15-Minuten Nowcast',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
                const Spacer(),
                Text('Scrollen →', style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
              ],
            ),
            const SizedBox(height: 6),
            _MinutelyTimeline(entries: minutely),
            const SizedBox(height: 14),
          ],
          // Row 1: Temperatur / Wind / Feuchtigkeit
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _detailColumn('Temperatur', '${weather.temperature.toStringAsFixed(1)}°C', Icons.thermostat),
                _detailColumn(
                  'Wind · ${weather.beaufortLabel}',
                  '${weather.windSpeed.toStringAsFixed(0)} km/h ${weather.windCompass} '
                      '(${weather.beaufort} Bft)',
                  Icons.air,
                ),
                _detailColumn('Feuchtigkeit', '${weather.humidity}%', Icons.water_drop),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Row 2: Gefühlt / Niederschlag / Luftdruck
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _detailColumn('Gefühlt', '${weather.apparentTemperature.toStringAsFixed(1)}°C', Icons.device_thermostat),
                _detailColumn('Niederschlag', '${weather.precipitation.toStringAsFixed(1)} mm', Icons.grain),
                _detailColumn('Luftdruck', '${weather.pressureMsl.toStringAsFixed(0)} hPa', Icons.speed),
              ],
            ),
          ),
          if (weather.uvIndex != null || weather.cloudCover != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  if (weather.uvIndex != null)
                    _detailColumn('UV-Index', weather.uvIndex!.toStringAsFixed(1), Icons.wb_sunny),
                  if (weather.cloudCover != null)
                    _detailColumn('Bewölkung', '${weather.cloudCover}%', Icons.cloud),
                  _detailColumn(
                    'Beobachtung',
                    DateFormat('HH:mm').format(weather.timestamp),
                    Icons.schedule,
                  ),
                ],
              ),
            ),
          ],
          // Quick AQI/pollen summary — tap to jump to the Umwelt tab. Saves
          // the user a full navigation just to check "is the air OK today?".
          if (widget.service.currentAirQuality != null) ...[
            const SizedBox(height: 10),
            _buildAqiPollenSummaryCard(widget.service.currentAirQuality!),
          ],
          // Astronomy — sunrise/sunset + moon phase
          if (widget.service.currentAstronomy != null) ...[
            const SizedBox(height: 10),
            _buildAstronomyCard(widget.service.currentAstronomy!),
          ],
          // Anziehtipp — derived from current WeatherData + optional AirQuality
          const SizedBox(height: 12),
          Builder(builder: (_) {
            final aq = widget.service.currentAirQuality;
            final advice = computeClothingAdvice(
              apparentTemp: weather.apparentTemperature,
              temp: weather.temperature,
              weatherCode: weather.weatherCode,
              wind: weather.windSpeed,
              precipProb: 0, // no probability for "now" — only forecast has it
              precip: weather.precipitation,
              uvIndex: weather.uvIndex ?? aq?.uvIndex,
              humidity: weather.humidity,
              durationMinutes: 60,
            );
            return ClothingAdviceCard(advice: advice, headline: 'Für jetzt');
          }),
          // DWD Alerts
          if (alerts.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                const Icon(Icons.warning_amber, color: Colors.red, size: 18),
                const SizedBox(width: 6),
                Text(
                  'DWD Warnungen (${alerts.length})',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.red),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ...alerts.map(_buildAlertCard),
          ] else ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle, size: 16, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Text('Keine DWD Warnungen aktiv',
                      style: TextStyle(fontSize: 12, color: Colors.green.shade700)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Text(
            'Beobachtung: DWD via Bright Sky • Vorhersage/UV: Open-Meteo',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
          ],
        ),
      ),
    );
  }

  Widget _buildStuendlichTab(List<HourlyForecast> next24h, DateFormat df) {
    return _StuendlichView(next24h: next24h, df: df);
  }


  Widget _buildRadarTab() {
    final lat = widget.service.latitude;
    final lon = widget.service.longitude;
    if (lat == null || lon == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Standort nicht verfügbar — Radar kann nicht angezeigt werden.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey),
          ),
        ),
      );
    }
    // Auto-play the radar loop when precipitation is imminent — a bit of
    // motion draws the eye and makes the "rain incoming" state obvious.
    return _RainRadarView(
      centerLat: lat,
      centerLon: lon,
      autoPlay: widget.service.hasImminentPrecipitation(),
    );
  }

  Widget _buildDreiTageTab(List<DailyForecast> next3Days, DateFormat dfDay) {
    if (next3Days.isEmpty) return const Center(child: Text('Keine Vorhersage verfügbar'));
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: next3Days.map((d) => _buildDayForecastCard(d, dfDay)).toList(),
      ),
    );
  }

  Widget _buildWocheTab(List<DailyForecast> weekForecast, DateFormat dfDayShort, DateTime now) {
    if (weekForecast.isEmpty) return const Center(child: Text('Keine Vorhersage verfügbar'));
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WeeklyTrendChart(week: weekForecast, today: now),
          const SizedBox(height: 12),
          _HistoricalComparisonCard(
            current: weekForecast,
            history: _history,
            isLoading: _historyLoading,
          ),
          const SizedBox(height: 12),
          ..._buildWeekList(weekForecast, dfDayShort, now),
        ],
      ),
    );
  }

  List<Widget> _buildWeekList(List<DailyForecast> weekForecast, DateFormat dfDayShort, DateTime now) {
    return List.generate(weekForecast.length, (i) {
      final d = weekForecast[i];
      final isToday = d.date.day == now.day && d.date.month == now.month;
      return _weekListRow(d, dfDayShort, isToday, i, weekForecast);
    });
  }

  Widget _weekListRow(
    DailyForecast d,
    DateFormat dfDayShort,
    bool isToday,
    int i,
    List<DailyForecast> weekForecast,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isToday ? Colors.blue.shade50 : (i.isEven ? Colors.grey.shade50 : null),
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: Colors.blue.shade200) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 35,
            child: Text(
              isToday ? 'Heu.' : dfDayShort.format(d.date),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(d.icon, style: _emojiStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Text('${d.tempMin.toStringAsFixed(0)}°',
              style: TextStyle(fontSize: 13, color: Colors.blue.shade700)),
          const SizedBox(width: 4),
          Expanded(child: _buildTempRangeBar(d.tempMin, d.tempMax, weekForecast)),
          const SizedBox(width: 4),
          Text(
            '${d.tempMax.toStringAsFixed(0)}°',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
          ),
          const SizedBox(width: 10),
          if (d.precipitationSum > 0) ...[
            Icon(Icons.water_drop, size: 14, color: Colors.blue.shade400),
            Text(
              d.precipitationSum.toStringAsFixed(1),
              style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
            ),
            const SizedBox(width: 6),
          ],
          Icon(Icons.air, size: 14, color: Colors.grey.shade400),
          const SizedBox(width: 2),
          SizedBox(
            width: 30,
            child: Text(
              d.windSpeedMax.toStringAsFixed(0),
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(WeatherAlert alert) {
    final color = _alertColor(alert.severity);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  alert.severityLabel,
                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(alert.event, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(alert.headline, style: const TextStyle(fontSize: 11)),
          if (alert.onset != null || alert.expires != null) ...[
            const SizedBox(height: 4),
            Text(
              [
                if (alert.onset != null)
                  'Von: ${alert.onset!.day}.${alert.onset!.month}.${alert.onset!.year} ${alert.onset!.hour}:${alert.onset!.minute.toString().padLeft(2, '0')}',
                if (alert.expires != null)
                  'Bis: ${alert.expires!.day}.${alert.expires!.month}.${alert.expires!.year} ${alert.expires!.hour}:${alert.expires!.minute.toString().padLeft(2, '0')} Uhr',
              ].join(' • '),
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDayForecastCard(DailyForecast day, DateFormat dfDay) {
    final now = DateTime.now();
    final isToday = day.date.day == now.day && day.date.month == now.month;

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: isToday ? 2 : 0.5,
      color: isToday ? Colors.blue.shade50 : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: isToday ? BorderSide(color: Colors.blue.shade200) : BorderSide.none,
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(day.icon, style: _emojiStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isToday ? 'Heute' : dfDay.format(day.date),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: isToday ? Colors.blue.shade800 : null,
                        ),
                      ),
                      Text(day.description, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${day.tempMax.toStringAsFixed(0)}°C',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange.shade800),
                    ),
                    Text(
                      '${day.tempMin.toStringAsFixed(0)}°C',
                      style: TextStyle(fontSize: 13, color: Colors.blue.shade700),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _smallInfo(Icons.air, '${day.windSpeedMax.toStringAsFixed(0)} km/h'),
                _smallInfo(Icons.water_drop, '${day.precipitationSum.toStringAsFixed(1)} mm'),
              ],
            ),
            const SizedBox(height: 10),
            // Anziehtipp derived from the day's max temp — approximates
            // "what to wear during the warmest hours". Daily data has no
            // apparent-temp/humidity, so we pass tempMax as the best proxy.
            ClothingAdviceCard(
              advice: computeClothingAdvice(
                apparentTemp: day.tempMax,
                temp: day.tempMax,
                weatherCode: day.weatherCode,
                wind: day.windSpeedMax,
                precipProb: day.precipitationSum >= 2 ? 70 : (day.precipitationSum >= 0.5 ? 40 : 0),
                precip: day.precipitationSum / 24, // rough hourly avg
                durationMinutes: 60,
              ),
              headline: isToday ? 'für heute tagsüber' : 'für ${dfDay.format(day.date)}',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTempRangeBar(double tempMin, double tempMax, List<DailyForecast> all) {
    double globalMin = all.fold(double.infinity, (v, d) => d.tempMin < v ? d.tempMin : v);
    double globalMax = all.fold(-double.infinity, (v, d) => d.tempMax > v ? d.tempMax : v);
    final range = globalMax - globalMin;
    if (range <= 0) return const SizedBox();

    final leftFraction = (tempMin - globalMin) / range;
    final widthFraction = (tempMax - tempMin) / range;

    return LayoutBuilder(
      builder: (_, constraints) {
        final totalWidth = constraints.maxWidth;
        return Stack(
          children: [
            Container(
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Positioned(
              left: leftFraction * totalWidth,
              child: Container(
                width: (widthFraction * totalWidth).clamp(4, totalWidth),
                height: 4,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade300, Colors.orange.shade400],
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailColumn(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 20, color: Colors.blue.shade700),
        const SizedBox(height: 4),
        Text(value,
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blue.shade800)),
        Text(label, style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
      ],
    );
  }

  Widget _smallInfo(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
      ],
    );
  }

  Widget _buildAstronomyCard(AstronomyData astro) {
    final df = DateFormat('HH:mm', 'de_DE');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          Column(
            children: [
              Text('🌅', style: _emojiStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                astro.sunrise != null ? df.format(astro.sunrise!) : '—',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.orange.shade900),
              ),
              Text('Sonnenaufgang', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
          Column(
            children: [
              Text('🌇', style: _emojiStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                astro.sunset != null ? df.format(astro.sunset!) : '—',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.deepOrange.shade900),
              ),
              Text('Sonnenuntergang', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
          Column(
            children: [
              Text(astro.moonEmoji, style: _emojiStyle(fontSize: 20)),
              const SizedBox(height: 4),
              Text(
                '${astro.moonIlluminationPercent}%',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.indigo.shade900),
              ),
              Text(astro.moonPhaseLabel, style: TextStyle(fontSize: 10, color: Colors.grey.shade600), textAlign: TextAlign.center),
            ],
          ),
          if (astro.daylight != null)
            Column(
              children: [
                Icon(Icons.wb_sunny_outlined, size: 20, color: Colors.amber.shade700),
                const SizedBox(height: 4),
                Text(
                  '${astro.daylight!.inHours}h ${astro.daylight!.inMinutes.remainder(60)}m',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber.shade900),
                ),
                Text('Tageslänge', style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
              ],
            ),
        ],
      ),
    );
  }

  /// Small tappable summary of air-quality + active pollen shown on the
  /// Aktuell tab. Tap → jumps to the Umwelt tab for the full breakdown.
  Widget _buildAqiPollenSummaryCard(AirQualityData aq) {
    // Which pollens are currently noticeable (≥10 grains/m³ ≈ start of light).
    final activePollens = <String>[
      if ((aq.alderPollen ?? 0) >= 10) 'Erle',
      if ((aq.birchPollen ?? 0) >= 10) 'Birke',
      if ((aq.grassPollen ?? 0) >= 10) 'Gräser',
      if ((aq.mugwortPollen ?? 0) >= 10) 'Beifuß',
      if ((aq.olivePollen ?? 0) >= 10) 'Olive',
      if ((aq.ragweedPollen ?? 0) >= 10) 'Ambrosia',
    ];
    return InkWell(
      onTap: () {
        final controller = DefaultTabController.maybeOf(context);
        controller?.animateTo(2); // 0=Aktuell 1=Stündlich 2=Umwelt
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.teal.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.teal.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.air, size: 22, color: _aqiColor(aq.europeanAqi)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    aq.europeanAqi != null
                        ? 'Luftqualität: ${aq.aqiLabel} (AQI ${aq.europeanAqi!.toStringAsFixed(0)})'
                        : 'Luftqualität: unbekannt',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: _aqiColor(aq.europeanAqi),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    activePollens.isEmpty
                        ? 'Pollen: keine aktiven Belastungen'
                        : 'Pollen aktiv: ${activePollens.join(", ")}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: Colors.teal.shade700),
          ],
        ),
      ),
    );
  }

  Widget _buildUmweltTab() {
    final aq = widget.service.currentAirQuality;
    if (aq == null) {
      // Shimmer skeleton while the first Air-Quality fetch is in flight.
      return const _UmweltSkeleton();
    }
    return RefreshIndicator(
      onRefresh: () async {
        await widget.service.refresh();
        if (mounted) setState(() {});
      },
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // European AQI headline
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _aqiColor(aq.europeanAqi).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _aqiColor(aq.europeanAqi).withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                Icon(Icons.air, size: 30, color: _aqiColor(aq.europeanAqi)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Europäischer Luftqualitäts-Index',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                      Text(
                        aq.europeanAqi != null
                            ? '${aq.europeanAqi!.toStringAsFixed(0)} • ${aq.aqiLabel}'
                            : 'unbekannt',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _aqiColor(aq.europeanAqi),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Text('Schadstoffe (µg/m³)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
              const SizedBox(width: 6),
              Text('· tippen für Details',
                  style: TextStyle(fontSize: 9, color: Colors.grey.shade500)),
            ],
          ),
          const SizedBox(height: 6),
          _pollutantRow('Feinstaub PM2.5', aq.pm25,
              warnAbove: 25, dangerAbove: 50, code: 'pm25', yesterday: aq.yesterdayPm25Avg),
          _pollutantRow('Feinstaub PM10', aq.pm10,
              warnAbove: 50, dangerAbove: 100, code: 'pm10', yesterday: aq.yesterdayPm10Avg),
          _pollutantRow('Ozon (O₃)', aq.ozone,
              warnAbove: 120, dangerAbove: 180, code: 'o3', yesterday: aq.yesterdayOzoneAvg),
          _pollutantRow('Stickstoffdioxid (NO₂)', aq.nitrogenDioxide,
              warnAbove: 40, dangerAbove: 200, code: 'no2'),
          if (aq.sulphurDioxide != null && aq.sulphurDioxide! > 0)
            _pollutantRow('Schwefeldioxid (SO₂)', aq.sulphurDioxide,
                warnAbove: 40, dangerAbove: 250, code: 'so2'),
          if (aq.carbonMonoxide != null && aq.carbonMonoxide! > 0)
            _pollutantRow('Kohlenmonoxid (CO)', aq.carbonMonoxide,
                warnAbove: 4000, dangerAbove: 10000, code: 'co'),
          if (aq.uvIndex != null) ...[
            const SizedBox(height: 14),
            _uvIndexBar(aq.uvIndex!),
          ],
          const SizedBox(height: 14),
          Text('Pollenflug (Körner/m³)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          if (aq.alderPollen != null || aq.birchPollen != null || aq.grassPollen != null ||
              aq.mugwortPollen != null || aq.olivePollen != null || aq.ragweedPollen != null)
            Column(
              children: [
                _pollenRow('Erle (Alder)', aq.alderPollen),
                _pollenRow('Birke', aq.birchPollen),
                _pollenRow('Gräser', aq.grassPollen),
                _pollenRow('Beifuß', aq.mugwortPollen),
                _pollenRow('Olive', aq.olivePollen),
                _pollenRow('Ambrosia (Ragweed)', aq.ragweedPollen),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Text('Keine Pollen-Daten für diesen Standort verfügbar',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            ),
          // 3-day forecast (AQI + PM peaks + active pollen). Only when the
          // API returned daily buckets we could aggregate from hourly.
          if (aq.forecast.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text('3-Tages-Vorschau',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
            const SizedBox(height: 6),
            ...aq.forecast.map(_dailyAirQualityCard),
          ],
          const SizedBox(height: 12),
          Text(
            'Daten: CAMS via Open-Meteo Air Quality API',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
          ],
        ),
      ),
    );
  }

  Color _aqiColor(double? aqi) {
    if (aqi == null) return Colors.grey;
    if (aqi <= 20) return Colors.green.shade700;
    if (aqi <= 40) return Colors.lightGreen.shade700;
    if (aqi <= 60) return Colors.amber.shade700;
    if (aqi <= 80) return Colors.orange.shade700;
    return Colors.red.shade700;
  }

  Widget _pollutantRow(String label, double? value,
      {required double warnAbove,
      required double dangerAbove,
      required String code,
      double? yesterday}) {
    final v = value;
    final color = v == null
        ? Colors.grey
        : (v >= dangerAbove
            ? Colors.red.shade700
            : (v >= warnAbove ? Colors.orange.shade700 : Colors.green.shade700));
    final ratio = v == null ? 0.0 : (v / dangerAbove).clamp(0.0, 1.0);
    return InkWell(
      onTap: () => _showPollutantInfo(code, label, v, warnAbove, dangerAbove, yesterday),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Row(
          children: [
            SizedBox(
              width: 148,
              child: Row(
                children: [
                  Flexible(child: Text(label, style: const TextStyle(fontSize: 12))),
                  const SizedBox(width: 3),
                  Icon(Icons.info_outline, size: 11, color: Colors.grey.shade500),
                ],
              ),
            ),
            Expanded(
              child: Container(
                height: 6,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: ratio,
                  child: Container(
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 70,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    v == null ? '—' : v.toStringAsFixed(1),
                    textAlign: TextAlign.right,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
                  ),
                  if (yesterday != null && v != null) _yesterdayDelta(v, yesterday),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Compact "besser/schlechter als gestern" chip below the current value.
  /// Green when today is lower (cleaner air), red when higher.
  Widget _yesterdayDelta(double today, double yesterday) {
    final delta = today - yesterday;
    if (delta.abs() < 0.5) {
      return Text('≈ gestern',
          style: TextStyle(fontSize: 9, color: Colors.grey.shade500));
    }
    final worse = delta > 0;
    final pct = yesterday > 0 ? (delta.abs() / yesterday * 100).round() : 0;
    return Text(
      '${worse ? "↑" : "↓"} ${pct > 0 ? "$pct% " : ""}vs. gestern',
      style: TextStyle(
        fontSize: 9,
        fontWeight: FontWeight.w600,
        color: worse ? Colors.red.shade600 : Colors.green.shade700,
      ),
    );
  }

  void _showPollutantInfo(String code, String label, double? value,
      double warn, double danger, double? yesterday) {
    final info = _pollutantInfoText(code);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text(info.what,
                style: const TextStyle(fontSize: 13, height: 1.35)),
            const SizedBox(height: 12),
            _bottomSheetSection('Wer sollte aufpassen',
                info.affected, Icons.person, Colors.orange.shade700),
            const SizedBox(height: 8),
            _bottomSheetSection('Empfehlung',
                info.advice, Icons.lightbulb_outline, Colors.blue.shade700),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Grenzwerte (µg/m³)',
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text('gut  <  ${warn.toStringAsFixed(0)}  <  erhöht  <  '
                      '${danger.toStringAsFixed(0)}  <  hoch',
                      style: const TextStyle(fontSize: 12)),
                  if (value != null) ...[
                    const SizedBox(height: 6),
                    Text('Aktuell: ${value.toStringAsFixed(1)} µg/m³',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                  if (yesterday != null) ...[
                    const SizedBox(height: 2),
                    Text('Ø gestern: ${yesterday.toStringAsFixed(1)} µg/m³',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottomSheetSection(String title, String body, IconData icon, Color color) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  style: TextStyle(
                      fontSize: 11, color: color, fontWeight: FontWeight.bold, letterSpacing: 0.3)),
              const SizedBox(height: 2),
              Text(body, style: const TextStyle(fontSize: 12, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  /// German-language descriptions for the six pollutants Umwelt-Tab surfaces.
  /// Sources: UBA, WHO air-quality guidelines.
  _PollutantInfo _pollutantInfoText(String code) {
    switch (code) {
      case 'pm25':
        return const _PollutantInfo(
          what: 'Feinstaub PM2.5: winzige Partikel unter 2,5 µm aus '
              'Verkehr, Heizung und Industrie. Dringt tief in die Lunge und '
              'sogar in die Blutbahn ein.',
          affected: 'Asthmatiker, COPD-Patienten, Herz-Kreislauf-Kranke, '
              'Kinder, Senioren, Schwangere.',
          advice: 'Bei erhöhten Werten: körperliche Anstrengung im Freien '
              'meiden, Fenster geschlossen halten, ggf. FFP2-Maske.',
        );
      case 'pm10':
        return const _PollutantInfo(
          what: 'Feinstaub PM10: gröbere Partikel unter 10 µm, u.a. aus '
              'Reifenabrieb und Baustellenstaub. Reizt die Atemwege.',
          affected: 'Personen mit Atemwegserkrankungen, Allergiker.',
          advice: 'Aktivitäten in verkehrsarme Gebiete verlegen. Bei '
              'Belastung > 50 µg/m³ Innenräume mit Filterlüftung bevorzugen.',
        );
      case 'o3':
        return const _PollutantInfo(
          what: 'Bodennahes Ozon (O₃) entsteht bei Sonne aus Autoabgasen. '
              'Reizt Schleimhäute und Lunge, oft nachmittags am höchsten.',
          affected: 'Asthmatiker, Kinder, Senioren, sportlich Aktive.',
          advice: 'Anstrengende Aktivitäten im Freien auf frühen Morgen '
              'oder Abend verlegen. Werte > 180 µg/m³: drinnen bleiben.',
        );
      case 'no2':
        return const _PollutantInfo(
          what: 'Stickstoffdioxid (NO₂) aus Dieselmotoren und Heizungen. '
              'Reizt Atemwege, verstärkt Asthma-Anfälle.',
          affected: 'Kinder, Asthmatiker, Anwohner an Hauptstraßen.',
          advice: 'Bei Werten > 40 µg/m³: Wege abseits verkehrsreicher '
              'Straßen wählen. Fenster zur Straße geschlossen halten.',
        );
      case 'so2':
        return const _PollutantInfo(
          what: 'Schwefeldioxid (SO₂) aus Kohle-/Ölverbrennung und '
              'Vulkantätigkeit. Reizt Schleimhäute, kann Asthma auslösen.',
          affected: 'Asthmatiker, Personen mit Herz-Lungen-Erkrankungen.',
          advice: 'In Deutschland selten hoch. Bei > 40 µg/m³ Innenräume '
              'bevorzugen und tief einatmen vermeiden.',
        );
      case 'co':
        return const _PollutantInfo(
          what: 'Kohlenmonoxid (CO) ist ein farb- und geruchloses Gas aus '
              'unvollständiger Verbrennung. Bindet an Hämoglobin und blockiert '
              'den Sauerstofftransport.',
          affected: 'Alle — besonders Herzkranke, Schwangere, Kinder.',
          advice: 'Werte im Freien sind meist unbedenklich. Innenraum-'
              'Belastung durch defekte Heizung ist gefährlich — CO-Melder!',
        );
    }
    return const _PollutantInfo(
      what: 'Keine Zusatzinfo verfügbar.',
      affected: '—',
      advice: '—',
    );
  }

  Widget _uvIndexBar(double uv) {
    final label = uv < 3 ? 'gering' : (uv < 6 ? 'mäßig' : (uv < 8 ? 'hoch' : (uv < 11 ? 'sehr hoch' : 'extrem')));
    final color = uv < 3
        ? Colors.green
        : (uv < 6 ? Colors.yellow.shade700 : (uv < 8 ? Colors.orange : (uv < 11 ? Colors.red : Colors.purple)));
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(Icons.wb_sunny, color: color, size: 22),
          const SizedBox(width: 10),
          Text('UV-Index ', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          Text(uv.toStringAsFixed(1),
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(width: 6),
          Text('($label)', style: TextStyle(fontSize: 12, color: color)),
        ],
      ),
    );
  }

  Widget _pollenRow(String name, double? count) {
    if (count == null || count <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            SizedBox(width: 140, child: Text(name, style: TextStyle(fontSize: 12, color: Colors.grey.shade500))),
            Text('—', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
          ],
        ),
      );
    }
    // Belastung: leicht <10, mittel 10-49, hoch 50+
    final level = count < 10
        ? ('gering', Colors.green.shade700)
        : (count < 50 ? ('mittel', Colors.orange.shade700) : ('hoch', Colors.red.shade700));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 140, child: Text(name, style: const TextStyle(fontSize: 12))),
          Text(count.toStringAsFixed(0), style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: level.$2)),
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: level.$2.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(level.$1, style: TextStyle(fontSize: 10, color: level.$2, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  /// One-day summary card for the 3-Tages-Vorschau in Umwelt tab.
  /// Shows AQI + peak pollutants + which pollens will be noticeable.
  Widget _dailyAirQualityCard(DailyAirQuality d) {
    const dayNames = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final now = DateTime.now();
    final isToday = d.date.day == now.day && d.date.month == now.month;
    final isTomorrow = d.date.difference(DateTime(now.year, now.month, now.day)).inDays == 1;
    final label = isToday ? 'Heute' : (isTomorrow ? 'Morgen' :
        '${dayNames[(d.date.weekday - 1) % 7]} ${d.date.day.toString().padLeft(2, '0')}.${d.date.month.toString().padLeft(2, '0')}.');
    final active = <String>[
      if ((d.alderPollenMax ?? 0) > 10) 'Erle',
      if ((d.birchPollenMax ?? 0) > 10) 'Birke',
      if ((d.grassPollenMax ?? 0) > 10) 'Gräser',
      if ((d.mugwortPollenMax ?? 0) > 10) 'Beifuß',
      if ((d.olivePollenMax ?? 0) > 10) 'Olive',
      if ((d.ragweedPollenMax ?? 0) > 10) 'Ambrosia',
    ];
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 3),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isToday ? Colors.blue.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: isToday ? Border.all(color: Colors.blue.shade200) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 55,
            child: Text(label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: isToday ? Colors.blue.shade900 : null,
                )),
          ),
          if (d.europeanAqi != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: _aqiColor(d.europeanAqi).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text('AQI ${d.europeanAqi!.toStringAsFixed(0)}',
                  style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.bold, color: _aqiColor(d.europeanAqi))),
            ),
            const SizedBox(width: 8),
          ],
          if (d.pm25Max != null)
            _dailyMiniBadge('PM2.5', d.pm25Max!, warn: 25, danger: 50),
          if (d.ozoneMax != null) ...[
            const SizedBox(width: 4),
            _dailyMiniBadge('O₃', d.ozoneMax!, warn: 120, danger: 180),
          ],
          const Spacer(),
          if (active.isNotEmpty)
            Flexible(
              child: Text(
                '🌾 ${active.join(", ")}',
                style: TextStyle(fontSize: 10, color: Colors.orange.shade900),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
              ),
            )
          else
            Text('Pollen ruhig',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
        ],
      ),
    );
  }

  Widget _dailyMiniBadge(String label, double value,
      {required double warn, required double danger}) {
    final color = value >= danger
        ? Colors.red.shade700
        : (value >= warn ? Colors.orange.shade700 : Colors.green.shade700);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text('$label ${value.toStringAsFixed(0)}',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: color)),
    );
  }

  Color _alertColor(String severity) {
    switch (severity) {
      case 'extreme':
        return Colors.red.shade800;
      case 'severe':
        return Colors.orange.shade700;
      case 'moderate':
        return Colors.amber.shade700;
      default:
        return Colors.yellow.shade700;
    }
  }
}

/// Stündlich tab with a `ScrollController` so we can jump to the "jetzt" row
/// on first paint. Also injects sunrise/sunset markers between rows and
/// midnight separators so a 24 h list stays readable when it crosses days.
class _StuendlichView extends StatefulWidget {
  final List<HourlyForecast> next24h;
  final DateFormat df;

  const _StuendlichView({required this.next24h, required this.df});

  @override
  State<_StuendlichView> createState() => _StuendlichViewState();
}

class _StuendlichViewState extends State<_StuendlichView> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.next24h.isEmpty) {
      return const Center(child: Text('Keine stündlichen Daten verfügbar'));
    }
    final now = DateTime.now();
    // Build interleaved rows: hours + sunrise/sunset markers + midnight bars.
    final rows = <_HourRow>[];
    final sunrise = _findAncestorAstronomy(context)?.sunrise;
    final sunset = _findAncestorAstronomy(context)?.sunset;
    int nowRowIndex = -1;

    DateTime? lastTime;
    for (int i = 0; i < widget.next24h.length; i++) {
      final h = widget.next24h[i];
      final isNow = !h.time.isAfter(now) &&
          h.time.add(const Duration(hours: 1)).isAfter(now);
      if (isNow && nowRowIndex < 0) nowRowIndex = rows.length;
      // Sunrise/sunset between last hour and this hour → inject marker.
      if (lastTime != null) {
        if (sunrise != null &&
            sunrise.isAfter(lastTime) &&
            !sunrise.isAfter(h.time)) {
          rows.add(_HourRow.sunEvent(time: sunrise, isSunrise: true));
        }
        if (sunset != null &&
            sunset.isAfter(lastTime) &&
            !sunset.isAfter(h.time)) {
          rows.add(_HourRow.sunEvent(time: sunset, isSunrise: false));
        }
        // Day change → midnight separator.
        if (h.time.day != lastTime.day) {
          rows.add(_HourRow.dayBreak(time: h.time));
        }
      }
      rows.add(_HourRow.hour(h: h, isNow: isNow));
      lastTime = h.time;
    }

    // Scroll to "jetzt" once we know the layout. Approx row height 42 px.
    if (nowRowIndex > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scroll.hasClients) return;
        final target = (nowRowIndex * 42.0 - 40)
            .clamp(0.0, _scroll.position.maxScrollExtent);
        _scroll.jumpTo(target);
      });
    }

    // Sticky sparkline header — temperature line + precipitation-probability
    // bars for the next 24 h. Compact overview above the detailed list.
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: _HourlySparkline(hours: widget.next24h),
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: rows.length,
            itemBuilder: (_, i) => _renderRow(rows[i], i),
          ),
        ),
      ],
    );
  }

  AstronomyData? _findAncestorAstronomy(BuildContext ctx) {
    // Walk up the widget tree to grab the shared WeatherService via the
    // enclosing _WeatherDialogState. Cheaper than plumbing another prop.
    final state = ctx.findAncestorStateOfType<_WeatherDialogState>();
    return state?.widget.service.currentAstronomy;
  }

  Widget _renderRow(_HourRow row, int idx) {
    if (row.type == _HourRowType.sunrise || row.type == _HourRowType.sunset) {
      final isSunrise = row.type == _HourRowType.sunrise;
      final color = isSunrise ? Colors.orange.shade700 : Colors.deepOrange.shade800;
      return Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withValues(alpha: 0.08),
            color.withValues(alpha: 0.02),
          ]),
          borderRadius: BorderRadius.circular(4),
          border: Border(left: BorderSide(color: color, width: 2)),
        ),
        child: Row(
          children: [
            Text(isSunrise ? '🌅' : '🌇',
                style: _emojiStyle(fontSize: 15)),
            const SizedBox(width: 8),
            Text(
              isSunrise ? 'Sonnenaufgang' : 'Sonnenuntergang',
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.bold),
            ),
            const Spacer(),
            Text(
              DateFormat('HH:mm', 'de_DE').format(row.time!),
              style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    if (row.type == _HourRowType.dayBreak) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: [
            Expanded(child: Divider(color: Colors.grey.shade400)),
            const SizedBox(width: 8),
            Text(
              DateFormat('EEEE, dd.MM.', 'de_DE').format(row.time!),
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700),
            ),
            const SizedBox(width: 8),
            Expanded(child: Divider(color: Colors.grey.shade400)),
          ],
        ),
      );
    }
    // Hour row.
    final h = row.h!;
    final isNow = row.isNow;
    return GestureDetector(
      onLongPress: () {
        final state = context.findAncestorStateOfType<_WeatherDialogState>();
        state?.showForecastDetailSheet(
          context: context,
          time: h.time,
          weatherCode: h.weatherCode,
          emoji: h.icon,
          description: h.description,
          temperature: h.temperature,
          windSpeed: h.windSpeed,
          humidity: h.humidity,
          precipitation: h.precipitation,
          precipitationProbability: h.precipitationProbability,
        );
      },
      child: Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isNow ? Colors.blue.shade50 : (idx.isEven ? Colors.grey.shade50 : null),
        borderRadius: BorderRadius.circular(6),
        border: isNow ? Border.all(color: Colors.blue.shade200) : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 45,
            child: Text(
              widget.df.format(h.time),
              style: TextStyle(
                fontSize: 13,
                fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                color: isNow ? Colors.blue.shade800 : null,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(h.icon, style: _emojiStyle(fontSize: 18)),
          const SizedBox(width: 10),
          SizedBox(
            width: 50,
            child: Text(
              '${h.temperature.toStringAsFixed(1)}°',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: h.temperature < 0 ? Colors.blue.shade800 : Colors.orange.shade800,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.air, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 2),
          SizedBox(
            width: 55,
            child: Text(
              '${h.windSpeed.toStringAsFixed(0)} km/h',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ),
          if (h.precipitation > 0) ...[
            Icon(Icons.water_drop, size: 14, color: Colors.blue.shade400),
            const SizedBox(width: 2),
            Text(
              '${h.precipitation.toStringAsFixed(1)} mm',
              style: TextStyle(fontSize: 11, color: Colors.blue.shade600),
            ),
          ],
          if ((h.precipitationProbability ?? 0) >= 10) ...[
            const SizedBox(width: 6),
            Icon(Icons.umbrella, size: 12, color: Colors.blue.shade300),
            const SizedBox(width: 1),
            Text(
              '${h.precipitationProbability}%',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: (h.precipitationProbability ?? 0) >= 70
                    ? Colors.blue.shade900
                    : Colors.blue.shade600,
              ),
            ),
          ],
          const Spacer(),
          SizedBox(
            width: 90,
            child: Text(
              h.description,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    ),
    );
  }
}

enum _HourRowType { hour, sunrise, sunset, dayBreak }

class _HourRow {
  final _HourRowType type;
  final HourlyForecast? h;
  final DateTime? time;
  final bool isNow;

  const _HourRow._({required this.type, this.h, this.time, this.isNow = false});

  factory _HourRow.hour({required HourlyForecast h, required bool isNow}) =>
      _HourRow._(type: _HourRowType.hour, h: h, isNow: isNow);
  factory _HourRow.sunEvent({required DateTime time, required bool isSunrise}) =>
      _HourRow._(type: isSunrise ? _HourRowType.sunrise : _HourRowType.sunset, time: time);
  factory _HourRow.dayBreak({required DateTime time}) =>
      _HourRow._(type: _HourRowType.dayBreak, time: time);
}

/// Horizontal 15-min timeline (wetter.com-style). Scrollable.
/// Each cell: HH:mm • weather emoji • temperature • precip probability • precipitation bar.
/// The current cell (the one containing "now") is highlighted with a blue border.
///
/// Public — reused as a sticky bar under the dashboard AppBar so the user sees
/// the next hours' forecast without opening the dialog.
/// Compact 24 h chart: temperature line (orange) over precipitation-probability
/// bars (blue). Zero-dependency CustomPainter, sized to fit above the hour list.
class _HourlySparkline extends StatelessWidget {
  final List<HourlyForecast> hours;

  const _HourlySparkline({required this.hours});

  @override
  Widget build(BuildContext context) {
    if (hours.length < 2) return const SizedBox.shrink();
    return Container(
      height: 80,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          Row(children: [
            Icon(Icons.show_chart, size: 12, color: Colors.orange.shade700),
            const SizedBox(width: 4),
            Text('24-Stunden-Trend',
                style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700)),
            const Spacer(),
            Container(width: 8, height: 8, color: Colors.orange.shade700),
            const SizedBox(width: 3),
            Text('°C',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
            const SizedBox(width: 8),
            Container(width: 8, height: 8, color: Colors.blue.shade400),
            const SizedBox(width: 3),
            Text('% Regen',
                style: TextStyle(fontSize: 9, color: Colors.grey.shade600)),
          ]),
          const SizedBox(height: 2),
          Expanded(
            child: LayoutBuilder(builder: (_, c) {
              return CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _HourlySparklinePainter(hours: hours),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HourlySparklinePainter extends CustomPainter {
  final List<HourlyForecast> hours;
  _HourlySparklinePainter({required this.hours});

  @override
  void paint(Canvas canvas, Size size) {
    if (hours.length < 2) return;
    double minT = hours.map((h) => h.temperature).reduce((a, b) => a < b ? a : b);
    double maxT = hours.map((h) => h.temperature).reduce((a, b) => a > b ? a : b);
    if ((maxT - minT).abs() < 2) { maxT += 1; minT -= 1; } // avoid flat line
    final rangeT = maxT - minT;
    final step = size.width / (hours.length - 1);

    // Precip probability bars along the bottom third.
    final barTop = size.height * 0.55;
    final barMaxH = size.height - barTop;
    for (int i = 0; i < hours.length; i++) {
      final p = hours[i].precipitationProbability ?? 0;
      if (p <= 0) continue;
      final h = barMaxH * (p / 100).clamp(0.0, 1.0);
      canvas.drawRect(
        Rect.fromLTWH(i * step - step * 0.35, size.height - h, step * 0.7, h),
        Paint()..color = Colors.blue.shade400.withValues(alpha: 0.55),
      );
    }

    // Temperature polyline.
    final tempPath = ui.Path();
    final tempPts = <Offset>[];
    for (int i = 0; i < hours.length; i++) {
      final x = i * step;
      final y = (barTop - 4) * (1 - (hours[i].temperature - minT) / rangeT);
      tempPts.add(Offset(x, y));
    }
    tempPath.moveTo(tempPts.first.dx, tempPts.first.dy);
    for (int i = 1; i < tempPts.length; i++) {
      tempPath.lineTo(tempPts[i].dx, tempPts[i].dy);
    }
    canvas.drawPath(
      tempPath,
      Paint()
        ..color = Colors.orange.shade700
        ..strokeWidth = 1.8
        ..style = PaintingStyle.stroke,
    );

    // Small dots on the temperature line to hint at hour granularity.
    final dotPaint = Paint()..color = Colors.orange.shade700;
    for (final p in tempPts) {
      canvas.drawCircle(p, 1.5, dotPaint);
    }

    // Label min/max temp for context.
    _drawText(canvas, '${maxT.toStringAsFixed(0)}°',
        const Offset(0, 0), 9, Colors.orange.shade900);
    _drawText(canvas, '${minT.toStringAsFixed(0)}°',
        Offset(0, barTop - 12), 9, Colors.orange.shade900);
  }

  void _drawText(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color)),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_HourlySparklinePainter old) => old.hours != hours;
}

class WeatherMinutelyBar extends StatelessWidget {
  final List<MinutelyForecast> entries;
  final VoidCallback? onTap;

  /// [compact] = true → shorter cells (no mm-bar), suitable for the sticky
  /// dashboard header. `false` = full detail for the in-dialog timeline.
  final bool compact;

  const WeatherMinutelyBar({
    super.key,
    required this.entries,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final bar = _MinutelyTimeline(entries: entries, compact: compact);
    if (onTap == null) return bar;
    return InkWell(onTap: onTap, child: bar);
  }
}

class _MinutelyTimeline extends StatefulWidget {
  final List<MinutelyForecast> entries;
  final bool compact;

  const _MinutelyTimeline({required this.entries, this.compact = false});

  @override
  State<_MinutelyTimeline> createState() => _MinutelyTimelineState();
}

class _MinutelyTimelineState extends State<_MinutelyTimeline> {
  final _scroll = ScrollController();
  static const _cellWidth = 48.0; // 46 px + 2 px horizontal margin

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scroll so the "jetzt" cell lands ~one cell in from the left edge.
  void _scrollToNow(int currentIdx) {
    if (!_scroll.hasClients) return;
    final target = ((currentIdx - 1) * _cellWidth).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.jumpTo(target);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.entries.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    // Only future/current slots (drop stale rows if the API returned them).
    final visible = widget.entries
        .where((e) => !e.time.isBefore(now.subtract(const Duration(minutes: 15))))
        .toList();

    // Find index of the "now" cell so we can scroll to it on first frame.
    final nowIdx = visible.indexWhere((e) =>
        !e.time.isAfter(now) && e.time.add(const Duration(minutes: 15)).isAfter(now));
    if (nowIdx > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToNow(nowIdx));
    }

    final compact = widget.compact;
    // Max precipitation for bar normalization — 2 mm/15min is heavy rain.
    final maxPrecip = visible.fold<double>(
      2.0,
      (m, e) => e.precipitation > m ? e.precipitation : m,
    );

    return Container(
      height: compact ? 78 : 115,
      decoration: BoxDecoration(
        color: compact
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.blue.shade50.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(8),
        border: compact ? null : Border.all(color: Colors.blue.shade100),
      ),
      child: ListView.builder(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        itemCount: visible.length,
        itemBuilder: (_, i) {
          final e = visible[i];
          final isCurrent = !e.time.isAfter(now) &&
              e.time.add(const Duration(minutes: 15)).isAfter(now);
          final label = isCurrent
              ? 'jetzt'
              : '${e.time.hour.toString().padLeft(2, '0')}:${e.time.minute.toString().padLeft(2, '0')}';

          final precipHeight = maxPrecip > 0
              ? (e.precipitation / maxPrecip * 18).clamp(0.0, 18.0)
              : 0.0;

          // Compact cells drop the mm-bar (used in dashboard sticky header).
          final labelColor = compact
              ? (isCurrent ? Colors.amber.shade200 : Colors.white70)
              : (isCurrent ? Colors.blue.shade900 : Colors.grey.shade700);
          final tempColor = compact
              ? (e.temperature < 0 ? Colors.lightBlue.shade200 : Colors.orange.shade200)
              : (e.temperature < 0 ? Colors.blue.shade800 : Colors.orange.shade800);
          final activeBg = compact
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.blue.shade100.withValues(alpha: 0.6);
          final activeBorder = compact ? Colors.amber.shade300 : Colors.blue.shade400;

          return Container(
            width: 46,
            margin: const EdgeInsets.symmetric(horizontal: 1),
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: isCurrent ? activeBg : null,
              borderRadius: BorderRadius.circular(6),
              border: isCurrent ? Border.all(color: activeBorder, width: 1.5) : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                    color: labelColor,
                  ),
                ),
                Text(e.icon, style: _emojiStyle(fontSize: 18)),
                Text(
                  '${e.temperature.toStringAsFixed(0)}°',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: tempColor,
                  ),
                ),
                // Precipitation probability (% chance of rain) — shown when ≥20% or when it's raining.
                SizedBox(
                  height: 12,
                  child: (e.precipitationProbability != null &&
                          (e.precipitationProbability! >= 20 || e.precipitation > 0))
                      ? Text(
                          '${e.precipitationProbability}%',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: compact
                                ? Colors.lightBlue.shade200
                                : (e.precipitationProbability! >= 70
                                    ? Colors.blue.shade900
                                    : (e.precipitationProbability! >= 40
                                        ? Colors.blue.shade700
                                        : Colors.blue.shade400)),
                          ),
                        )
                      : null,
                ),
                // Precipitation bar — full detail only; compact drops this row.
                if (!compact)
                  SizedBox(
                    height: 20,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (e.precipitation > 0)
                          Container(
                            width: 12,
                            height: precipHeight,
                            decoration: BoxDecoration(
                              color: Colors.blue.shade400,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        if (e.precipitation > 0)
                          Text(
                            e.precipitation < 0.1
                                ? '<0.1'
                                : e.precipitation.toStringAsFixed(1),
                            style: TextStyle(fontSize: 8, color: Colors.blue.shade700),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Sticky banner in the dashboard header for locally-generated
/// vulnerability warnings (heat, cold, UV, PM2.5, ozone). Each banner has
/// its own colour by severity/kind. Tap the "Verstanden" button to
/// acknowledge — the alert won't re-appear until tomorrow.
///
/// Renders as a Column of banners (one per active alert). If the alert list
/// is empty, the widget takes zero space so the dashboard layout is unaffected.
class HealthAlertBanner extends StatelessWidget {
  final List<HealthAlert> alerts;
  final void Function(HealthAlert) onAcknowledge;
  final void Function(HealthAlert)? onTap;

  const HealthAlertBanner({
    super.key,
    required this.alerts,
    required this.onAcknowledge,
    this.onTap,
  });

  Color _color(HealthAlert a) {
    final base = switch (a.kind) {
      HealthAlertKind.heat => Colors.deepOrange,
      HealthAlertKind.cold => Colors.lightBlue,
      HealthAlertKind.uv => Colors.amber,
      HealthAlertKind.pm25 => Colors.brown,
      HealthAlertKind.ozone => Colors.purple,
      HealthAlertKind.pollen => Colors.green,
    };
    return a.severity == 'severe' ? base.shade900 : base.shade700;
  }

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: alerts.map((a) {
        final c = _color(a);
        return Material(
          color: c,
          child: InkWell(
            onTap: onTap == null ? null : () => onTap!(a),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(a.icon, style: _emojiStyle(fontSize: 26)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Text(
                              a.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 6),
                            if (a.severity == 'severe')
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.25),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  'AKUT',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          a.body,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          a.recommendation,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.85),
                            height: 1.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton(
                        onPressed: () => onAcknowledge(a),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: c,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        ),
                        child: const Text(
                          'OK',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text('Verstanden',
                          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}

/// 7-day trend visualisation: two temperature lines (max/min) with a filled
/// gradient in between, and blue precipitation bars underneath. Zero external
/// dependencies — everything drawn with CustomPainter so we don't drag in a
/// charts package (and its version conflicts).
class _WeeklyTrendChart extends StatelessWidget {
  final List<DailyForecast> week;
  final DateTime today;

  const _WeeklyTrendChart({required this.week, required this.today});

  @override
  Widget build(BuildContext context) {
    if (week.isEmpty) return const SizedBox.shrink();
    final dfShort = DateFormat('E', 'de_DE');
    // Compute the shared temperature range so both lines share the same scale.
    double minT = week.map((d) => d.tempMin).reduce((a, b) => a < b ? a : b);
    double maxT = week.map((d) => d.tempMax).reduce((a, b) => a > b ? a : b);
    // Pad the range so the lines don't hug the frame edges.
    minT = (minT - 3).floorToDouble();
    maxT = (maxT + 3).ceilToDouble();
    double maxPrecip = week.map((d) => d.precipitationSum).fold(0, (a, b) => a > b ? a : b);
    if (maxPrecip < 2) maxPrecip = 2;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.show_chart, size: 16, color: Colors.grey.shade700),
              const SizedBox(width: 6),
              Text('7-Tage-Trend',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade800)),
              const Spacer(),
              _legendDot(Colors.orange.shade700, 'Max'),
              const SizedBox(width: 6),
              _legendDot(Colors.blue.shade700, 'Min'),
              const SizedBox(width: 6),
              _legendDot(Colors.blue.shade300, 'Regen'),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 150,
            child: LayoutBuilder(builder: (context, constraints) {
              return CustomPaint(
                size: Size(constraints.maxWidth, 150),
                painter: _WeeklyTrendPainter(
                  week: week,
                  today: today,
                  minT: minT,
                  maxT: maxT,
                  maxPrecip: maxPrecip,
                ),
              );
            }),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: week.map((d) {
              final isToday = d.date.day == today.day && d.date.month == today.month;
              return Text(
                isToday ? 'Heu.' : dfShort.format(d.date),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                  color: isToday ? Colors.blue.shade900 : Colors.grey.shade700,
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 3),
      Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
    ]);
  }
}

class _WeeklyTrendPainter extends CustomPainter {
  final List<DailyForecast> week;
  final DateTime today;
  final double minT;
  final double maxT;
  final double maxPrecip;

  _WeeklyTrendPainter({
    required this.week,
    required this.today,
    required this.minT,
    required this.maxT,
    required this.maxPrecip,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (week.isEmpty) return;
    // Split canvas: top 70% for temperature lines, bottom 30% for precip bars.
    final tempH = size.height * 0.72;
    final precipH = size.height - tempH - 4;

    final xStep = size.width / (week.length - 1).clamp(1, 100);

    // Grid lines behind the plot area — 4 horizontal gridlines.
    final gridPaint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 0.5;
    for (int i = 0; i <= 3; i++) {
      final y = tempH * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    // Y-axis temp labels on the left (min at bottom, max at top).
    final rangeT = maxT - minT;
    for (int i = 0; i <= 3; i++) {
      final t = maxT - rangeT * i / 3;
      final y = tempH * i / 3;
      _drawText(canvas, '${t.toStringAsFixed(0)}°',
          Offset(2, y - 6), 9, Colors.grey.shade600);
    }

    // Points for the two lines.
    final maxPts = <Offset>[];
    final minPts = <Offset>[];
    for (int i = 0; i < week.length; i++) {
      final d = week[i];
      final x = i * xStep;
      final yMax = tempH * (maxT - d.tempMax) / rangeT;
      final yMin = tempH * (maxT - d.tempMin) / rangeT;
      maxPts.add(Offset(x, yMax));
      minPts.add(Offset(x, yMin));
    }

    // Gradient shading between min and max lines.
    final fillPath = ui.Path()..moveTo(maxPts.first.dx, maxPts.first.dy);
    for (final p in maxPts) { fillPath.lineTo(p.dx, p.dy); }
    for (final p in minPts.reversed) { fillPath.lineTo(p.dx, p.dy); }
    fillPath.close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.orange.shade200.withValues(alpha: 0.4),
            Colors.blue.shade200.withValues(alpha: 0.4),
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, tempH)),
    );

    // Max line (orange).
    final maxLinePaint = Paint()
      ..color = Colors.orange.shade700
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    _drawPolyline(canvas, maxPts, maxLinePaint);

    // Min line (blue).
    final minLinePaint = Paint()
      ..color = Colors.blue.shade700
      ..strokeWidth = 2.2
      ..style = PaintingStyle.stroke;
    _drawPolyline(canvas, minPts, minLinePaint);

    // Point markers + inline value labels.
    for (int i = 0; i < week.length; i++) {
      canvas.drawCircle(maxPts[i], 3, Paint()..color = Colors.orange.shade700);
      canvas.drawCircle(minPts[i], 3, Paint()..color = Colors.blue.shade700);
      _drawText(
        canvas,
        '${week[i].tempMax.toStringAsFixed(0)}°',
        Offset(maxPts[i].dx - 8, maxPts[i].dy - 15),
        10, Colors.orange.shade800, bold: true,
      );
      _drawText(
        canvas,
        '${week[i].tempMin.toStringAsFixed(0)}°',
        Offset(minPts[i].dx - 8, minPts[i].dy + 4),
        10, Colors.blue.shade800, bold: true,
      );
    }

    // "Today" vertical guide.
    for (int i = 0; i < week.length; i++) {
      if (week[i].date.day == today.day && week[i].date.month == today.month) {
        final x = i * xStep;
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, size.height),
          Paint()
            ..color = Colors.blue.shade900.withValues(alpha: 0.3)
            ..strokeWidth = 1
            ..strokeCap = StrokeCap.round,
        );
        break;
      }
    }

    // Precipitation bars along the bottom band.
    final precipTop = tempH + 4;
    for (int i = 0; i < week.length; i++) {
      final d = week[i];
      if (d.precipitationSum <= 0) continue;
      final barX = i * xStep - 8;
      final ratio = (d.precipitationSum / maxPrecip).clamp(0.0, 1.0);
      final h = precipH * ratio;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barX, precipTop + (precipH - h), 16, h),
          const Radius.circular(3),
        ),
        Paint()..color = Colors.blue.shade400,
      );
      _drawText(
        canvas,
        d.precipitationSum.toStringAsFixed(0),
        Offset(barX + 2, precipTop + precipH - h - 12),
        8, Colors.blue.shade800,
      );
    }
  }

  void _drawPolyline(Canvas canvas, List<Offset> pts, Paint paint) {
    if (pts.length < 2) return;
    final path = ui.Path()..moveTo(pts.first.dx, pts.first.dy);
    for (int i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    canvas.drawPath(path, paint);
  }

  void _drawText(Canvas canvas, String text, Offset at, double size, Color color,
      {bool bold = false}) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size,
          color: color,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(covariant _WeeklyTrendPainter old) =>
      old.week != week || old.today != today ||
      old.minT != minT || old.maxT != maxT || old.maxPrecip != maxPrecip;
}

/// Compare the current 7-day forecast against the same calendar week in the
/// last 3 years. Data comes from [WeatherHistoryService] (cached forever, since
/// historical daily numbers don't change).
class _HistoricalComparisonCard extends StatelessWidget {
  final List<DailyForecast> current;
  final List<HistoricalWeekSummary>? history;
  final bool isLoading;

  const _HistoricalComparisonCard({
    required this.current,
    required this.history,
    required this.isLoading,
  });

  @override
  Widget build(BuildContext context) {
    if (isLoading && history == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(children: [
          const SizedBox(
            width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 10),
          Text('Historische Daten laden…',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
        ]),
      );
    }
    if (history == null || history!.isEmpty) return const SizedBox.shrink();

    // Aggregate current week values.
    final curMax = current.map((d) => d.tempMax).reduce((a, b) => a + b) / current.length;
    final curMin = current.map((d) => d.tempMin).reduce((a, b) => a + b) / current.length;
    final curRain = current.map((d) => d.precipitationSum).reduce((a, b) => a + b);

    // 3-Jahres-Durchschnitt.
    final histAvgMaxs = history!.map((h) => h.avgTempMax).whereType<double>().toList();
    final histAvgMax = histAvgMaxs.isEmpty
        ? null
        : histAvgMaxs.reduce((a, b) => a + b) / histAvgMaxs.length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.indigo.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.indigo.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, size: 16, color: Colors.indigo.shade700),
              const SizedBox(width: 6),
              Text(
                'Vergleich mit den letzten ${history!.length} Jahren',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.bold, color: Colors.indigo.shade900),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Multi-year overlay chart — only when history entries have per-day
          // arrays populated (v2+ cache). Falls back to the numeric table
          // gracefully when older cache entries exist.
          if (_HistoricalComparisonCard._anyHistoryHasDailies(history!)) ...[
            _MultiYearChart(current: current, history: history!),
            const SizedBox(height: 8),
          ],
          _row(
            label: 'Diese Woche',
            valueTop: 'Ø max ${curMax.toStringAsFixed(1)}°C',
            valueBottom: 'Ø min ${curMin.toStringAsFixed(1)}°C · ${curRain.toStringAsFixed(0)} mm Regen',
            color: Colors.indigo.shade900,
            highlight: true,
          ),
          const Divider(height: 12),
          for (final h in history!) ...[
            _row(
              label: _labelForYear(h.yearsAgo, h.start),
              valueTop: h.avgTempMax != null
                  ? 'Ø max ${h.avgTempMax!.toStringAsFixed(1)}°C'
                  : '—',
              valueBottom: 'Ø min ${h.avgTempMin?.toStringAsFixed(1) ?? "—"}°C · '
                  '${h.totalPrecipitation?.toStringAsFixed(0) ?? "?"} mm Regen',
              color: Colors.grey.shade800,
              highlight: false,
            ),
            const SizedBox(height: 4),
          ],
          if (histAvgMax != null) ...[
            const SizedBox(height: 4),
            _deltaSummary(curMax, histAvgMax),
          ],
        ],
      ),
    );
  }

  String _labelForYear(int yearsAgo, DateTime start) {
    final months = [
      'Januar','Februar','März','April','Mai','Juni',
      'Juli','August','September','Oktober','November','Dezember',
    ];
    final monthLabel = months[start.month - 1];
    return 'Vor ${yearsAgo == 1 ? "1 Jahr" : "$yearsAgo Jahren"} '
        '(${monthLabel} ${start.year})';
  }

  static bool _anyHistoryHasDailies(List<HistoricalWeekSummary> h) =>
      h.any((e) => e.dailyTempMax.isNotEmpty);

  Widget _row({
    required String label,
    required String valueTop,
    required String valueBottom,
    required Color color,
    required bool highlight,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 4,
          child: Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                color: color,
              )),
        ),
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(valueTop,
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: highlight ? FontWeight.bold : FontWeight.w500,
                      color: color)),
              Text(valueBottom,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _deltaSummary(double curMax, double histAvgMax) {
    final delta = curMax - histAvgMax;
    final absDelta = delta.abs();
    if (absDelta < 0.5) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          '💡 Diese Woche entspricht dem ${history!.length}-Jahres-Durchschnitt',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
        ),
      );
    }
    final warmer = delta > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: warmer ? Colors.orange.shade100 : Colors.blue.shade100,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '💡 Diese Woche ${absDelta.toStringAsFixed(1)} °C '
        '${warmer ? "wärmer" : "kälter"} als der '
        '${history!.length}-Jahres-Durchschnitt',
        style: TextStyle(
            fontSize: 11,
            color: warmer ? Colors.orange.shade900 : Colors.blue.shade900,
            fontWeight: FontWeight.w600),
      ),
    );
  }
}

/// Multi-year overlay chart — draws the max-temperature line for the current
/// week alongside the same 7 dates in the last 3 years. Uses opacity ramp
/// (current bold, older years progressively faded) instead of distinct hues
/// to keep the chart readable at small dialog sizes.
class _MultiYearChart extends StatelessWidget {
  final List<DailyForecast> current;
  final List<HistoricalWeekSummary> history;

  const _MultiYearChart({required this.current, required this.history});

  @override
  Widget build(BuildContext context) {
    // Collect all four year-series' max temps to pick a shared Y-range.
    final all = <double>[];
    for (final d in current) { all.add(d.tempMax); }
    for (final h in history) {
      all.addAll(h.dailyTempMax.whereType<double>());
    }
    if (all.length < 4) return const SizedBox.shrink();
    double minT = all.reduce((a, b) => a < b ? a : b);
    double maxT = all.reduce((a, b) => a > b ? a : b);
    minT = (minT - 2).floorToDouble();
    maxT = (maxT + 2).ceilToDouble();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.indigo.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.timeline, size: 14, color: Colors.indigo.shade700),
              const SizedBox(width: 4),
              Text('Max-Temperatur im Jahresvergleich',
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.indigo.shade900)),
              const Spacer(),
              _legendChip(Colors.orange.shade900, 'Jetzt'),
              const SizedBox(width: 4),
              for (int i = 1; i <= history.length; i++) ...[
                _legendChip(
                  Colors.deepOrange.withValues(alpha: 1 - i * 0.22),
                  '-$i J.',
                ),
                const SizedBox(width: 4),
              ],
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 110,
            child: LayoutBuilder(builder: (_, c) {
              return CustomPaint(
                size: Size(c.maxWidth, c.maxHeight),
                painter: _MultiYearPainter(
                  current: current.map((d) => d.tempMax).toList(),
                  history: history,
                  minT: minT,
                  maxT: maxT,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _legendChip(Color color, String label) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
          width: 8,
          height: 3,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1))),
      const SizedBox(width: 2),
      Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade700)),
    ]);
  }
}

class _MultiYearPainter extends CustomPainter {
  final List<double> current;
  final List<HistoricalWeekSummary> history;
  final double minT;
  final double maxT;

  _MultiYearPainter({
    required this.current,
    required this.history,
    required this.minT,
    required this.maxT,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (current.length < 2) return;
    final rangeT = maxT - minT;
    final xStep = size.width / (current.length - 1);

    // Grid lines.
    final gridPaint = Paint()..color = Colors.grey.shade200..strokeWidth = 0.5;
    for (int i = 0; i <= 3; i++) {
      final y = size.height * i / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
      final t = maxT - rangeT * i / 3;
      _drawText(canvas, '${t.toStringAsFixed(0)}°',
          Offset(2, y - 6), 9, Colors.grey.shade500);
    }

    // Historical lines — draw oldest first so newest sits on top.
    final sortedHistory = [...history]
      ..sort((a, b) => b.yearsAgo.compareTo(a.yearsAgo));
    for (final h in sortedHistory) {
      if (h.dailyTempMax.isEmpty) continue;
      final alpha = (1 - h.yearsAgo * 0.22).clamp(0.2, 1.0);
      _drawSeries(
        canvas,
        h.dailyTempMax,
        Colors.deepOrange.withValues(alpha: alpha),
        1.4,
        xStep,
        size.height,
        rangeT,
      );
    }
    // Current-week line — thickest, on top.
    _drawSeries(
      canvas,
      current.map((v) => v as double?).toList(),
      Colors.orange.shade900,
      2.5,
      xStep,
      size.height,
      rangeT,
    );
  }

  void _drawSeries(
    Canvas canvas,
    List<double?> values,
    Color color,
    double stroke,
    double xStep,
    double height,
    double rangeT,
  ) {
    final path = ui.Path();
    bool started = false;
    for (int i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final x = i * xStep;
      final y = height * (1 - (v - minT) / rangeT);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 2, Paint()..color = color);
    }
    if (started) {
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = stroke
          ..style = PaintingStyle.stroke,
      );
    }
  }

  void _drawText(Canvas canvas, String text, Offset at, double size, Color color) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: size, color: color)),
      textDirection: ui.TextDirection.ltr,
    );
    tp.layout();
    tp.paint(canvas, at);
  }

  @override
  bool shouldRepaint(_MultiYearPainter old) =>
      old.current != current || old.history != history ||
      old.minT != minT || old.maxT != maxT;
}

/// Rain radar overlay backed by RainViewer's free API and OpenStreetMap tiles.
///
/// RainViewer publishes an animated tile pyramid updated every ~10 min covering
/// the past ~2h; there is no per-user key. We fetch the frame index once, then
/// let the user scrub through it with a slider (or auto-play). No animation
/// loop by default so idle dialogs don't burn tile fetches.
class _RainRadarView extends StatefulWidget {
  final double centerLat;
  final double centerLon;
  final bool autoPlay;

  const _RainRadarView({
    required this.centerLat,
    required this.centerLon,
    this.autoPlay = false,
  });

  @override
  State<_RainRadarView> createState() => _RainRadarViewState();
}

class _RainRadarViewState extends State<_RainRadarView> {
  List<_RadarFrame> _frames = [];
  int _currentFrameIndex = 0;
  bool _loading = true;
  String? _error;
  bool _playing = false;
  Timer? _playTimer;
  final _mapController = MapController();

  @override
  void initState() {
    super.initState();
    _loadFrames();
  }

  @override
  void dispose() {
    _playTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _loadFrames() async {
    try {
      final r = await http
          .get(Uri.parse('https://api.rainviewer.com/public/weather-maps.json'))
          .timeout(const Duration(seconds: 10));
      if (r.statusCode != 200) {
        setState(() { _loading = false; _error = 'Radar-Daten nicht erreichbar.'; });
        return;
      }
      final data = jsonDecode(r.body);
      final host = data['host'] as String? ?? 'https://tilecache.rainviewer.com';
      final radar = data['radar'] as Map<String, dynamic>?;
      final past = (radar?['past'] as List?) ?? const [];
      final nowcast = (radar?['nowcast'] as List?) ?? const [];
      final frames = <_RadarFrame>[
        for (final f in past)
          _RadarFrame(
            time: DateTime.fromMillisecondsSinceEpoch((f['time'] as int) * 1000),
            path: '$host${f['path']}',
            isForecast: false,
          ),
        for (final f in nowcast)
          _RadarFrame(
            time: DateTime.fromMillisecondsSinceEpoch((f['time'] as int) * 1000),
            path: '$host${f['path']}',
            isForecast: true,
          ),
      ];
      if (!mounted) return;
      setState(() {
        _frames = frames;
        _currentFrameIndex = frames.length - 1; // start on the most recent frame
        _loading = false;
        _error = frames.isEmpty ? 'Keine Radar-Frames verfügbar.' : null;
      });
      // Auto-play if the caller flagged incoming precipitation — restart from
      // the oldest frame so the user actually sees the front approaching.
      if (widget.autoPlay && frames.isNotEmpty && mounted) {
        setState(() => _currentFrameIndex = 0);
        _togglePlay();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _error = 'Radar-Fehler: $e'; });
    }
  }

  void _togglePlay() {
    if (_frames.isEmpty) return;
    if (_playing) {
      _playTimer?.cancel();
      _playTimer = null;
      setState(() => _playing = false);
      return;
    }
    setState(() => _playing = true);
    _playTimer = Timer.periodic(const Duration(milliseconds: 550), (_) {
      if (!mounted || _frames.isEmpty) return;
      setState(() {
        _currentFrameIndex = (_currentFrameIndex + 1) % _frames.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () { setState(() { _loading = true; _error = null; }); _loadFrames(); },
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Erneut versuchen'),
              ),
            ],
          ),
        ),
      );
    }

    final frame = _frames[_currentFrameIndex];
    final center = LatLng(widget.centerLat, widget.centerLon);
    final tileUrl = '${frame.path}/256/{z}/{x}/{y}/2/1_1.png';

    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: center,
                  initialZoom: 7,
                  // RainViewer tiles top out at zoom 7 — allowing more just
                  // triggers "zoom level not supported" errors from the tile
                  // layer. The base OSM layer can still upscale visually.
                  minZoom: 3,
                  maxZoom: 10,
                ),
                children: [
                  // Base map: OSM tiles.
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'de.icd360s.vorsitzer',
                    // OSM tile usage policy requires a real UA. maxNativeZoom
                    // caps the fetch level; higher zooms upscale the cached tile.
                    maxNativeZoom: 19,
                  ),
                  // RainViewer radar overlay for the current frame.
                  // Hard cap at native zoom 7 — that is the highest zoom the
                  // RainViewer tile pyramid publishes. Anything higher is
                  // upscaled from the zoom-7 tile.
                  TileLayer(
                    urlTemplate: tileUrl,
                    userAgentPackageName: 'de.icd360s.vorsitzer',
                    minNativeZoom: 0,
                    maxNativeZoom: 7,
                    // Semi-transparent so the base map stays readable.
                    tileBuilder: (ctx, tileWidget, _) => Opacity(opacity: 0.75, child: tileWidget),
                  ),
                  // Marker on the user's location.
                  MarkerLayer(markers: [
                    Marker(
                      point: center,
                      width: 30,
                      height: 30,
                      child: const Icon(Icons.my_location, size: 24, color: Colors.blue),
                    ),
                  ]),
                ],
              ),
              // Attribution — required by OSM AND RainViewer terms.
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  color: Colors.white.withValues(alpha: 0.75),
                  child: const Text(
                    'Karte: © OpenStreetMap · Radar: © RainViewer',
                    style: TextStyle(fontSize: 9, color: Colors.black87),
                  ),
                ),
              ),
              // Frame label — HH:mm + hint that this frame is a forecast.
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: frame.isForecast ? Colors.orange.shade700 : Colors.blue.shade700,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${frame.isForecast ? "Vorhersage" : "Radar"}  ${DateFormat('HH:mm', 'de_DE').format(frame.time)}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Colour legend — matches the RainViewer default palette (color=2)
        // so users can read the map without guessing. mm/h intensity buckets
        // reflect the DWD radar scale.
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              Text('Intensität:',
                  style: TextStyle(
                      fontSize: 10, color: Colors.grey.shade700, fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              _radarLegendChip(const Color(0xFF7FFF7F), 'sehr leicht'),
              _radarLegendChip(const Color(0xFF3ACC3A), 'leicht'),
              _radarLegendChip(const Color(0xFFFFFF00), 'mäßig'),
              _radarLegendChip(const Color(0xFFFF9500), 'stark'),
              _radarLegendChip(const Color(0xFFFF2A2A), 'Starkregen'),
              _radarLegendChip(const Color(0xFFB100FF), 'extrem'),
            ],
          ),
        ),
        const Divider(height: 1),
        // Timeline controls.
        Container(
          color: Colors.grey.shade100,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(
            children: [
              IconButton(
                icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle,
                    size: 30, color: Colors.blue.shade700),
                tooltip: _playing ? 'Pause' : 'Animation abspielen',
                onPressed: _togglePlay,
              ),
              Expanded(
                child: Slider(
                  min: 0,
                  max: (_frames.length - 1).toDouble(),
                  divisions: _frames.length - 1,
                  value: _currentFrameIndex.toDouble(),
                  onChanged: (v) => setState(() => _currentFrameIndex = v.round()),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text(
                  DateFormat('HH:mm', 'de_DE').format(frame.time),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _radarLegendChip(Color color, String label) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
              border: Border.all(color: Colors.grey.shade400, width: 0.5),
            ),
          ),
          const SizedBox(width: 2),
          Text(label, style: TextStyle(fontSize: 9, color: Colors.grey.shade800)),
        ],
      ),
    );
  }
}

class _RadarFrame {
  final DateTime time;
  final String path;   // tilecache.rainviewer.com/v2/radar/<hash>
  final bool isForecast;
  _RadarFrame({required this.time, required this.path, required this.isForecast});
}

/// Shimmering skeleton placeholder — mimics a real block while data is fetched.
/// Uses a subtle grey-to-lighter-grey linear gradient that slides horizontally.
class _SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double radius;

  const _SkeletonBox({
    this.width = double.infinity,
    this.height = 12,
    this.radius = 4,
  });

  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = _c.value * 3 - 1;
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.radius),
            gradient: LinearGradient(
              begin: Alignment(t - 0.3, 0),
              end: Alignment(t + 0.3, 0),
              colors: [
                Colors.grey.shade200,
                Colors.grey.shade100,
                Colors.grey.shade200,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
          ),
        );
      },
    );
  }
}

/// Skeleton content for the Umwelt tab while `currentAirQuality` is null.
class _UmweltSkeleton extends StatelessWidget {
  const _UmweltSkeleton();
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SkeletonBox(height: 70, radius: 10),
          const SizedBox(height: 14),
          const _SkeletonBox(width: 100, height: 12),
          const SizedBox(height: 8),
          for (int i = 0; i < 4; i++) ...[
            const Row(children: [
              _SkeletonBox(width: 120, height: 10),
              SizedBox(width: 12),
              Expanded(child: _SkeletonBox(height: 6)),
              SizedBox(width: 8),
              _SkeletonBox(width: 40, height: 10),
            ]),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 8),
          const _SkeletonBox(width: 100, height: 12),
          const SizedBox(height: 8),
          for (int i = 0; i < 3; i++) ...[
            const Row(children: [
              _SkeletonBox(width: 130, height: 10),
              Spacer(),
              _SkeletonBox(width: 40, height: 16, radius: 3),
            ]),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// Static German-language description block used by the pollutant info bottom
/// sheet. `what` = one-paragraph explanation, `affected` = risk groups,
/// `advice` = what to do when levels are elevated.
class _PollutantInfo {
  final String what;
  final String affected;
  final String advice;
  const _PollutantInfo({
    required this.what,
    required this.affected,
    required this.advice,
  });
}
