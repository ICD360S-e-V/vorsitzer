import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../services/weather_service.dart';

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

  const WeatherPill({
    super.key,
    required this.weather,
    required this.alertsCount,
    required this.compact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
            Text(weather.icon, style: TextStyle(fontSize: compact ? 16 : 18)),
            SizedBox(width: compact ? 3 : 4),
            if (compact)
              Text(
                '${weather.temperature.toStringAsFixed(0)}°',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
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
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if ((weather.apparentTemperature - weather.temperature).abs() >= 1) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(gefühlt ${weather.apparentTemperature.toStringAsFixed(0)}°)',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    weather.city.isEmpty ? weather.description : weather.city,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
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
  }

  @override
  void dispose() {
    widget.service.onWeatherUpdate = _prevWeatherCb;
    widget.service.onAlertsUpdate = _prevAlertsCb;
    widget.service.onAirQualityUpdate = _prevAirQualityCb;
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

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: SizedBox(
        width: 520,
        height: 620,
        child: DefaultTabController(
          length: 5,
          child: Column(
            children: [
              _buildHeader(context, weather),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildAktuellTab(weather, alerts),
                    _buildStuendlichTab(next24h, df),
                    _buildUmweltTab(),
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
              Text(weather.icon, style: const TextStyle(fontSize: 32)),
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
    return SingleChildScrollView(
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
                _detailColumn('Wind', '${weather.windSpeed.toStringAsFixed(0)} km/h ${weather.windCompass}', Icons.air),
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
                  _detailColumn(weather.isDay ? 'Tag' : 'Nacht',
                      weather.isDay ? '☀️' : '🌙', Icons.access_time),
                ],
              ),
            ),
          ],
          // Astronomy — sunrise/sunset + moon phase
          if (widget.service.currentAstronomy != null) ...[
            const SizedBox(height: 10),
            _buildAstronomyCard(widget.service.currentAstronomy!),
          ],
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
    );
  }

  Widget _buildStuendlichTab(List<HourlyForecast> next24h, DateFormat df) {
    if (next24h.isEmpty) return const Center(child: Text('Keine stündlichen Daten verfügbar'));
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: next24h.length,
      itemBuilder: (_, i) {
        final h = next24h[i];
        final isNow = i == 0;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: isNow ? Colors.blue.shade50 : (i.isEven ? Colors.grey.shade50 : null),
            borderRadius: BorderRadius.circular(6),
            border: isNow ? Border.all(color: Colors.blue.shade200) : null,
          ),
          child: Row(
            children: [
              SizedBox(
                width: 45,
                child: Text(
                  df.format(h.time),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: isNow ? FontWeight.bold : FontWeight.normal,
                    color: isNow ? Colors.blue.shade800 : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(h.icon, style: const TextStyle(fontSize: 18)),
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
        );
      },
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
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: weekForecast.length,
      itemBuilder: (_, i) {
        final d = weekForecast[i];
        final isToday = d.date.day == now.day && d.date.month == now.month;
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
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
              Text(d.icon, style: const TextStyle(fontSize: 20)),
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
      },
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
                Text(day.icon, style: const TextStyle(fontSize: 28)),
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
              const Text('🌅', style: TextStyle(fontSize: 20)),
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
              const Text('🌇', style: TextStyle(fontSize: 20)),
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
              Text(astro.moonEmoji, style: const TextStyle(fontSize: 20)),
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

  Widget _buildUmweltTab() {
    final aq = widget.service.currentAirQuality;
    if (aq == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Luftqualitäts-Daten werden geladen …',
              style: TextStyle(fontSize: 13, color: Colors.grey)),
        ),
      );
    }
    return SingleChildScrollView(
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
          Text('Schadstoffe (µg/m³)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade700)),
          const SizedBox(height: 6),
          _pollutantRow('Feinstaub PM2.5', aq.pm25, warnAbove: 25, dangerAbove: 50),
          _pollutantRow('Feinstaub PM10', aq.pm10, warnAbove: 50, dangerAbove: 100),
          _pollutantRow('Ozon (O₃)', aq.ozone, warnAbove: 120, dangerAbove: 180),
          _pollutantRow('Stickstoffdioxid (NO₂)', aq.nitrogenDioxide, warnAbove: 40, dangerAbove: 200),
          if (aq.sulphurDioxide != null && aq.sulphurDioxide! > 0)
            _pollutantRow('Schwefeldioxid (SO₂)', aq.sulphurDioxide, warnAbove: 40, dangerAbove: 250),
          if (aq.carbonMonoxide != null && aq.carbonMonoxide! > 0)
            _pollutantRow('Kohlenmonoxid (CO)', aq.carbonMonoxide, warnAbove: 4000, dangerAbove: 10000),
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
          const SizedBox(height: 12),
          Text(
            'Daten: CAMS via Open-Meteo Air Quality API',
            style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
          ),
        ],
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
      {required double warnAbove, required double dangerAbove}) {
    final v = value;
    final color = v == null
        ? Colors.grey
        : (v >= dangerAbove
            ? Colors.red.shade700
            : (v >= warnAbove ? Colors.orange.shade700 : Colors.green.shade700));
    final ratio = v == null ? 0.0 : (v / dangerAbove).clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 140,
            child: Text(label, style: const TextStyle(fontSize: 12)),
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
            width: 60,
            child: Text(
              v == null ? '—' : v.toStringAsFixed(1),
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            ),
          ),
        ],
      ),
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

/// Horizontal 15-min timeline (wetter.com-style). Scrollable.
/// Each cell: HH:mm • weather emoji • temperature • precip probability • precipitation bar.
/// The current cell (the one containing "now") is highlighted with a blue border.
///
/// Public — reused as a sticky bar under the dashboard AppBar so the user sees
/// the next hours' forecast without opening the dialog.
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

class _MinutelyTimeline extends StatelessWidget {
  final List<MinutelyForecast> entries;
  final bool compact;

  const _MinutelyTimeline({required this.entries, this.compact = false});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();

    final now = DateTime.now();
    // Only future/current slots (drop stale rows if the API returned them).
    final visible = entries
        .where((e) => !e.time.isBefore(now.subtract(const Duration(minutes: 15))))
        .toList();

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
                Text(e.icon, style: const TextStyle(fontSize: 18)),
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
                  Text(a.icon, style: const TextStyle(fontSize: 26)),
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
